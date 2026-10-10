#!/usr/bin/env python3
"""Source-owned installed copy and one previous backup. See docs/deployment.md for the state contract."""
import argparse
import ast
from contextlib import contextmanager, nullcontext
import fcntl
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


def write_text(path, text, mode=0o600):
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.parent / (".dfa-state-" + uuid.uuid4().hex)
    with temporary.open("x") as file:
        temporary.chmod(mode)
        file.write(text)
        file.flush(); os.fsync(file.fileno())
    os.replace(temporary, path)
    descriptor = os.open(path.parent, os.O_RDONLY | os.O_DIRECTORY)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def write_json(path, data):
    write_text(path, json.dumps(data, sort_keys=True, indent=2) + "\n")


def lexical(path):
    return Path(os.path.abspath(path))


def link_value(path):
    return str(lexical(path.parent / os.readlink(path))) if path.is_symlink() else None


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

class Deployment:
    def __init__(self, home, working_tree=False):
        self.working_tree = working_tree
        self.home = lexical(home)
        self.root = self.home / ".local/share/workstation"
        self.active = self.root / "config"
        self.previous = self.root / "previous"
        self.stage = self.root / "staging"
        self.journal = self.root / "transaction.json"

    @contextmanager
    def locked(self, recovery=False):
        safe_parents(self.root / "lock", self.home)
        self.root.mkdir(parents=True, exist_ok=True, mode=0o700)
        self.root.chmod(0o700)
        for name in ("lock", "blue", "green", "staging", "transaction.json"):
            if (self.root / name).is_symlink():
                raise Pending(f"Redirected deployment path preserved: {name}")
        with (self.root / "lock").open("a") as lock:
            os.chmod(lock.name, 0o600)
            try:
                fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            except BlockingIOError as error:
                raise Pending("Another deployment is running; retry when it finishes") from error
            if self.previous.exists() and not self.previous.is_symlink():
                raise Pending("Previous backup link is a foreign real target")
            if self.previous.is_symlink() and link_value(self.previous) not in {str(self.root / "blue"), str(self.root / "green")}:
                raise Pending("Previous backup link is foreign")
            if self.journal.exists() and not recovery:
                raise Pending("Interrupted activation; run dfa-deploy recover before retrying")
            yield

    def state(self, folder):
        if (folder / ".dfa").is_symlink() or any((folder / ".dfa" / name).is_symlink() for name in ("sources.json", "links.json")):
            raise Pending("Installed source/link records are redirected")
        sources = read_json(folder / ".dfa/sources.json")
        recorded = read_json(folder / ".dfa/links.json")
        if not isinstance(sources, list) or not sources or not isinstance(recorded, dict):
            raise Pending("Missing installed source/link records; restore the installation")
        if not all(isinstance(s, dict) for s in sources) or sources[0].get("id") != "primary" or len({s.get("id") for s in sources}) != len(sources):
            raise Pending("Invalid installed source list")
        for source in sources:
            if not re.fullmatch(r"[a-zA-Z0-9_-]+", source.get("id", "")) or not Path(source.get("path", "")).is_absolute():
                raise Pending("Invalid source record")
        links = {}
        for target, artifact in recorded.items():
            if not Path(target).is_absolute() or not isinstance(artifact, str) or not artifact or Path(artifact).is_absolute() or ".." in Path(artifact).parts:
                raise Pending("Invalid installed link record")
            links[target] = {"artifact": artifact}
        return {"sources": sources, "links": links}

    def current(self):
        if not self.active.is_symlink():
            if self.active.exists():
                raise Pending("Deployment config path is a foreign real directory")
            return None, {"sources": [], "links": {}}
        folder = self.active.resolve()
        if folder in (self.root / "blue", self.root / "green"):
            return folder, self.state(folder)
        # Only migration reads the old manifest; no fingerprints or merge state survive.
        if folder.name == "tree" and folder.parent.parent == self.root / "generations":
            legacy = read_json(folder.parent / "manifest.json")
            if not legacy or legacy.get("version") != 1 or not legacy.get("sources") or not isinstance(legacy.get("links"), dict):
                raise Pending("Invalid legacy deployment; restore it before migration")
            if not all(isinstance(s, dict) and re.fullmatch(r"primary|[0-9a-f]{16}", s.get("id", "")) and Path(s.get("path", "")).is_absolute() for s in legacy["sources"]):
                raise Pending("Invalid legacy source records")
            state = {"sources": [{k: s.get(k) for k in ("id", "path", "type", "overwritable", "url", "commit")}
                                 for s in legacy["sources"]], "links": legacy["links"], "legacy": True}
            for info in state["links"].values():
                key = info.get("artifact", "")
                if not key or Path(key).is_absolute() or ".." in Path(key).parts:
                    raise Pending("Invalid legacy link record")
            return folder, state
        raise Pending("Deployment config link is foreign")

    def source_name(self, path, kind, used):
        base = re.sub(r"[^a-zA-Z0-9_-]+", "-", path.name).strip("-") or "source"
        name = base
        number = 2
        while name == "primary" or name in used:
            name = f"{base}-{number}"
            number += 1
        return name

    def save_state(self, folder, sources, links):
        write_json(folder / ".dfa/sources.json", sources)
        write_json(folder / ".dfa/links.json", {target: info["artifact"] for target, info in links.items()})

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
        previous_ids = {}
        for source in installed["sources"][1:]:
            name = self.source_name(Path(source["path"]), source["type"], previous_ids.values()) if installed.get("legacy") else source["id"]
            previous_ids[(source["path"], source["type"])] = name
        previous_ids.update(getattr(self, "rebound_sources", {}))
        config = self.home / ".config/dotfiles-arch/sync-sources"
        if config.exists():
            for line in getattr(self, "registry_new", config.read_text()).splitlines():
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
                if installed.get("legacy"):
                    for source in installed["sources"][1:]:
                        if source["path"] == str(path) and source["type"] == kind:
                            self.source_path(source["id"])
                name = previous_ids.get((str(path), kind), self.source_name(path, kind, previous_ids.values()))
                if name in {s["id"] for s in installed["sources"][1:]} and name not in getattr(self, "rebound_sources", {}).values():
                    self.source_path(name)
                if (path, kind) in {(p, k) for p, k, _, _ in entries}:
                    raise Pending("Duplicate registered source")
                previous_ids[(str(path), kind)] = name
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
                if name == "primary" and relative.parts[0] == ".dfa":
                    raise Pending("Source .dfa folder conflicts with installed bookkeeping")
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
                                  "origin": str(src)}
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
                        raise Pending("Pi settings also load cross-harness skills; remove those legacy paths with the standalone owner before copy syncing")
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
                        raise Pending(f"Native Pi package duplicates registered source data: {path}; remove that native resource package explicitly before copy syncing")
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
            # shared Pi files are linked from the installed copy below.
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
            artifacts[key] = {"source": None, "origin": str(path / rule.relative_to(staged))}
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
                    "These are replaceable installed DFA copies. Edit shared files in the source checkout, "
                    f"currently {primary}. Before shared edits run `dfa-deploy source`; "
                    "if unavailable, restore/rebind the checkout with `dfa-deploy rebind /actual/checkout`. "
                    "Never use installed copies as source. Deployment replaces installed edits; "
                    "keep machine-local settings outside managed files. For extra sources use "
                    "`dfa-deploy source --source-id ID`. `dfa-deploy rollback` restores the previous copy.\n\n"
                    f"Recorded shared edit destinations:\n{destinations}\n\n")
        key = "generated/AGENTS.md"
        output = incoming / key; output.parent.mkdir(parents=True, exist_ok=True)
        output.write_text(guidance + "\n".join(rules_bodies))
        artifacts[key] = {"source": None, "origin": "generated instructions"}
        legacy = self.home / ".config/dotfiles-arch/rules-build/pi-agents.md"
        for dest in (codex / "AGENTS.md", pi / "AGENTS.md", self.home / ".config/opencode/AGENTS.md"):
            add_link(dest, key, legacy)
        # A separate import preserves user-written Claude instructions.
        add_link(self.home / ".claude/dfa-deployment.md", key, self.home / ".claude/dfa-deployment.md")
        key = "generated/dfa-deployment.mdc"
        output = incoming / key
        output.write_text("---\ndescription: DFA installed-copy edit destinations\nalwaysApply: true\n---\n" + guidance)
        artifacts[key] = {"source": None, "origin": "generated instructions"}
        add_link(self.home / ".cursor/rules/dfa-deployment.mdc", key, self.home / ".cursor/rules/dfa-deployment.mdc")
        key = "DEPLOYMENT-README.md"
        output = incoming / key
        output.write_text(guidance_readme(primary))
        artifacts[key] = {"source": None, "origin": "installed-copy guidance"}
        return artifacts, links, sources

    def link_snapshot(self, target, info, old):
        path = Path(target)
        safe_parents(path, self.home)
        value = link_value(path)
        previous = old.get(target)
        if value == str(self.active / info["artifact"]) or (previous and value == str(self.active / previous["artifact"])):
            return os.readlink(path)
        if info.get("legacy") and value == info["legacy"] and value != str(path):
            if not path.exists():
                raise Pending(f"Broken legacy link preserved: {path}; restore its source")
            return os.readlink(path)
        if path.exists() or path.is_symlink():
            raise Pending(f"Unmanaged target preserved: {path}; relocate it explicitly")
        return None

    def preserve_legacy_directories(self, links, snapshots, artifacts):
        known = {lexical(item["origin"]) for item in artifacts.values() if item.get("source")}
        for target, info in links.items():
            legacy = Path(info["legacy"])
            if snapshots[target] and link_value(Path(target)) == str(legacy) and legacy.is_dir():
                for path in legacy.rglob("*"):
                    if (path.is_file() or path.is_symlink()) and lexical(path) not in known:
                        raise Pending(f"Unmanaged legacy descendant preserved: {path}")

    def check_handoffs(self, incoming, artifacts, sources, tree):
        config = read_json(incoming / ".dfa-source-handoffs.json", {"version": 1, "moves": []})
        if not isinstance(config, dict) or config.get("version") != 1 or not isinstance(config.get("moves"), list):
            raise Pending("Invalid source handoff configuration")
        for move in config["moves"]:
            if not isinstance(move, dict) or set(move) != {"from", "to", "source"}:
                raise Pending("Invalid source handoff entry")
            for field in ("from", "to"):
                value = move[field]
                if not isinstance(value, str) or not value or Path(value).is_absolute() or any(p in {"..", "."} for p in value.split("/")):
                    raise Pending("Unsafe source handoff path")
            if not tree:
                continue
            replacements = [s for s in sources[1:] if s["type"] == "standard" and s["url"] == move["source"]]
            for old in (tree / move["from"]).rglob("*"):
                if not (old.is_file() or old.is_symlink()) or old.relative_to(tree).as_posix() in artifacts:
                    continue
                if len(replacements) != 1:
                    raise Pending("Source handoff requires exactly one manually registered replacement source")
                key = f"extras/{replacements[0]['id']}/{move['to']}/{old.relative_to(tree / move['from']).as_posix()}"
                if key not in artifacts:
                    raise Pending(f"Replacement source is missing handoff artifact: {key}")

    def swap(self, path, target):
        safe_parents(path, self.home)
        path.parent.mkdir(parents=True, exist_ok=True)
        temp = path.parent / (".dfa-link-" + uuid.uuid4().hex)
        try:
            temp.symlink_to(target)
            os.replace(temp, path)
        finally:
            temp.unlink(missing_ok=True)

    def claude_snapshot(self):
        path = self.home / ".claude/CLAUDE.md"
        safe_parents(path, self.home)
        if path.is_symlink() or (path.exists() and not path.is_file()):
            raise Pending("Claude instructions are redirected; preserve and relocate them explicitly")
        return {"text": path.read_text() if path.exists() else None,
                "mode": stat.S_IMODE(path.stat().st_mode) if path.exists() else 0o600}

    def claude_text(self, text):
        lines = []
        for line in text.splitlines():
            imported = self.home / ".claude" / line[1:] if line.startswith("@dfa-rules-") else None
            owned = imported and imported.is_symlink() and (link_value(imported) or "").startswith(str(self.home / ".config/dotfiles-arch/rules-build") + "/")
            if not owned:
                lines.append(line)
        if "@dfa-deployment.md" not in lines:
            lines.append("@dfa-deployment.md")
        return "\n".join(lines) + "\n"

    def write_claude(self, text, mode=0o600):
        path = self.home / ".claude/CLAUDE.md"
        safe_parents(path, self.home)
        write_text(path, text, mode)

    def snapshots(self, links, old):
        return {target: self.link_snapshot(target, links.get(target, old.get(target)), old)
                for target in links.keys() | old.keys()}

    def same_copy(self, left, right):
        def entries(root):
            return {p.relative_to(root): p for p in root.rglob("*")
                    if p.relative_to(root).parts[0] != ".dfa" and (p.is_file() or p.is_symlink())}
        a, b = entries(left), entries(right)
        if a.keys() != b.keys():
            return False
        for key, path in a.items():
            other = b[key]
            if path.is_symlink() or other.is_symlink():
                if not (path.is_symlink() and other.is_symlink() and os.readlink(path) == os.readlink(other)):
                    return False
            elif stat.S_IMODE(path.stat().st_mode) != stat.S_IMODE(other.stat().st_mode) or path.read_bytes() != other.read_bytes():
                return False
        return True

    def deploy(self, primary, locked=False):
        with nullcontext() if locked else self.locked():
            tree, old = self.current()
            if self.stage.exists():
                shutil.rmtree(self.stage)
            self.stage.mkdir(mode=0o700)
            incoming = self.stage / "new"
            incoming.mkdir()
            try:
                artifacts, links, sources = self.inventory(primary, incoming)
                self.check_handoffs(incoming, artifacts, sources, tree)
                snapshots = self.snapshots(links, old["links"])
                if not tree:
                    self.preserve_legacy_directories(links, snapshots, artifacts)
                for key in artifacts:
                    path = incoming / key
                    if path.is_symlink() and (not path.exists() or not path.resolve().is_relative_to(incoming)):
                        raise Pending(f"Incomplete or external installed symlink: {key}")
                    validate(path)
                self.save_state(incoming, sources, links)
                claude = self.claude_snapshot()
                new_claude = self.claude_text(claude["text"] or "")
                if tree and not old.get("legacy") and sources == old["sources"] and {k: v['artifact'] for k,v in links.items()} == {k: v['artifact'] for k,v in old['links'].items()} and self.same_copy(incoming, tree) and claude["text"] == new_claude:
                    print("Installed copy already current")
                    return
                next_folder = self.root / ("green" if tree == self.root / "blue" or old.get("legacy") else "blue")
                if next_folder.exists():
                    self.state(next_folder)  # Never remove a foreign blue/green folder.
                backup = tree
                if old.get("legacy"):
                    # Preserve old installed bytes (including override effects), not baselines/hashes.
                    backup = self.root / "blue"
                    if backup.exists():
                        raise Pending("Existing blue folder blocks migration; inspect it explicitly")
                    shutil.copytree(tree, self.stage / "backup", symlinks=True)
                    backup_sources = []
                    backup_links = {k: dict(v) for k, v in old["links"].items()}
                    for source in old["sources"]:
                        entry = dict(source)
                        if source["id"] != "primary":
                            entry["id"] = self.source_name(Path(source["path"]), source["type"], [s["id"] for s in backup_sources])
                            for prefix in ("extras", "generated/rules"):
                                old_path = self.stage / "backup" / prefix / source["id"]
                                if old_path.exists():
                                    old_path.rename(old_path.parent / entry["id"])
                            for info in backup_links.values():
                                for prefix in ("extras", "generated/rules"):
                                    info["artifact"] = info["artifact"].replace(f"{prefix}/{source['id']}/", f"{prefix}/{entry['id']}/", 1)
                        backup_sources.append(entry)
                    self.save_state(self.stage / "backup", backup_sources, backup_links)
                transaction = {"previous": str(tree) if tree else None, "next": str(next_folder),
                               "backup_before": link_value(self.previous), "backup_after": str(backup) if backup else None,
                               "links": snapshots, "desired": {k: v["artifact"] for k,v in links.items()},
                               "claude": claude, "claude_new": new_claude, "legacy": bool(old.get("legacy")),
                               "phase": "prepared"}
                if hasattr(self, "registry_new"):
                    transaction["registry"] = {"before": self.registry_original, "after": self.registry_new}
                write_json(self.journal, transaction)
                try:
                    if next_folder.exists():
                        next_folder.rename(self.stage / "retired")
                    incoming.rename(next_folder)
                    if old.get("legacy"):
                        (self.stage / "backup").rename(backup)
                    self.check_links(transaction)
                    self.activate(transaction)
                    self.detach_models_store(primary)
                    transaction["phase"] = "committed"
                    write_json(self.journal, transaction)
                    self.finish(transaction)
                except BaseException:
                    # A hard interruption leaves the journal for recover; ordinary failures undo activation.
                    if transaction["phase"] == "prepared":
                        self.restore(transaction)
                    raise
                print(f"Deployed {next_folder.name}; installed copy: {self.active}; previous backup: {self.previous if backup else 'none'}")
                if old.get("legacy"):
                    print("Migrated to blue/green. Installed edits and override effects are in the backup; future deploys replace them from source.")
            finally:
                if not self.journal.exists() and self.stage.exists():
                    shutil.rmtree(self.stage)

    def check_links(self, transaction):
        if link_value(self.active) not in {transaction["previous"], transaction["next"], None} or (self.active.exists() and not self.active.is_symlink()):
            raise Pending("Activation link drift preserved; inspect transaction.json")
        for target, before in transaction["links"].items():
            path = Path(target)
            safe_parents(path, self.home)
            after = str(self.active / transaction["desired"][target]) if target in transaction["desired"] else None
            if (path.exists() and not path.is_symlink()) or (os.readlink(path) if path.is_symlink() else None) not in {before, after}:
                raise Pending(f"Link drift preserved: {target}; inspect transaction.json")
        if self.previous.exists() and not self.previous.is_symlink():
            raise Pending("Backup pointer drift preserved")
        if link_value(self.previous) not in {transaction["backup_before"], transaction["backup_after"]}:
            raise Pending("Backup pointer drift preserved")
        if "registry" in transaction:
            path = self.home / ".config/dotfiles-arch/sync-sources"
            safe_parents(path, self.home)
            if path.is_symlink() or path.read_text() not in transaction["registry"].values():
                raise Pending("Source registry edits preserved")
        text = self.claude_snapshot()["text"]
        if text not in {transaction["claude"]["text"], transaction["claude_new"]}:
            raise Pending("Later Claude instruction edits preserved; inspect transaction.json")

    def activate(self, transaction):
        self.swap(self.active, transaction["next"])
        for target, artifact in transaction["desired"].items():
            self.swap(Path(target), str(self.active / artifact))
        for target in transaction["links"].keys() - transaction["desired"].keys():
            Path(target).unlink(missing_ok=True)
        self.write_claude(transaction["claude_new"], transaction["claude"]["mode"])
        if "registry" in transaction:
            write_text(self.home / ".config/dotfiles-arch/sync-sources", transaction["registry"]["after"])
        if transaction["backup_after"]:
            self.swap(self.previous, transaction["backup_after"])
        else:
            self.previous.unlink(missing_ok=True)

    def restore(self, transaction):
        self.check_links(transaction)
        for target, before in transaction["links"].items():
            if before is None:
                Path(target).unlink(missing_ok=True)
            else:
                self.swap(Path(target), before)
        if transaction["previous"]:
            self.swap(self.active, transaction["previous"])
        else:
            self.active.unlink(missing_ok=True)
        if transaction["backup_before"]:
            self.swap(self.previous, transaction["backup_before"])
        else:
            self.previous.unlink(missing_ok=True)
        if transaction["claude"]["text"] is None:
            (self.home / ".claude/CLAUDE.md").unlink(missing_ok=True)
        else:
            self.write_claude(transaction["claude"]["text"], transaction["claude"]["mode"])
        if "registry" in transaction:
            write_text(self.home / ".config/dotfiles-arch/sync-sources", transaction["registry"]["before"])
        if transaction.get("operation") != "rollback":
            next_folder = Path(transaction["next"])
            if next_folder.exists() and not (self.stage / "new").exists():
                shutil.rmtree(next_folder)
            if (self.stage / "retired").exists():
                (self.stage / "retired").rename(next_folder)
            if transaction["legacy"] and Path(transaction["backup_after"]).exists():
                shutil.rmtree(transaction["backup_after"])
        self.journal.unlink()
        if self.stage.exists():
            shutil.rmtree(self.stage)

    def finish(self, transaction):
        if transaction["legacy"]:
            generations = self.root / "generations"
            for folder in list(generations.iterdir()) if generations.exists() else []:
                if folder.is_symlink() or not folder.is_dir():
                    continue
                metadata = read_json(folder / "manifest.json", {})
                if metadata.get("version") == 1 and (folder / "tree").is_dir():
                    shutil.rmtree(folder)
            if generations.exists() and not any(generations.iterdir()):
                generations.rmdir()
            overrides = self.root / "overrides"
            if overrides.is_dir() and not overrides.is_symlink():
                shutil.rmtree(overrides)
        if self.stage.exists():
            shutil.rmtree(self.stage)
        self.journal.unlink()

    def rollback(self):
        with self.locked():
            tree, old = self.current()
            backup = link_value(self.previous)
            if not tree or backup not in {str(self.root / "blue"), str(self.root / "green")} or backup == str(tree):
                raise Pending("No previous installed copy")
            desired = self.state(Path(backup))
            claude = self.claude_snapshot()
            transaction = {"previous": str(tree), "next": backup, "backup_before": backup,
                           "backup_after": str(tree), "links": self.snapshots(desired["links"], old["links"]),
                           "desired": {k: v["artifact"] for k,v in desired["links"].items()},
                           "claude": claude, "claude_new": self.claude_text(claude["text"] or ""),
                           "phase": "prepared", "legacy": False, "operation": "rollback"}
            write_json(self.journal, transaction)
            try:
                self.activate(transaction)
                transaction["phase"] = "committed"
                write_json(self.journal, transaction)
                self.finish(transaction)
            except BaseException:
                if transaction["phase"] == "prepared":
                    self.restore(transaction)
                raise
            print(f"Rolled back to {Path(backup).name}")

    def recover(self):
        with self.locked(recovery=True):
            if not self.journal.exists():
                print("No interrupted activation")
                return
            transaction = read_json(self.journal)
            if transaction.get("next") not in {str(self.root / "blue"), str(self.root / "green")}:
                raise Pending("Recover legacy activation using its installed v5 manager before migrating")
            if transaction.get("phase") == "committed":
                self.check_links(transaction)
                if link_value(self.active) != transaction["next"] or link_value(self.previous) != transaction["backup_after"]:
                    raise Pending("Committed activation links changed; inspect transaction.json")
                self.finish(transaction)
                print("Finished committed deployment cleanup")
            else:
                self.restore(transaction)
                print("Recovered previous installed copy; retry deployment")

    def detach_models_store(self, primary):
        pi = lexical(os.environ.get("PI_CODING_AGENT_DIR", self.home / ".pi/agent"))
        path = pi / "models-store.json"
        source = primary / "pi/models-store.json"
        if link_value(path) == str(source):
            safe_parents(path, self.home)
            if not source.is_file():
                raise Pending(f"Broken models-store link preserved: {path}; restore its source")
            temporary = path.parent / (".dfa-models-" + uuid.uuid4().hex)
            try:
                copy_file(source.resolve(), temporary)
                os.replace(temporary, path)
            finally:
                temporary.unlink(missing_ok=True)

    def rebind(self, path, accept, source_id="primary"):
        with self.locked():
            _, old = self.current()
            path = Path(path).resolve()
            previous = next((s for s in old["sources"] if s["id"] == source_id), None)
            if not previous or not path.is_dir() or path.is_relative_to(self.root):
                raise Pending("Rebind requires a recorded source ID and actual source directory")
            if previous["commit"]:
                url = clean_url(git(path, "remote", "get-url", "origin").stdout.decode())
                if url != previous["url"] and not accept:
                    raise Pending("Repository URL changed; use --accept-origin-change after verification")
                if git(path, "merge-base", "--is-ancestor", previous["commit"], "HEAD", check=False).returncode:
                    raise Pending("Replacement checkout does not descend from the recorded source commit")
            if source_id == "primary":
                if not (path / "scripts/sync.sh").is_file():
                    raise Pending("Primary rebind requires the actual checkout")
                self.deploy(path, locked=True)
                return
            registry = self.home / ".config/dotfiles-arch/sync-sources"
            safe_parents(registry, self.home)
            if registry.is_symlink():
                raise Pending("Source registry is redirected")
            original = registry.read_text()
            updated = []
            found = False
            for line in original.splitlines():
                if not line.strip() or line.lstrip().startswith("#"):
                    updated.append(line)
                    continue
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
                raise Pending("Recorded extra source is no longer registered")
            self.rebound_sources = {(str(path), previous["type"]): source_id}
            self.registry_original = original
            self.registry_new = "\n".join(updated) + "\n"
            self.deploy(self.source(), locked=True)


