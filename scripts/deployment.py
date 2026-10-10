#!/usr/bin/env python3
"""Deterministic installed generations. See docs/deployment.md for the state contract."""
import argparse
import ast
from contextlib import contextmanager, nullcontext
import fcntl
import hashlib
import io
import json
import os
from pathlib import Path
import re
import pwd
import shutil
import stat
import subprocess
import sys
import tomllib
from urllib.parse import urlsplit, urlunsplit
import uuid

sys.dont_write_bytecode = True
from skill_discovery import discover_skills

MISSING = object()
HOME_FILES = {".bashrc", ".inputrc", ".profile", ".gitignore_global", ".nvim-cheatsheet.md",
              ".welcome.md", ".packages.md", ".tmux.conf"}
SECRET_NAMES = {"auth.json", "models-store.json", "user_credentials.json", ".env",
                ".dotfiles_bootstrap_config", ".git-credentials", ".netrc", ".npmrc",
                "credentials.json", "auth.toml", ".ssh", ".claude.json"}


class Pending(ValueError):
    pass


def git(root, *args, check=True):
    result = subprocess.run(["git", "-C", str(root), *args], capture_output=True)
    if check and result.returncode:
        # Git diagnostics can contain credentials from remote URLs.
        raise Pending(f"Source git operation failed: {args[0]}; inspect the source checkout locally")
    return result


def clean_url(raw):
    raw = raw.strip()
    if raw.startswith("git@"):
        raw = "https://" + raw[4:].replace(":", "/", 1)
    parsed = urlsplit(raw)
    if parsed.scheme not in {"https", "http", "ssh", "file"}:
        raise Pending("Unsupported source URL; configure a credential-free origin")
    host = parsed.hostname or ""
    if parsed.port:
        host += f":{parsed.port}"
    return urlunsplit(("https" if parsed.scheme == "ssh" else parsed.scheme,
                       host, parsed.path.removesuffix(".git"), "", ""))


def read_json(path, default=None):
    return json.loads(path.read_text()) if path.exists() else default