def guidance_readme(primary):
    return (f"# DFA installed copy\n\nShared source: {primary}\n"
            "Run dfa-deploy source before shared edits. Restore/rebind unavailable sources.\n"
            "Deploy replaces managed installed files. Keep machine-local settings outside this copy.\n"
            "config points to blue or green; the other folder is the previous backup.\n"
            "Use dfa-deploy rollback for the previous copy and recover after interruption.\n")
def main():
    # Root execution must create user-owned copies without recursive chown.
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
    for command in ("rollback", "recover", "status", "help"):
        sub.add_parser(command)
    args = parser.parse_args()
    deployment = Deployment(os.environ.get("USER_HOME_DIR", os.environ["HOME"]),
                            working_tree=args.command == "deploy" and not args.committed)
    try:
        if args.command in {"deploy", "update", "rebind", "rollback", "recover"}:
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
                print(f"Would copy, validate and deploy from {source}; no writes")
            else:
                if args.command == "update":
                    if git(source, "status", "--porcelain").stdout:
                        raise Pending("Source is dirty; commit/stash/review it before update, or deploy explicitly without fetching")
                    git(source, "pull", "--ff-only")
                deployment.deploy(source)
        elif args.command == "rebind":
            deployment.rebind(args.path, args.accept_origin_change, args.source_id)
        elif args.command == "rollback":
            deployment.rollback()
        elif args.command == "recover":
            deployment.recover()
        elif args.command == "status":
            if (deployment.root / "transaction.json").exists():
                raise Pending("Interrupted activation; run dfa-deploy recover before migration/stamping")
            tree, manifest = deployment.current()
            print(json.dumps({"tree": str(tree) if tree else None, "sources": manifest["sources"],
                              "previous": link_value(deployment.previous), "layout": "legacy" if manifest.get("legacy") else "blue-green"}, indent=2))
        else:
            print("dfa-deploy deploy|update|source [--source PATH] [--dry-run]\n"
                  "dfa-deploy deploy [--committed] (default: local working files; no fetch)\n"
                  "dfa-deploy status|rollback|recover\n"
                  "dfa-deploy rebind PATH [--accept-origin-change] [--source-id ID]\n"
                  "Policy and inventory: ~/.local/share/workstation/config/docs/deployment.md")
    except (Pending, OSError, ValueError, SyntaxError) as error:
        print(f"dfa-deploy: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