def write_json(path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.parent / (".dfa-state-" + uuid.uuid4().hex)
    with temporary.open("x") as file:
        temporary.chmod(0o600)
        file.write(json.dumps(data, sort_keys=True, indent=2) + "\n")
        file.flush(); os.fsync(file.fileno())
    os.replace(temporary, path)
    descriptor = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def lexical(path):
    return Path(os.path.abspath(path))


def link_value(path):
    return str(lexical(path.parent / os.readlink(path))) if path.is_symlink() else None


def identity(path):
    if path.is_symlink():
        return {"kind": "link", "target": os.readlink(path)}
    if path.is_file():
        return {"kind": "file", "sha256": hashlib.sha256(path.read_bytes()).hexdigest(),
                "mode": stat.S_IMODE(path.stat().st_mode)}
    if path.exists():
        raise Pending(f"Unsupported artifact type: {path}")
    return None


def copy_file(source, dest):
    dest.parent.mkdir(parents=True, exist_ok=True)
    if source.is_symlink():
        dest.symlink_to(os.readlink(source))
    else:
        shutil.copy2(source, dest)


def safe_parents(path, boundary):
    for parent in [path.parent, *path.parent.parents]:
        if parent == boundary:
            break
        if parent.is_symlink():
            raise Pending(f"Redirected parent preserved: {parent}")


def json_value(data):
    def pairs(items):
        result = {}
        for key, value in items:
            if key in result:
                raise Pending(f"Duplicate JSON key: {key}")
            result[key] = value
        return result
    return json.loads(data, object_pairs_hook=pairs,
                      parse_constant=lambda value: (_ for _ in ()).throw(Pending(f"Invalid JSON: {value}")))


def same(left, right):
    if type(left) is not type(right):
        return False
    if isinstance(left, dict):
        return left.keys() == right.keys() and all(same(left[k], right[k]) for k in left)
    if isinstance(left, list):
        return len(left) == len(right) and all(same(a, b) for a, b in zip(left, right))
    return left == right


def reconcile(base, live, incoming):
    # Missing keys have an identity distinct from JSON null. Arrays are atomic.
    if same(live, base):
        return incoming
    if same(incoming, base) or same(live, incoming):
        return live
    if all(isinstance(item, dict) for item in (base, live, incoming)):
        merged = {}
        for key in sorted(base.keys() | live.keys() | incoming.keys()):
            value = reconcile(base.get(key, MISSING), live.get(key, MISSING), incoming.get(key, MISSING))
            if value is not MISSING:
                merged[key] = value
        return merged
    raise Pending("Competing edits, deletion versus edit, or incompatible types")


def parsed_json(path, data):
    # JSONC is accepted only for known comment-capable app paths and .jsonc.
    comments = path.suffix == ".jsonc" or str(path).endswith(("config/zed/settings.json", "config/zed/keymap.json"))
    if comments:
        pattern = r'"(?:[^"\\]|\\.)*"|//[^\n]*|/\*.*?\*/|,\s*(?=[}\]])'
        data = re.sub(pattern, lambda m: m[0] if m[0].startswith('"') else " " if m[0].startswith("/") else "",
                      data.decode() if isinstance(data, bytes) else data, flags=re.S)
    return json_value(data)


def validate(path):
    if path.is_symlink():
        return
    data = path.read_bytes()
    if path.suffix in {".json", ".jsonc"}:
        parsed_json(path, data)
    elif path.suffix == ".toml":
        tomllib.loads(data.decode())
    elif path.suffix == ".py":
        ast.parse(data, filename=str(path))
    elif data.startswith((b"#!/bin/bash", b"#!/usr/bin/env bash")) or path.suffix == ".sh":
        result = subprocess.run(["bash", "-n", str(path)], capture_output=True)
        if result.returncode:
            raise Pending("Bash syntax validation failed")
    # Format parsing checks syntax. Application schemas/runtime remain unverified.


def has_literal_credentials(path):
    if path.suffix in {".json", ".jsonc"}:
        value = parsed_json(path, path.read_bytes())
    elif path.suffix == ".toml":
        value = tomllib.loads(path.read_text())
    else:
        return False
    def contains(item):
        if isinstance(item, dict):
            for key, child in item.items():
                sensitive = key.lower().replace("_", "").replace("-", "") in {
                    "password", "apikey", "token", "bottoken", "accesstoken", "refreshtoken", "secret"}
                reference = isinstance(child, str) and (re.fullmatch(r"[A-Z][A-Z0-9_]*", child)
                            or child.startswith(("env:", "{env:", "$")))
                if sensitive and isinstance(child, str) and child and not reference:
                    return True
                if contains(child):
                    return True
        elif isinstance(item, list):
            return any(contains(child) for child in item)
        return False
    return contains(value)


def merge_file(base, live, incoming, candidate):
    b, l, i = identity(base), identity(live), identity(incoming)
    kinds = {value["kind"] for value in (b, l, i) if value is not None}
    if b is not None and l is None and i is not None:
        raise Pending("Managed live artifact is missing; restore it or select an explicit override")
    if b is not None and len(kinds) > 1:
        raise Pending("Artifact kind change; select an explicit override")
    if b and b["kind"] == "file" and i != b and l != i:
        for path in (base, live, incoming):
            if identity(path) and identity(path)["kind"] == "file":
                try:
                    data = path.read_bytes().decode("utf-8")
                except UnicodeError as error:
                    raise Pending("Unsupported binary change; select an explicit override") from error
                if "\0" in data:
                    raise Pending("Unsupported binary change; select an explicit override")
    if l == b:
        selected = incoming
    elif i == b or l == i:
        selected = live
    else:
        if not all(value and value["kind"] == "file" for value in (b, l, i)):
            raise Pending("Missing baseline, deletion versus local edit, or artifact type conflict")
        try:
            texts = [path.read_bytes().decode("utf-8") for path in (base, live, incoming)]
        except UnicodeError as error:
            raise Pending("Unsupported binary merge") from error
        if any("\0" in data for data in texts):
            raise Pending("Unsupported binary merge")
        candidate.parent.mkdir(parents=True, exist_ok=True)
        jsonc = candidate.suffix == ".jsonc" or str(candidate).endswith(("config/zed/settings.json", "config/zed/keymap.json"))
        if candidate.suffix == ".json" and not jsonc:
            merged = reconcile(*(json_value(data) for data in texts))
            candidate.write_text(json.dumps(merged, indent=2, ensure_ascii=False) + "\n")
        else:
            if jsonc:
                # Semantic conflicts (including atomic arrays) must also reject clean textual merges.
                reconcile(*(parsed_json(candidate, data) for data in texts))
            result = subprocess.run(["git", "merge-file", "-p", str(live), str(base), str(incoming)],
                                    capture_output=True)
            if result.returncode:
                raise Pending("Text merge conflict; live file unchanged")
            candidate.write_bytes(result.stdout)
        mode = reconcile(b["mode"], l["mode"], i["mode"])
        candidate.chmod(mode)
        validate(candidate)
        return
    if identity(selected) is not None:
        copy_file(selected, candidate)
        validate(candidate)


class Deployment:
    def __init__(self, home, working_tree=False):
        self.working_tree = working_tree
        self.home = lexical(home)
        self.root = self.home / ".local/share/workstation"
        self.active = self.root / "config"
        self.schema = self.home / ".config/dotfiles-arch/.dotfiles_schema_version"

    @contextmanager
    def locked(self):
        safe_parents(self.root / "lock", self.home)
        self.root.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.root.chmod(0o700)
        if (self.root / "lock").is_symlink():
            raise Pending("Deployment lock is redirected")
        for directory in ("staging", "generations", "overrides"):
            safe_parents(self.root / directory / "artifact", self.root)
        with (self.root / "lock").open("a") as lock:
            os.chmod(lock.name, 0o600)
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError as error:
                raise Pending("Another deployment is running; retry when it finishes") from error
            if (self.root / "transaction.json").exists():
                raise Pending("Interrupted activation; run dfa-deploy recover before retrying")
            yield

    def current(self):
        if not self.active.is_symlink():
            if self.active.exists():
                raise Pending("Deployment config path is a foreign real directory")
            return None, {"artifacts": {}, "links": {}, "sources": []}
        tree = self.active.resolve()
        if tree.parent.parent != self.root / "generations" or tree.name != "tree":
            raise Pending("Deployment config link is foreign")
        manifest = read_json(tree.parent / "manifest.json")
        if not manifest or manifest.get("version") != 1 or not isinstance(manifest.get("artifacts"), dict) or not isinstance(manifest.get("links"), dict) or not manifest.get("sources"):
            raise Pending("Missing or invalid deployment provenance; restore a recorded generation")
        for key in manifest["artifacts"]:
            if Path(key).is_absolute() or ".." in Path(key).parts:
                raise Pending("Invalid artifact provenance; restore a recorded generation")
            override_key = manifest["artifacts"][key].get("override_artifact", key)
            if not isinstance(override_key, str) or not override_key or Path(override_key).is_absolute() or ".." in Path(override_key).parts:
                raise Pending("Invalid override provenance; restore a recorded generation")
        for source in manifest["sources"]:
            if not re.fullmatch(r"primary|[0-9a-f]{16}", source.get("id", "")) or not Path(source.get("path", "")).is_absolute():
                raise Pending("Invalid source provenance; restore a recorded generation")
        return tree, manifest

    def source(self, explicit=None):
        _, manifest = self.current()
        previous = manifest["sources"][0] if manifest["sources"] else None
        path = Path(explicit).resolve() if explicit else Path(previous["path"]) if previous else None
        if path is None or not (path / "scripts/sync.sh").is_file():
            raise Pending("Source checkout unavailable; restore it or run dfa-deploy rebind /actual/checkout. Installed tools remain usable")
        if self.root == path or self.root in path.parents:
            raise Pending("Installed copies cannot be used as the editable source")
        url = clean_url(git(path, "remote", "get-url", "origin").stdout.decode())
        commit = git(path, "rev-parse", "HEAD").stdout.decode().strip()
        if previous and (str(path) != previous["path"] or url != previous["url"]):
            raise Pending("Source provenance differs; explicitly use dfa-deploy rebind PATH [--accept-origin-change]")
        if previous and git(path, "merge-base", "--is-ancestor", previous["commit"], commit,
                            check=False).returncode:
            raise Pending("Recorded source commit is not in this checkout history; restore the recorded source")
        return path

    def source_path(self, identifier):
        if identifier == "primary":
            return self.source()
        _, manifest = self.current()
        origin = next((s for s in manifest["sources"] if s["id"] == identifier), None)
        if origin is None:
            raise Pending("Select a recorded source ID from dfa-deploy status")
        path = Path(origin["path"])
        if not path.is_dir() or path.is_relative_to(self.root):
            raise Pending("Extra source unavailable; restore or explicitly rebind its source ID")
        if origin["commit"]:
            url = clean_url(git(path, "remote", "get-url", "origin").stdout.decode())
            if url != origin["url"] or git(path, "merge-base", "--is-ancestor", origin["commit"], "HEAD", check=False).returncode:
                raise Pending("Extra source provenance differs; explicitly rebind the recorded source ID")
        return path

    def sources(self, primary):
        entries = [(primary, "standard", False, "primary")]
        _, installed = self.current()
        previous_ids = {(s["path"], s["type"]): s["id"] for s in installed["sources"][1:]}
        previous_ids.update(getattr(self, "rebound_sources", {}))
        config = self.home / ".config/dotfiles-arch/sync-sources"
        if config.exists():
            for line in config.read_text().splitlines():
                if not line.strip() or line.lstrip().startswith("#"):
                    continue
                spec, *options = line.split("\t")
                kind, sep, path = spec.partition(":")
                if not sep:
                    kind, path = "standard", spec
                if kind not in {"standard", "skills-root", "rules-root", "extensions-root"}:
                    raise Pending("Unknown extra source type")
                if options and options != ["overwritable=true"] and options != ["overwritable=false"]:
                    raise Pending("Invalid overwritable value")
                path = Path(path.replace("~", str(self.home), 1) if path.startswith("~/") else path).resolve()
                if not path.is_dir():
                    raise Pending(f"Configured source unavailable: {path}; restore or unregister it explicitly")
                name = previous_ids.get((str(path), kind), hashlib.sha256(f"{kind}:{path}".encode()).hexdigest()[:16])
                if name in {s["id"] for s in installed["sources"][1:]} and name not in getattr(self, "rebound_sources", {}).values():
                    self.source_path(name)
                entries.append((path, kind, options == ["overwritable=true"], name))
        return entries

    def inventory(self, primary, incoming):
        artifacts, links, sources = {}, {}, []
        roots, overwritable, rules_bodies = [], [], []
        rule_entries = []
        pi = lexical(os.environ.get("PI_CODING_AGENT_DIR", self.home / ".pi/agent"))
        codex = lexical(os.environ.get("CODEX_HOME", self.home / ".codex"))
        def add_link(target, relative, legacy):
            links[str(target)] = {"artifact": relative, "legacy": str(lexical(legacy))}
        for path, kind, can_replace, name in self.sources(primary):
            git_source = git(path, "rev-parse", "--show-toplevel", check=False)
            is_git = git_source.returncode == 0
            source = {"id": name, "path": str(path), "type": kind, "overwritable": can_replace,
                      "url": clean_url(git(path, "remote", "get-url", "origin").stdout.decode()) if is_git else None,
                      "commit": git(path, "rev-parse", "HEAD").stdout.decode().strip() if is_git else None}
            sources.append(source)
            working_tree = is_git and self.working_tree and name == "primary"
            if working_tree:
                source["working_tree"] = hashlib.sha256(git(path, "status", "--porcelain", "-z", "--untracked-files=all").stdout).hexdigest()
            prefix = "" if name == "primary" else f"extras/{name}/"
            committed = {}
            if is_git and not working_tree:
                prefix_in_git = git(path, "rev-parse", "--show-prefix").stdout.decode().strip().rstrip("/")
                revision = source["commit"] + (":" + prefix_in_git if prefix_in_git else "")
                entries = []
                for record in git(path, "ls-tree", "--full-tree", "-rz", revision).stdout.split(b"\0"):
                    if not record:
                        continue
                    metadata, filename = record.split(b"\t", 1)
                    mode, kind_in_git, object_id = metadata.split()
                    relative = Path(os.fsdecode(filename))
                    if kind_in_git != b"blob" or any(part in SECRET_NAMES or part in {".git", "node_modules", "__pycache__"}
                                                   or part.startswith(".env.") for part in relative.parts):
                        continue
                    entries.append((relative, mode, object_id))
                # Raw blobs ignore export-ignore/export-subst attributes and avoid reading excluded secrets.
                batch = subprocess.run(["git", "-C", str(path), "cat-file", "--batch"],
                                       input=b"".join(oid + b"\n" for _, _, oid in entries), capture_output=True)
                if batch.returncode:
                    raise Pending("Cannot read committed source blobs")
                stream = io.BytesIO(batch.stdout)
                for relative, mode, object_id in entries:
                    header = stream.readline().split()
                    if len(header) != 3 or header[0] != object_id or header[1] != b"blob":
                        raise Pending("Invalid committed source blob response")
                    data = stream.read(int(header[2]))
                    if stream.read(1) != b"\n":
                        raise Pending("Incomplete committed source blob")
                    committed[relative] = {"target": data.decode() if mode == b"120000" else None,
                                           "data": None if mode == b"120000" else data,
                                           "mode": 0o755 if mode == b"100755" else 0o644}
                files = list(committed)
            elif working_tree:
                files = {Path(os.fsdecode(p)) for p in git(path, "ls-files", "-z", "--cached", "--others",
                                                          "--exclude-standard").stdout.split(b"\0") if p}
            else:
                files = [p.relative_to(path) for p in path.rglob("*") if p.is_file() or p.is_symlink()]
            for relative in sorted(files):
                if relative.is_absolute() or ".." in relative.parts:
                    raise Pending("Unsafe source artifact path")
                if any(p in SECRET_NAMES or p in {".git", "node_modules", "__pycache__"}
                       or p.startswith(".env.") for p in relative.parts):
                    continue
                src = path / relative
                if (not is_git or working_tree) and not src.exists() and not src.is_symlink():
                    continue
                if (not is_git or working_tree) and src.is_dir() and not src.is_symlink():
                    continue
                key = prefix + relative.as_posix()
                dest = incoming / key
                if working_tree:
                    safe_parents(src, path)
                link = committed[relative]["target"] if is_git and not working_tree else os.readlink(src) if src.is_symlink() else None
                if link is not None:
                    resolved = lexical(src.parent / link)
                    # Explicit rebind retains the mapping for old absolute internal source links.
                    if not resolved.is_relative_to(path):
                        _, previous = self.current()
                        old_source = next((entry for entry in previous["sources"] if entry["id"] == name), None)
                        if old_source and resolved.is_relative_to(old_source["path"]):
                            resolved = path / resolved.relative_to(old_source["path"])
                    if not resolved.is_relative_to(path):
                        raise Pending(f"External source symlink: {src}")
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    target = incoming / prefix / resolved.relative_to(path)
                    dest.symlink_to(os.path.relpath(target, dest.parent))
                elif is_git and not working_tree:
                    dest.parent.mkdir(parents=True, exist_ok=True)
                    dest.write_bytes(committed[relative]["data"])
                    dest.chmod(committed[relative]["mode"])
                else:
                    copy_file(src, dest)
                artifacts[key] = {"source": name, "relative": relative.as_posix(),
                                  "origin": str(src), "source_identity": identity(src), "incoming": identity(dest)}
                if name == "primary":
                    if relative.parts[0] == "home":
                        sub = relative.relative_to("home")
                        if str(sub) in HOME_FILES or str(sub).startswith(".local/bin/"):
                            add_link(self.home / sub, key, src)
                    elif relative.parts[0] == "config":
                        add_link(self.home / ".config" / relative.relative_to("config"), key, src)
                    elif relative.parts[0] == "pi" and "extensions" not in relative.parts:
                        add_link(pi / relative.relative_to("pi"), key, src)
            staged = incoming / prefix
            if kind == "standard" and (staged / "pi").is_dir():
                settings = read_json(pi / "settings.json", {})
                if not isinstance(settings, dict) or not isinstance(settings.get("packages", []), list):
                    raise Pending("Invalid Pi package settings; preserve and reconcile them before source sync")
                legacy_skill_paths = {str(self.home / ".claude/skills"), str(codex / "skills")}
                for value in settings.get("skills", []) if isinstance(settings.get("skills", []), list) else []:
                    if isinstance(value, str) and value.replace("$HOME", str(self.home)).replace("~", str(self.home), 1) in legacy_skill_paths:
                        raise Pending("Pi settings also load cross-harness skills; remove those legacy paths with the standalone owner before generation syncing")
                package = read_json(staged / "package.json", {})
                for entry in settings.get("packages", []):
                    value = entry.get("source") if isinstance(entry, dict) else entry
                    if not isinstance(value, str):
                        continue
                    if value.startswith("npm:"):
                        match = re.match(r"npm:((?:@[^/]+/)?[^@]+)", value)
                        duplicate = isinstance(package, dict) and match and match[1] == package.get("name")
                    elif value.startswith(("git:", "git+", "github:", "https://", "http://", "ssh://")):
                        raw = value.removeprefix("git:").removeprefix("git+")
                        if raw.startswith("github:"):
                            raw = "https://github.com/" + raw.removeprefix("github:")
                        parsed = urlsplit(raw if "://" in raw else "https://" + raw)
                        remote = urlunsplit((parsed.scheme, parsed.netloc, parsed.path.split("@", 1)[0], "", ""))
                        duplicate = clean_url(remote) == source["url"]
                    else:
                        local = Path(value.replace("~", str(self.home), 1) if value.startswith("~/") else value)
                        duplicate = (local if local.is_absolute() else pi / local).resolve() == path
                    if duplicate:
                        raise Pending(f"Native Pi package duplicates registered source data: {path}; remove that native resource package explicitly before generation syncing")
            skills = staged / "skills" if kind == "standard" else staged if kind == "skills-root" else None
            if skills and skills.is_dir():
                roots.append(skills)
                if can_replace:
                    overwritable.append(skills)
            extensions = staged / "pi/extensions" if (staged / "pi/extensions").is_dir() else staged / "extensions"
            if kind == "extensions-root":
                extensions = staged
            if kind in {"standard", "extensions-root"} and extensions.is_dir():
                for entry in sorted(extensions.iterdir()):
                    key = entry.relative_to(incoming).as_posix()
                    add_link(pi / "extensions" / entry.name, key, path / entry.relative_to(staged))
            # Standard sources may carry Pi data beside skills/rules.  Skills and
            # prompts are discovered by their native locations; the remaining
            # shared Pi files are linked from the retained generation below.
            if kind == "standard":
                pi_root = staged / "pi"
                if pi_root.is_dir():
                    for entry in sorted(pi_root.rglob("*")):
                        if not (entry.is_file() or entry.is_symlink()):
                            continue
                        relative = entry.relative_to(pi_root)
                        if relative.parts[0] == "extensions":
                            continue
                        if relative.parts[0] not in {"agents", "prompts"} and relative.parts not in {
                                ("models.json",), ("settings.json",)}:
                            continue
                        key = prefix + (Path("pi") / relative).as_posix()
                        if key in artifacts:
                            add_link(pi / relative, key, path / "pi" / relative)

            rules = staged / "rules" if kind == "standard" else staged if kind == "rules-root" else None
            if rules and rules.is_dir():
                for rule in sorted(rules.iterdir()):
                    if rule.suffix not in {".md", ".mdc"} or rule.name.lower() == "readme.md":
                        continue
                    text = rule.read_text()
                    fields, body = {}, text
                    if text.startswith("---\n"):
                        parts = text.split("---\n", 2)
                        if len(parts) != 3:
                            raise Pending(f"Invalid rule frontmatter: {rule.name}")
                        fields = dict(line.split(":", 1) for line in parts[1].splitlines() if ":" in line)
                        body = parts[2]
                    elif rule.suffix == ".md":
                        continue
                    rule_entries.append((name, path, rule, text, fields, body, staged))
        # Registered extras are applied first so the primary source remains the
        # final rule authority.  De-duplicate by basename across every consumer.
        ordered_rules = [entry for entry in rule_entries if entry[0] != "primary"]
        ordered_rules += [entry for entry in rule_entries if entry[0] == "primary"]
        selected_rules = {}
        for entry in ordered_rules:
            selected_rules[entry[2].stem] = entry
        for entry in ordered_rules:
            name, path, rule, text, fields, body, staged = entry
            if selected_rules[rule.stem] is not entry:
                continue
            key = f"generated/rules/{name}/{rule.stem}.mdc"
            out = incoming / key; out.parent.mkdir(parents=True, exist_ok=True)
            out.write_text(text)
            artifacts[key] = {"source": None, "origin": str(path / rule.relative_to(staged)),
                              "incoming": identity(out)}
            slug = str(path).lstrip("/").replace("/", "-")
            add_link(self.home / ".cursor/rules" / (rule.stem + ".mdc"), key,
                     self.home / ".config/dotfiles-arch/rules-build" / slug / "mdc" / (rule.stem + ".mdc"))
            if fields.get("alwaysApply", "").strip() == "true":
                rules_bodies.append(f"<!-- source: {path} -->\n\n{body}\n")
        alias_key = "home/.local/bin/rebind-window-push"
        if alias_key in artifacts:
            add_link(self.home / ".local/bin/rebind-monitor-moves", alias_key, primary / alias_key)
        # Primary skills have final priority. Reuse the established collision policy.
        roots = [r for r in roots if r != incoming / "skills"] + ([incoming / "skills"] if (incoming / "skills").is_dir() else [])
        for skill in discover_skills(roots, overwritable):
            key = skill.relative_to(incoming).as_posix()
            entry = next(s for s in sources if key.startswith(f"extras/{s['id']}/")) if key.startswith("extras/") else sources[0]
            relative = key.split("/", 2)[2] if key.startswith("extras/") else key
            for dest in (self.home / ".claude/skills", self.home / ".cursor/skills", codex / "skills", pi / "skills"):
                add_link(dest / skill.name, key, Path(entry["path"]) / relative)
        destinations = "\n".join(f"- {s['id']}: {s['path']} ({s['type']})" for s in sources)
        guidance = ("<!-- managed-by: dotfiles-arch dfa-sync-rules -->\n\n"
                    "These are installed DFA copies. Shared edits belong in the actual source checkout, "
                    f"currently {primary}. Provenance is ~/.local/share/workstation/config/../manifest.json "
                    "(resolve config first). Before editing shared configuration run `dfa-deploy source`; "
                    "if provenance or the checkout is missing, stop source editing and use "
                    "`dfa-deploy rebind /actual/checkout`. Never use installed copies as the source. "
                    "Use `dfa-deploy override ARTIFACT FILE` for intentional local overrides; "
                    "use `dfa-deploy capture ARTIFACT` to select a local improvement for source review. "
                    "Capture does not commit or push. For extra-source artifacts use the manifest origin and "
                    "verify it with `dfa-deploy source --source-id ID`. See `dfa-deploy help` for recovery.\n\n"
                    f"Recorded shared edit destinations:\n{destinations}\n\n")
        key = "generated/AGENTS.md"
        output = incoming / key; output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(guidance + "\n".join(rules_bodies))
        artifacts[key] = {"source": None, "origin": "generated instructions", "incoming": identity(output)}
        legacy = self.home / ".config/dotfiles-arch/rules-build/pi-agents.md"
        for dest in (codex / "AGENTS.md", pi / "AGENTS.md", self.home / ".config/opencode/AGENTS.md"):
            add_link(dest, key, legacy)
        # A separate import preserves user-written Claude instructions.
        add_link(self.home / ".claude/dfa-deployment.md", key, self.home / ".claude/dfa-deployment.md")
        key = "generated/dfa-deployment.mdc"
        output = incoming / key
        output.write_text("---\ndescription: DFA installed-copy edit destinations\nalwaysApply: true\n---\n" + guidance)
        artifacts[key] = {"source": None, "origin": "generated instructions", "incoming": identity(output)}
        add_link(self.home / ".cursor/rules/dfa-deployment.mdc", key, self.home / ".cursor/rules/dfa-deployment.mdc")
        key = "DEPLOYMENT-README.md"
        output = incoming / key
        output.write_text(guidance_readme(primary))
        artifacts[key] = {"source": None, "origin": "installed-copy guidance", "incoming": identity(output)}
        return artifacts, links, sources

    def link_snapshot(self, target, info, old):
        path = Path(target)
        safe_parents(path, self.home)
        expected = str(self.active / info["artifact"])
        value = link_value(path)
        previous = old.get(target)
        if value == expected or (previous and value == str(self.active / previous["artifact"])):
            return {"kind": "link", "target": os.readlink(path)}
        if value == info.get("legacy") and value != str(path):
            if not path.exists():
                raise Pending(f"Broken legacy link preserved: {path}; restore the source before migrating")
            return {"kind": "link", "target": os.readlink(path)}
        if path.exists() or path.is_symlink():
            raise Pending(f"Unmanaged target preserved: {path}; relocate it explicitly before deployment")
        return None

    def preserve_unknown_files(self, tree, artifacts):
        for path in sorted(tree.rglob("*")):
            if (path.is_file() or path.is_symlink()) and path.relative_to(tree).as_posix() not in artifacts:
                raise Pending(f"Unmanifested installed file preserved: {path}; move it outside managed copies")

    def preserve_legacy_directories(self, links, snapshots, artifacts):
        known = {lexical(item["origin"]) for item in artifacts.values() if item.get("source")}
        for target, info in links.items():
            legacy = Path(info["legacy"])
            if snapshots[target] and link_value(Path(target)) == str(legacy) and legacy.is_dir():
                for path in sorted(legacy.rglob("*")):
                    if (path.is_file() or path.is_symlink()) and lexical(path) not in known:
                        raise Pending(f"Unmanaged legacy descendant preserved: {path}; track it explicitly or move it outside the managed folder before migration")

    def source_handoffs(self, incoming, artifacts, sources, old, tree):
        """Explicit primary-source moves reuse old B/L and persistent override keys."""
        for key in artifacts.keys() & old["artifacts"].keys():
            if "override_artifact" in old["artifacts"][key]:
                artifacts[key]["override_artifact"] = old["artifacts"][key]["override_artifact"]
        config = read_json(incoming / ".dfa-source-handoffs.json", {"version": 1, "moves": []})
        if not isinstance(config, dict) or config.get("version") != 1 or not isinstance(config.get("moves"), list):
            raise Pending("Invalid source handoff configuration")
        moves = {}
        for move in config["moves"]:
            if not isinstance(move, dict) or set(move) != {"from", "to", "source"}:
                raise Pending("Invalid source handoff entry")
            for field in ("from", "to"):
                value = move[field]
                if not isinstance(value, str) or not value or Path(value).is_absolute() or any(p in {"..", "."} for p in value.split("/")):
                    raise Pending("Unsafe source handoff path")
            destinations = [s for s in sources[1:] if s["type"] == "standard" and s["url"] == move["source"]]
            for old_key, item in old["artifacts"].items():
                source_backed = item.get("source") == "primary" and Path(old_key).is_relative_to(move["from"])
                generated_rule = move["from"] == "rules" and move["to"] == "rules" and old_key.startswith("generated/rules/primary/")
                if old_key in artifacts or not (source_backed or generated_rule):
                    continue
                if len(destinations) != 1:
                    raise Pending("Source handoff requires exactly one manually registered replacement source; restore/register it before deploying")
                if generated_rule:
                    relative = Path("generated/rules") / destinations[0]["id"] / Path(old_key).name
                    new_key = relative.as_posix()
                else:
                    relative = Path(move["to"]) / Path(old_key).relative_to(move["from"])
                    new_key = f"extras/{destinations[0]['id']}/{relative.as_posix()}"
                if new_key not in artifacts:
                    raise Pending(f"Replacement source is missing handoff artifact: {relative}")
                if new_key in moves or old_key in moves.values():
                    raise Pending("Ambiguous source handoff; retain the original source and resolve duplicate identities")
                if new_key in old["artifacts"]:
                    destination_base = identity(tree.parent / "baseline" / new_key)
                    if destination_base != old["artifacts"][new_key]["baseline"] or identity(tree / new_key) != destination_base:
                        raise Pending(f"Replacement artifact also has local edits or an altered baseline: {new_key}; reconcile both copies before handoff")
                    if (self.root / "overrides" / new_key).exists():
                        raise Pending(f"Replacement artifact also has an override: {new_key}; reconcile both overrides before handoff")
                moves[new_key] = old_key
                artifacts[new_key]["override_artifact"] = item.get("override_artifact", old_key)
        return moves

    def deploy(self, primary, locked=False):
        with nullcontext() if locked else self.locked():
            tree, old = self.current()
            identifier = uuid.uuid4().hex
            stage = self.root / "staging" / identifier
            stage.mkdir(parents=True, mode=0o700)
            incoming, candidate, baseline = stage / "incoming", stage / "tree", stage / "baseline"
            incoming.mkdir(); candidate.mkdir(); baseline.mkdir()
            errors = []
            registry = self.home / ".config/dotfiles-arch/sync-sources"
            registry_before = identity(registry)
            try:
                artifacts, links, sources = self.inventory(primary, incoming)
                moves = self.source_handoffs(incoming, artifacts, sources, old, tree)
                # A content-derived staging key gives repeated identical conflicts identical evidence paths.
                state = {"incoming": artifacts, "sources": sources, "previous": old,
                         "live": {key: identity(tree / key) for key in old["artifacts"]} if tree else {},
                         "baseline": {key: identity(tree.parent / "baseline" / key) for key in old["artifacts"]} if tree else {},
                         "overrides": {key: identity(self.root / "overrides" / artifacts[key].get("override_artifact", key)) for key in artifacts},
                         "targets": {target: {"link": identity(Path(target)) if not Path(target).is_dir() or Path(target).is_symlink() else "directory",
                                     "content": identity(Path(target).resolve()) if Path(target).is_file() else None}
                                     for target in links}}
                identifier = hashlib.sha256(json.dumps(state, sort_keys=True).encode()).hexdigest()
                canonical = self.root / "staging" / identifier
                if canonical.exists():
                    blocked = read_json(canonical / "blocked.json")
                    if blocked:
                        shutil.rmtree(stage)
                        raise Pending("Deployment pending; active files unchanged\n" + "\n".join(blocked))
                    # Preserve prior uncommitted stage evidence instead of overwriting it.
                    suffix = 1
                    while (self.root / "staging" / f"{identifier}-{suffix}").exists():
                        suffix += 1
                    canonical = self.root / "staging" / f"{identifier}-{suffix}"
                stage.rename(canonical); stage = canonical
                incoming, candidate, baseline = stage / "incoming", stage / "tree", stage / "baseline"
                write_json(stage / "inventory.json", {"artifacts": artifacts, "sources": sources})
                snapshots = {target: self.link_snapshot(target, info, old["links"])
                             for target, info in links.items()}
                for target, info in old["links"].items():
                    if target not in links:
                        snapshots[target] = self.link_snapshot(target, info, old["links"])
                if not tree:
                    self.preserve_legacy_directories(links, snapshots, artifacts)
                observed = {key + ":replacement": {"path": str(tree / key), "identity": identity(tree / key)}
                            for key in moves if key in old["artifacts"]}
                for key in sorted((artifacts.keys() | old["artifacts"].keys()) - set(moves.values())):
                    old_key = moves.get(key, key)
                    live = (tree / old_key) if tree else stage / "absent-live" / key
                    base = (tree.parent / "baseline" / old_key) if tree else stage / "absent-base" / key
                    inc = incoming / key
                    if not tree:
                        # A legacy layout's Git HEAD is trusted source B/I; its working
                        # checkout is L, including local edits in runtime dependencies.
                        migrating = any(snapshot is not None for snapshot in snapshots.values())
                        item = artifacts.get(key, {})
                        if migrating and item.get("source"):
                            origin = next(entry for entry in sources if entry["id"] == item["source"])
                            live = Path(item["origin"])
                            if origin["commit"] and identity(inc) is not None:
                                base.parent.mkdir(parents=True, exist_ok=True)
                                copy_file(inc, base)
                        else:
                            for target, info in links.items():
                                if info["artifact"] == key and snapshots[target] and Path(info["legacy"]).is_file():
                                    live = Path(info["legacy"])
                                    break
                    observed[key] = {"path": str(live), "identity": identity(live)}
                    try:
                        if tree and old_key in old["artifacts"] and identity(base) != old["artifacts"][old_key]["baseline"]:
                            raise Pending("Missing or altered source baseline; recover a retained generation")
                        override = self.root / "overrides" / artifacts.get(key, old["artifacts"].get(old_key, {})).get("override_artifact", key)
                        if override.exists():
                            if key not in artifacts or not override.is_file() or override.is_symlink():
                                raise Pending("Override no longer has an incoming managed artifact")
                            copy_file(override, candidate / key); validate(candidate / key)
                        else:
                            # Initial unequal generated copies have no trustworthy source baseline.
                            if not tree and identity(base) is None and identity(live) is not None and identity(live) != identity(inc):
                                raise Pending("Missing trusted initial baseline; select an explicit override")
                            merge_file(base, live, inc, candidate / key)
                        if identity(inc) is not None:
                            copy_file(inc, baseline / key)
                        if key in artifacts:
                            artifacts[key]["baseline"] = identity(inc)
                            artifacts[key]["deployed"] = identity(candidate / key)
                        elif identity(candidate / key) is not None:
                            raise Pending("Upstream removal retained locally; capture or remove the local edit explicitly")
                    except (Pending, OSError, ValueError, SyntaxError) as error:
                        evidence = stage / "pending" / key
                        evidence.mkdir(parents=True, exist_ok=True)
                        for label, path in (("B", base), ("L", live), ("I", inc)):
                            if identity(path) is not None:
                                copy_file(path, evidence / label)
                        write_json(evidence / "reason.json", {"artifact": key, "reason": str(error),
                                   "resolution": f"Review B/L/I; dfa-deploy override {key} /resolved/file; then dfa-deploy deploy"})
                        errors.append(f"{key}: {error}; inputs: {evidence}")
                if errors:
                    write_json(stage / "blocked.json", errors)
                    raise Pending("Deployment pending; active files unchanged\n" + "\n".join(errors))
                for key in artifacts:
                    path = candidate / key
                    if path.is_symlink() and (not path.exists() or not path.resolve().is_relative_to(candidate)):
                        raise Pending(f"Incomplete or external installed symlink: {key}; source closure must include its target")
                manifest = {"version": 1, "sources": sources,
                            "artifacts": {key: {field: value for field, value in item.items() if field != "source_identity"}
                                          for key, item in artifacts.items()}, "links": links}
                write_json(stage / "manifest.json", manifest)
                shutil.copy2(candidate / "DEPLOYMENT-README.md", stage / "README.md")
                # Source changes during staging require a fresh deterministic attempt.
                for key, item in artifacts.items():
                    if item.get("source") and identity(Path(item["origin"])) != item["source_identity"]:
                        raise Pending(f"Source edited during staging: {key}; retry deployment")
                for source in sources:
                    if source["commit"]:
                        path = Path(source["path"])
                        commit_now = git(path, "rev-parse", "HEAD").stdout.decode().strip()
                        url_now = clean_url(git(path, "remote", "get-url", "origin").stdout.decode())
                        if commit_now != source["commit"] or url_now != source["url"]:
                            raise Pending(f"Source provenance changed during staging: {source['id']}; retry deployment")
                        if source.get("working_tree") and source["working_tree"] != hashlib.sha256(
                                git(path, "status", "--porcelain", "-z", "--untracked-files=all").stdout).hexdigest():
                            raise Pending("Source paths changed during staging; retry deployment")
                if identity(registry) != registry_before:
                    raise Pending("Source registry edited during staging; retry deployment")
                if tree and self.active.resolve() != tree:
                    raise Pending("Active deployment changed during staging")
                for key, observation in observed.items():
                    if identity(Path(observation["path"])) != observation["identity"]:
                        raise Pending(f"Live edit during staging: {key}; retry deployment")
                for target, snapshot in snapshots.items():
                    if identity(Path(target)) != snapshot:
                        raise Pending(f"Link changed during staging: {target}; retry deployment")
                # Recheck directory membership after staging and provenance subprocesses.
                if tree:
                    self.preserve_unknown_files(tree, old["artifacts"])
                else:
                    self.preserve_legacy_directories(links, snapshots, artifacts)
                if tree and manifest == old and all(identity(candidate / key) == identity(tree / key) for key in artifacts):
                    shutil.rmtree(stage)
                    print("Deployment already current")
                    return
                generation = self.root / "generations" / identifier
                generation.parent.mkdir(exist_ok=True)
                suffix = 1
                while generation.exists():
                    generation = self.root / "generations" / f"{identifier}-{suffix}"
                    suffix += 1
                stage.rename(generation)
                # Persist recovery intent BEFORE changing any link. Retain generations indefinitely.
                transaction = {"previous": str(tree) if tree else None, "next": str(generation / "tree"),
                               "links": snapshots, "desired": links,
                               "schema": self.schema.read_text() if self.schema.exists() else None,
                               "claude": self.claude_snapshot(),
                               "registry": getattr(self, "registry_original", registry.read_text() if registry.exists() else None),
                               "registry_after": identity(registry)}
                transaction["claude_new"] = self.claude_text(transaction["claude"]["text"] or "")
                write_json(self.root / "transaction.json", transaction)
                try:
                    self.activate(transaction)
                    self.detach_models_store(primary)
                except BaseException:
                    if self.active.is_symlink() and self.active.resolve() == Path(transaction["next"]):
                        self.check_recovery(transaction)
                        self.restore(transaction)
                    (self.root / "transaction.json").unlink(missing_ok=True)
                    raise
                write_json(generation / "rollback.json", transaction)
                (self.root / "transaction.json").unlink()
                print(f"Deployed {identifier}; manifest: {generation / 'manifest.json'}")
            except BaseException:
                # Staging is retained for diagnosis; active generation and baseline remain unchanged.
                raise

    def detach_models_store(self, primary):
        # This app-owned mutable state is detached, never included in deployment/backups.
        pi = lexical(os.environ.get("PI_CODING_AGENT_DIR", self.home / ".pi/agent"))
        path = pi / "models-store.json"
        source = primary / "pi/models-store.json"
        if link_value(path) == str(source):
            safe_parents(path, self.home)
            if not source.is_file():
                raise Pending(f"Broken models-store link preserved: {path}; restore its source")
            resolved = source.resolve()
            before = identity(resolved)
            temp = path.parent / (".dfa-models-" + uuid.uuid4().hex)
            copy_file(resolved, temp)
            if identity(resolved) != before:
                temp.unlink()
                raise Pending("Pi models-store changed during detachment; retry")
            os.replace(temp, path)

    def swap(self, path, target):
        path.parent.mkdir(parents=True, exist_ok=True)
        temp = path.parent / (".dfa-link-" + uuid.uuid4().hex)
        temp.symlink_to(target)
        os.replace(temp, path)

    def activate(self, transaction):
        if identity(self.home / ".claude/CLAUDE.md") != transaction["claude"]["identity"]:
            raise Pending("Claude instructions edited during staging; preserved")
        self.swap(self.active, transaction["next"])
        for target, info in transaction["desired"].items():
            self.swap(Path(target), str(self.active / info["artifact"]))
        for target in transaction["links"].keys() - transaction["desired"].keys():
            Path(target).unlink(missing_ok=True)
        self.write_claude(transaction["claude_new"])

    def claude_snapshot(self):
        path = self.home / ".claude/CLAUDE.md"
        safe_parents(path, self.home)
        if path.is_symlink():
            raise Pending("Claude instructions are redirected; preserve and relocate them explicitly")
        return {"text": path.read_text() if path.exists() else None,
                "identity": identity(path)}

    def claude_text(self, text):
        # Retire only owned legacy imports; preserve user instructions/imports.
        lines = []
        for existing in text.splitlines():
            imported = self.home / ".claude" / existing[1:] if existing.startswith("@dfa-rules-") else None
            owned = imported and imported.is_symlink() and (link_value(imported) or "").startswith(str(self.home / ".config/dotfiles-arch/rules-build") + "/")
            if not owned:
                lines.append(existing)
        if "@dfa-deployment.md" not in lines:
            lines.append("@dfa-deployment.md")
        return "\n".join(lines) + "\n"

    def write_claude(self, text, mode=0o600):
        path = self.home / ".claude/CLAUDE.md"
        path.parent.mkdir(parents=True, exist_ok=True)
        temporary = path.parent / (".dfa-instructions-" + uuid.uuid4().hex)
        temporary.write_text(text); temporary.chmod(mode)
        os.replace(temporary, path)

    def restore(self, transaction):
        for target, snapshot in transaction["links"].items():
            path = Path(target)
            if snapshot is None:
                path.unlink(missing_ok=True)
            else:
                self.swap(path, snapshot["target"])
        if transaction["previous"]:
            self.swap(self.active, transaction["previous"])
        else:
            self.active.unlink(missing_ok=True)
        claude = transaction.get("claude")
        if claude:
            path = self.home / ".claude/CLAUDE.md"
            if claude["text"] is None:
                path.unlink(missing_ok=True)
            else:
                self.write_claude(claude["text"], claude["identity"]["mode"])
        registry = self.home / ".config/dotfiles-arch/sync-sources"
        if transaction.get("registry") is None:
            registry.unlink(missing_ok=True)
        else:
            registry.write_text(transaction["registry"])
        if transaction["schema"] is None:
            self.schema.unlink(missing_ok=True)
        else:
            self.schema.parent.mkdir(parents=True, exist_ok=True)
            self.schema.write_text(transaction["schema"])

    def rollback(self):
        with self.locked():
            tree, manifest = self.current()
            if tree is None:
                raise Pending("No deployment to roll back")
            transaction = read_json(tree.parent / "rollback.json")
            if not transaction:
                raise Pending("Missing rollback journal")
            self.check_state_restore(transaction)
            if not transaction["previous"]:
                for target, snapshot in transaction["links"].items():
                    if snapshot and not (Path(target).parent / snapshot["target"]).exists():
                        raise Pending(f"Original checkout link no longer resolves: {target}; restore the checkout before initial rollback")
            claude = self.home / ".claude/CLAUDE.md"
            if claude.is_symlink() or not claude.is_file() or claude.read_text() != transaction["claude_new"]:
                raise Pending("Rollback would overwrite later Claude instruction edits; preserve them before retrying")
            for target, info in manifest["links"].items():
                if link_value(Path(target)) != str(self.active / info["artifact"]):
                    raise Pending(f"Rollback link drift preserved: {target}")
            self.preserve_unknown_files(tree, manifest["artifacts"])
            for key, item in manifest["artifacts"].items():
                if identity(tree / key) != item["deployed"]:
                    raise Pending(f"Rollback would hide a live edit: {key}; capture or copy it before retrying")
            write_json(self.root / "transaction.json", transaction)
            self.restore(transaction)
            (self.root / "transaction.json").unlink()
            print(f"Rolled back to {transaction['previous']}; baseline, provenance, links and schema restored")

    def check_state_restore(self, transaction):
        registry = self.home / ".config/dotfiles-arch/sync-sources"
        for path in (registry, self.schema, self.home / ".claude/CLAUDE.md"):
            safe_parents(path, self.home)
            if path.is_symlink() or (path.exists() and not path.is_file()):
                raise Pending(f"Recovery state target drift preserved: {path}")
        if identity(registry) != transaction["registry_after"] and (not registry.is_file() or registry.read_text() != transaction.get("registry")):
            raise Pending("Recovery would overwrite later source registry edits; preserve them before retrying")
        schema = self.schema.read_text() if self.schema.is_file() else None
        if schema not in (transaction["schema"], "5", "5\n"):
            raise Pending("Recovery would overwrite later schema edits; preserve them before retrying")

    def check_recovery(self, transaction):
        self.check_state_restore(transaction)
        safe_parents(self.active, self.home)
        pointer = link_value(self.active)
        if (self.active.exists() and not self.active.is_symlink()) or pointer not in {transaction["previous"], transaction["next"], None}:
            raise Pending("Recovery activation-link drift preserved; inspect transaction.json")
        for target in transaction["links"]:
            safe_parents(Path(target), self.home)
        claude = self.home / ".claude/CLAUDE.md"
        current_text = claude.read_text() if claude.is_file() and not claude.is_symlink() else None
        if current_text not in (transaction["claude"]["text"], transaction["claude_new"]):
            raise Pending("Recovery would overwrite later Claude instruction edits; inspect transaction.json")
        for target, snapshot in transaction["links"].items():
            actual = identity(Path(target))
            desired = transaction["desired"].get(target)
            expected = {"kind": "link", "target": str(self.active / desired["artifact"])} if desired else None
            if actual not in (snapshot, expected):
                raise Pending(f"Recovery link drift preserved: {target}; inspect transaction.json")
        next_tree = Path(transaction["next"])
        manifest = read_json(next_tree.parent / "manifest.json")
        if manifest:
            self.preserve_unknown_files(next_tree, manifest["artifacts"])
            for key, item in manifest["artifacts"].items():
                if identity(next_tree / key) != item["deployed"]:
                    raise Pending(f"Recovery would hide a new live edit: {key}; preserve it before retrying")

    def recover(self):
        # A separate lock path uses the same flock; only recover accepts an outstanding journal.
        journal = self.root / "transaction.json"
        if not journal.exists():
            print("No interrupted activation")
            return
        with (self.root / "lock").open("a") as lock:
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError as error:
                raise Pending("Another deployment is running") from error
            transaction = read_json(journal)
            self.check_recovery(transaction)
            self.restore(transaction)
            journal.unlink()
            print("Recovered previous deployment; retry deployment")

    def rebind(self, path, accept, source_id="primary"):
        with self.locked():
            tree, manifest = self.current()
            if tree is None:
                raise Pending("No installed provenance; use deploy --source for the first install")
            path = Path(path).resolve()
            if path.is_relative_to(self.root) or not path.is_dir():
                raise Pending("Rebind requires an actual source directory")
            previous = next((s for s in manifest["sources"] if s["id"] == source_id), None)
            if previous is None:
                raise Pending("Select a source ID from dfa-deploy status")
            if source_id == "primary" and not (path / "scripts/sync.sh").is_file():
                raise Pending("Primary rebind requires an actual source checkout")
            if previous["commit"]:
                url = clean_url(git(path, "remote", "get-url", "origin").stdout.decode())
                if url != previous["url"] and not accept:
                    raise Pending("Repository URL changed; verify the intended rename and use --accept-origin-change")
                if git(path, "merge-base", "--is-ancestor", previous["commit"], "HEAD", check=False).returncode:
                    raise Pending("Replacement checkout does not descend from the recorded source commit")
            if source_id == "primary":
                self.deploy(path, locked=True)
                return
            registry = self.home / ".config/dotfiles-arch/sync-sources"
            safe_parents(registry, self.home)
            if registry.is_symlink():
                raise Pending("Source registry is redirected; preserved")
            original = registry.read_text()
            updated, found = [], False
            for line in original.splitlines():
                spec, *options = line.split("\t")
                kind, sep, registered = spec.partition(":")
                if not sep:
                    kind, registered = "standard", spec
                registered = registered.replace("~", str(self.home), 1) if registered.startswith("~/") else registered
                if kind == previous["type"] and lexical(registered) == Path(previous["path"]):
                    line = f"{kind}:{path}" + ("\t" + "\t".join(options) if options else "")
                    found = True
                updated.append(line)
            if not found:
                raise Pending("Recorded extra source is no longer registered; restore its registry entry first")
            self.rebound_sources = {(str(path), previous["type"]): source_id}
            self.registry_original = original
            registry.write_text("\n".join(updated) + "\n")
            try:
                self.deploy(self.source(), locked=True)
            except BaseException:
                registry.write_text(original)
                raise

    def capture(self, key):
        with self.locked():
            tree, manifest = self.current()
            item = manifest["artifacts"].get(key)
            if tree is None or not item or item.get("source") is None:
                raise Pending("Select a source-backed managed artifact; generated instructions cannot be captured")
            origin = next(s for s in manifest["sources"] if s["id"] == item["source"])
            path = Path(origin["path"])
            self.source_path(item["source"])
            dest = path / item["relative"]
            safe_parents(dest, path)
            before = identity(dest)
            baseline = item["baseline"]
            if dest.is_symlink() or not before or before["kind"] != "file" or not baseline or baseline["kind"] != "file" or before["sha256"] != baseline["sha256"] or (before["mode"] & 0o111) != (baseline["mode"] & 0o111):
                raise Pending(f"Dirty source artifact preserved: {dest}; reconcile its changes manually")
            live = tree / key
            if not live.is_file() or live.is_symlink():
                raise Pending("Capture supports regular managed files only")
            validate(live)
            if has_literal_credentials(live):
                raise Pending("Capture refused literal credential values; use machine-local auth or environment references")
            temp = dest.parent / (".dfa-capture-" + uuid.uuid4().hex)
            copy_file(live, temp)
            temp.chmod((before["mode"] & ~0o111) | (stat.S_IMODE(live.stat().st_mode) & 0o111))
            if identity(dest) != before:
                temp.unlink()
                raise Pending("Source edited during capture; preserved")
            os.replace(temp, dest)
            print(f"Captured selected artifact for review: {dest}; no commit or push")

    def override(self, key, file):
        with self.locked():
            _, manifest = self.current()
            known = dict(manifest["artifacts"])
            if key not in known:
                inventories = sorted((self.root / "staging").glob("*/inventory.json"), key=lambda p: p.stat().st_mtime_ns)
                if inventories:
                    known.update(read_json(inventories[-1])["artifacts"])
            if key not in known or Path(key).is_absolute() or ".." in Path(key).parts:
                raise Pending("Select a manifested or initial-pending artifact key")
            dest = self.root / "overrides" / known[key].get("override_artifact", key)
            safe_parents(dest, self.root)
            if file is None:
                dest.unlink(missing_ok=True)
                print("Override removed; deploy to reconcile source and live state")
            else:
                source = Path(file)
                if source.is_symlink() or not source.is_file():
                    raise Pending("Overrides require a regular supplied file")
                validate(source)
                # Validate against the artifact's actual format, not an arbitrary override filename.
                dest.parent.mkdir(parents=True, exist_ok=True)
                temp = dest.parent / (".override-" + uuid.uuid4().hex)
                copy_file(source, temp)
                validation = dest.parent / (".check-" + dest.name)
                copy_file(source, validation)
                try:
                    validate(validation)
                finally:
                    validation.unlink()
                temp.chmod(0o600 | (stat.S_IMODE(source.stat().st_mode) & 0o111))
                os.replace(temp, dest)
                print("Override recorded; run dfa-deploy deploy to activate")


def guidance_readme(primary):
    return (f"# Installed DFA copies\n\nShared source: {primary}\n\n"
            "This generation contains installed copies, never an editable source repository. "
            "Run dfa-deploy source before shared edits; unavailable or stale provenance stops source editing. "
            "Manifest and source baselines live beside tree/. Local overrides live in ../../overrides/. "
            "Use dfa-deploy capture ARTIFACT for selected source improvements, override ARTIFACT FILE "
            "for intentional local differences, rollback for the previous generation, recover after interruption. "
            "Staging and pending B/L/I inputs are under ../../staging/. Generations are retained as backups; "
            "no automatic pruning. See docs/deployment.md in tree/ for the full contract.\n")


def main():
    # Root execution must create user-owned generations without recursive chown.
    if os.geteuid() == 0 and os.environ.get("SUDO_USER"):
        user = pwd.getpwnam(os.environ["SUDO_USER"])
        os.initgroups(user.pw_name, user.pw_gid)
        os.setgid(user.pw_gid)
        os.setuid(user.pw_uid)
        os.environ["USER_HOME_DIR"] = user.pw_dir
        os.environ["HOME"] = user.pw_dir
    parser = argparse.ArgumentParser(description=__doc__)
    sub = parser.add_subparsers(dest="command", required=True)
    for command in ("deploy", "update", "source"):
        p = sub.add_parser(command)
        p.add_argument("--source", type=Path)
        p.add_argument("--dry-run", action="store_true")
        if command == "deploy":
            p.add_argument("--committed", action="store_true", help="Deploy HEAD instead of local working files")
        if command == "source":
            p.add_argument("--source-id", default="primary")
    p = sub.add_parser("rebind"); p.add_argument("path", type=Path)
    p.add_argument("--accept-origin-change", action="store_true")
    p.add_argument("--source-id", default="primary")
    p = sub.add_parser("capture"); p.add_argument("artifact")
    p = sub.add_parser("override"); p.add_argument("artifact"); p.add_argument("file", nargs="?", type=Path)
    for command in ("rollback", "recover", "status", "help"):
        sub.add_parser(command)
    args = parser.parse_args()
    deployment = Deployment(os.environ.get("USER_HOME_DIR", os.environ["HOME"]),
                            working_tree=args.command == "deploy" and not args.committed)
    try:
        if args.command in {"deploy", "update", "rebind", "capture", "override", "rollback", "recover"}:
            # Use the same read-only host gate as shell entrypoints; never a saved distro preference.
            check = subprocess.run(["bash", "-c",
                'set -e; DF_SCRIPT_DIR="$1"; source "$DF_SCRIPT_DIR/fn-lib.sh"; '
                'distro="$(detect_workstation_distro)"; require_workstation_entrypoint "$distro" deployment.py',
                "dfa-deploy", str(Path(__file__).resolve().parent)], capture_output=True, text=True)
            if check.returncode:
                raise Pending(check.stderr.strip() or "Unsupported workstation host")
        if args.command in {"deploy", "update", "source"}:
            source = deployment.source_path(args.source_id) if args.command == "source" and args.source_id != "primary" else deployment.source(args.source)
            if args.command == "source":
                print(source)
            elif args.dry_run:
                print(f"Would stage, merge, validate and deploy from {source}; no writes")
            else:
                if args.command == "update":
                    if git(source, "status", "--porcelain").stdout:
                        raise Pending("Source is dirty; commit/stash/review it before update, or deploy explicitly without fetching")
                    git(source, "pull", "--ff-only")
                deployment.deploy(source)
        elif args.command == "rebind":
            deployment.rebind(args.path, args.accept_origin_change, args.source_id)
        elif args.command == "capture":
            deployment.capture(args.artifact)
        elif args.command == "override":
            deployment.override(args.artifact, args.file)
        elif args.command == "rollback":
            deployment.rollback()
        elif args.command == "recover":
            deployment.recover()
        elif args.command == "status":
            if (deployment.root / "transaction.json").exists():
                raise Pending("Interrupted activation; run dfa-deploy recover before migration/stamping")
            tree, manifest = deployment.current()
            print(json.dumps({"tree": str(tree) if tree else None, "sources": manifest["sources"],
                              "pending": sorted(str(p) for p in (deployment.root / "staging").glob("*/blocked.json"))}, indent=2))
        else:
            print("dfa-deploy deploy|update|source [--source PATH] [--dry-run]\n"
                  "dfa-deploy deploy [--committed] (default: local working files; no fetch)\n"
                  "dfa-deploy status|rollback|recover\n"
                  "dfa-deploy rebind PATH [--accept-origin-change] [--source-id ID]\n"
                  "dfa-deploy capture ARTIFACT\n"
                  "dfa-deploy override ARTIFACT [FILE] (omit FILE to remove)\n"
                  "Conflict inputs: ~/.local/share/workstation/staging/*/pending/ARTIFACT/{B,L,I,reason.json}\n"
                  "Policy and inventory: ~/.local/share/workstation/config/docs/deployment.md")
    except (Pending, OSError, ValueError, SyntaxError) as error:
        print(f"dfa-deploy: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
