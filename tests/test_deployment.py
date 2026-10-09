"""Public deployment CLI checks; all writes stay in temporary supplied repositories."""
import json
import os
from pathlib import Path
import subprocess
import shutil
import fcntl
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / "scripts/deployment.py"


def main():
    with tempfile.TemporaryDirectory(prefix="dfa-deploy-") as tmp:
        temp = Path(tmp)
        home, source = temp / "home", temp / "source"
        source.mkdir(); home.mkdir()
        def git(*args):
            return subprocess.run(["git", "-C", str(source), *args], check=True,
                                  capture_output=True, text=True).stdout.strip()
        git("init", "-b", "main")
        git("config", "user.email", "fixture@example.test")
        git("config", "user.name", "Fixture")
        git("remote", "add", "origin", "https://github.com/example/anonymous.git")
        (source / "home").mkdir()
        (source / "home/.bashrc").write_text("one\ntwo\nthree\nfour\nfive\n")
        (source / "scripts").mkdir()
        (source / "scripts/sync.sh").write_text("#!/bin/bash\nexit 0\n")
        git("add", "."); git("commit", "-m", "fixture")
        env = dict(os.environ, USER_HOME_DIR=str(home), HOME=str(home),
                   CODEX_HOME=str(home / ".codex"), PI_CODING_AGENT_DIR=str(home / ".pi/agent"))
        def run(*args, ok=True):
            # Supplied incoming source means a committed shared revision, never incidental dirty bytes.
            if args[0] == "deploy" and git("status", "--porcelain"):
                git("add", "."); git("commit", "-m", "supplied incoming revision")
            result = subprocess.run(["python3", str(CLI), *args], env=env,
                                    capture_output=True, text=True)
            assert (result.returncode == 0) == ok, result.stdout + result.stderr
            return result
        run("deploy", "--source", str(source))
        live = home / ".bashrc"
        assert live.is_symlink() and ".local/share/workstation/config/" in os.readlink(live)
        live.write_text("LOCAL\ntwo\nthree\nfour\nfive\n")
        (source / "home/.bashrc").write_text("one\ntwo\nthree\nfour\nINCOMING\n")
        run("deploy", "--source", str(source))
        assert live.read_text() == "LOCAL\ntwo\nthree\nfour\nINCOMING\n"
        # Competing text edits block the whole generation and retain literal inputs.
        active = home / ".local/share/workstation/config"
        generation = os.readlink(active)
        run("deploy", "--source", str(source))
        assert os.readlink(active) == generation
        before = live.read_bytes()
        (source / "home/.bashrc").write_text("SHARED\ntwo\nthree\nfour\nINCOMING\n")
        blocked = run("deploy", "--source", str(source), ok=False)
        assert "pending" in blocked.stderr and live.read_bytes() == before
        assert run("deploy", "--source", str(source), ok=False).stderr == blocked.stderr
        assert os.readlink(active) == generation
        pending = list((active.parent / "staging").glob("*/pending/home/.bashrc"))[-1]
        assert (pending / "L").read_bytes() == before
        resolved = temp / "resolved"
        resolved.write_text("RESOLVED\ntwo\nthree\nfour\nINCOMING\n")
        run("override", "home/.bashrc", str(resolved))
        run("deploy", "--source", str(source))
        assert live.read_text() == resolved.read_text()
        run("override", "home/.bashrc")
        # Source operations preserve an independently dirty source artifact.
        (source / "home/.bashrc").write_text("independent dirty source edit\n")
        run("capture", "home/.bashrc", ok=False)
        (source / "home/.bashrc").write_text("SHARED\ntwo\nthree\nfour\nINCOMING\n")
        run("capture", "home/.bashrc")
        assert (source / "home/.bashrc").read_text() == resolved.read_text()
        # Missing baseline is conservative even if live equals incoming.
        run("deploy", "--source", str(source))
        current = active.resolve().parent
        (current / "baseline/home/.bashrc").unlink()
        assert "baseline" in run("deploy", "--source", str(source), ok=False).stderr.lower()
        (current / "baseline/home/.bashrc").write_text(resolved.read_text())
        (current / "baseline/home/.bashrc").chmod(json.loads((current / "manifest.json").read_text())["artifacts"]["home/.bashrc"]["baseline"]["mode"])
        # Checkout move, repository rename and credentials never change installed targets.
        git("add", "."); git("commit", "--allow-empty", "-m", "shared changes")
        original_link = os.readlink(live)
        moved = temp / "renamed checkout"
        source.rename(moved); source = moved
        assert live.read_bytes() == resolved.read_bytes()
        run("source", ok=False)
        run("rebind", str(source))
        assert run("source").stdout.strip() == str(source)
        assert os.readlink(live) == original_link
        git("remote", "set-url", "origin", "https://name:secret@github.com/example/renamed.git?token=secret")
        run("source", ok=False)
        run("rebind", str(source), ok=False)
        run("rebind", str(source), "--accept-origin-change")
        manifest = (active.resolve().parent / "manifest.json").read_text()
        assert "secret" not in manifest and "renamed" in manifest
        assert "actual source checkout" in (home / ".codex/AGENTS.md").read_text()
        # Rollback refuses to hide post-activation edits.
        live.write_text("post-activation edit\n")
        run("rollback", ok=False)
        live.write_text(resolved.read_text())
        run("rollback")
        assert os.readlink(live) == original_link
        run("rebind", str(source), "--accept-origin-change")
        # Structured values: missing/null, deletion, local-only keys, atomic arrays and types.
        (source / "config").mkdir(exist_ok=True)
        structured = source / "config/example.json"
        cases = [
            ({"a": 1, "b": 2}, {"a": 3, "b": 2, "local": None}, {"a": 1, "b": 4}, {"a": 3, "b": 4, "local": None}),
            ({"a": 1, "b": None}, {"a": 1}, {"a": 2, "b": None}, {"a": 2}),
            ({"a": 1}, {}, {"a": 2}, None),
            ({"a": [1, 2]}, {"a": [3, 2]}, {"a": [1, 4]}, None),
            ({"a": {"x": 1}}, {"a": {"x": 2}}, {"a": []}, None),
        ]
        for base, local, incoming, expected in cases:
            structured.write_text(json.dumps(base) + "\n")
            git("add", "."); git("commit", "--allow-empty", "-m", "structured fixture")
            destination = home / ".config/example.json"
            if destination.exists():
                destination.write_text(json.dumps(base) + "\n")
            run("deploy", "--source", str(source))
            destination.write_text(json.dumps(local) + "\n")
            structured.write_text(json.dumps(incoming) + "\n")
            before = destination.read_bytes(); generation = os.readlink(active)
            run("deploy", "--source", str(source), ok=expected is not None)
            if expected is None:
                assert destination.read_bytes() == before and os.readlink(active) == generation
                destination.write_text(json.dumps(base) + "\n")
                structured.write_text(json.dumps(base) + "\n")
            else:
                assert json.loads(destination.read_text()) == expected
        structured.write_text("invalid JSON")
        assert "pending" in run("deploy", "--source", str(source), ok=False).stderr
        structured.write_text(json.dumps(cases[-1][0]) + "\n")
        # A source deletion versus a local edit retains working content and baseline.
        destination.write_text('{"local": true}\n')
        structured.unlink()
        run("deploy", "--source", str(source), ok=False)
        assert destination.read_text() == '{"local": true}\n'
        structured.write_text(json.dumps(cases[-1][0]) + "\n")
        destination.write_text(structured.read_text())
        run("deploy", "--source", str(source))
        binary = source / "config/binary.dat"
        binary.write_bytes(b"\0baseline")
        git("add", "."); git("commit", "--allow-empty", "-m", "binary fixture")
        run("deploy", "--source", str(source))
        binary.write_bytes(b"\0incoming")
        run("deploy", "--source", str(source), ok=False)
        assert (home / ".config/binary.dat").read_bytes() == b"\0baseline"
        binary.write_bytes(b"\0baseline")
        # Extra sources also deploy stable copies and can be explicitly rebound.
        extra = temp / "extra source"; skill = extra / "nested/supplied"
        skill.mkdir(parents=True); (skill / "SKILL.md").write_text("shared skill\n")
        registry = home / ".config/dotfiles-arch/sync-sources"
        registry.parent.mkdir(parents=True, exist_ok=True)
        registry.write_text(f"skills-root:{extra}\n")
        run("deploy", "--source", str(source))
        deployed_skill = home / ".claude/skills/supplied/SKILL.md"
        stable_skill = os.readlink(deployed_skill.parent)
        deployed_skill.write_text("local skill improvement\n")
        manifest = json.loads((active.resolve().parent / "manifest.json").read_text())
        source_id = manifest["sources"][1]["id"]
        moved_extra = temp / "moved extra source"; extra.rename(moved_extra)
        run("deploy", "--source", str(source), ok=False)
        assert deployed_skill.read_text() == "local skill improvement\n"
        run("rebind", str(moved_extra), "--source-id", source_id)
        assert deployed_skill.read_text() == "local skill improvement\n"
        assert os.readlink(deployed_skill.parent) == stable_skill
        assert str(moved_extra) in registry.read_text()
        # Recover a journaled activation with the public recovery interface.
        completed = active.resolve().parent / "rollback.json"
        (active.parent / "transaction.json").write_bytes(completed.read_bytes())
        run("status", ok=False)
        run("recover")
        assert not (active.parent / "transaction.json").exists()
        assert deployed_skill.read_text() == "local skill improvement\n"
        run("rebind", str(moved_extra), "--source-id", source_id)
        # A live edit made during clean merge staging is detected before activation.
        guard = temp / "guard"; guard.mkdir()
        real_git = shutil.which("git")
        (guard / "git").write_text(
            '#!/bin/bash\nif [[ "$1" == merge-file ]]; then\n'
            '  "$REAL_GIT" "$@"\n  result=$?\n'
            '  printf "concurrent edit\\n" >> "$DRIFT_FILE"\n  exit "$result"\n'
            'fi\nexec "$REAL_GIT" "$@"\n')
        (guard / "git").chmod(0o755)
        drift_before = live.read_text()
        live.write_text(drift_before.replace("RESOLVED", "LOCALDRIFT"))
        shared_before = (source / "home/.bashrc").read_text()
        (source / "home/.bashrc").write_text(shared_before.replace("INCOMING", "SHAREDDRIFT"))
        old_env = dict(env)
        env.update(PATH=str(guard) + os.pathsep + os.environ["PATH"], REAL_GIT=real_git, DRIFT_FILE=str(live))
        generation = os.readlink(active)
        failure = run("deploy", "--source", str(source), ok=False)
        assert "during staging" in failure.stderr and os.readlink(active) == generation
        assert live.read_text().endswith("concurrent edit\n")
        env.clear(); env.update(old_env)
        live.write_text(drift_before); (source / "home/.bashrc").write_text(shared_before)
        # A file added after candidate validation must also block activation.
        added = deployed_skill.parent / "late-support.txt"
        counter = temp / "git-head-count"
        (guard / "git").write_text(
            '#!/bin/bash\nif [[ "$1" == -C && "$2" == "$DRIFT_SOURCE" && "$3" == rev-parse && "$4" == HEAD ]]; then\n'
            '  count=0; [[ ! -f "$COUNT_FILE" ]] || read -r count < "$COUNT_FILE"\n'
            '  count=$((count + 1)); printf "%s\\n" "$count" > "$COUNT_FILE"\n'
            '  if ((count == 3)); then printf "keep late file\\n" > "$DRIFT_FILE"; fi\n'
            'fi\nexec "$REAL_GIT" "$@"\n')
        env.update(PATH=str(guard) + os.pathsep + os.environ["PATH"], REAL_GIT=real_git,
                   DRIFT_SOURCE=str(source), COUNT_FILE=str(counter), DRIFT_FILE=str(added))
        generation = os.readlink(active)
        run("deploy", "--source", str(source), ok=False)
        assert os.readlink(active) == generation and added.read_text() == "keep late file\n"
        added.unlink(); env.clear(); env.update(old_env)
        # Unknown installed files remain active during both rollback and interruption recovery.
        added = deployed_skill.parent / "local-support.txt"; added.write_text("keep active\n")
        generation = os.readlink(active)
        run("rollback", ok=False)
        assert os.readlink(active) == generation and added.read_text() == "keep active\n"
        completed = active.resolve().parent / "rollback.json"
        (active.parent / "transaction.json").write_bytes(completed.read_bytes())
        run("recover", ok=False)
        assert added.read_text() == "keep active\n" and os.readlink(active) == generation
        added.unlink()
        # A foreign activation pointer and redirected parents are never overwritten on recovery.
        foreign = temp / "foreign activation"; foreign.mkdir()
        active.unlink(); active.symlink_to(foreign)
        run("recover", ok=False)
        assert active.resolve() == foreign
        active.unlink(); active.symlink_to(generation)
        state_dir = home / ".config/dotfiles-arch"
        original_state = temp / "original state"; state_dir.rename(original_state)
        foreign_state = temp / "foreign state"; foreign_state.mkdir()
        (foreign_state / "sync-sources").write_text("foreign registry\n")
        (foreign_state / ".dotfiles_schema_version").write_text("88\n")
        state_dir.symlink_to(foreign_state)
        run("recover", ok=False)
        assert (foreign_state / "sync-sources").read_text() == "foreign registry\n"
        assert (foreign_state / ".dotfiles_schema_version").read_text() == "88\n"
        state_dir.unlink(); original_state.rename(state_dir)
        registry_before = registry.read_text(); registry.write_text("later registry edit\n")
        run("recover", ok=False)
        assert registry.read_text() == "later registry edit\n"
        registry.write_text(registry_before)
        schema = state_dir / ".dotfiles_schema_version"
        schema_before = schema.read_bytes() if schema.exists() else None
        schema.write_text("88\n")
        run("recover", ok=False)
        assert schema.read_text() == "88\n"
        if schema_before is None:
            schema.unlink()
        else:
            schema.write_bytes(schema_before)
        run("recover")
        run("rebind", str(moved_extra), "--source-id", source_id)
        # Missing live artifacts are pending, rather than successful dangling activation.
        installed_file = live.resolve(); saved = installed_file.read_bytes(); mode = installed_file.stat().st_mode & 0o777
        installed_file.unlink(); generation = os.readlink(active)
        run("deploy", "--source", str(source), ok=False)
        assert os.readlink(active) == generation
        installed_file.write_bytes(saved); installed_file.chmod(mode)
        # Registered Git extras require explicit origin/history rebinding on replacement.
        def extra_git(*args):
            return subprocess.run(["git", "-C", str(moved_extra), *args], check=True, capture_output=True)
        extra_git("init", "-b", "main"); extra_git("config", "user.name", "Fixture")
        extra_git("config", "user.email", "fixture@example.test")
        extra_git("remote", "add", "origin", "https://github.com/example/extra.git")
        extra_git("add", "."); extra_git("commit", "-m", "supplied extra source")
        run("deploy", "--source", str(source))
        extra_git("remote", "set-url", "origin", "https://github.com/unrelated/replacement.git")
        generation = os.readlink(active)
        run("deploy", "--source", str(source), ok=False)
        assert os.readlink(active) == generation
        run("rebind", str(moved_extra), "--source-id", source_id, "--accept-origin-change")
        # Nested Git source roots include raw committed files even with export-ignore attributes.
        nested_repo = temp / "nested git source"
        nested_skill = nested_repo / "group/nested-skill"
        nested_skill.mkdir(parents=True); (nested_skill / "SKILL.md").write_text("nested committed skill\n")
        (nested_repo / "group/.gitattributes").write_text("nested-skill/SKILL.md export-ignore\n")
        def nested_git(*args):
            return subprocess.run(["git", "-C", str(nested_repo), *args], check=True, capture_output=True)
        nested_git("init", "-b", "main"); nested_git("config", "user.name", "Fixture")
        nested_git("config", "user.email", "fixture@example.test")
        nested_git("remote", "add", "origin", "https://github.com/example/nested.git")
        nested_git("add", "."); nested_git("commit", "-m", "nested supplied source")
        registry.write_text(registry.read_text() + f"skills-root:{nested_repo / 'group'}\n")
        run("deploy", "--source", str(source))
        assert (home / ".claude/skills/nested-skill/SKILL.md").read_text() == "nested committed skill\n"
        # Unsupported architecture rejects writes at the backend host boundary.
        unsupported = temp / "unsupported guard"; unsupported.mkdir()
        (unsupported / "uname").write_text('#!/bin/bash\nprintf "aarch64\\n"\n')
        (unsupported / "uname").chmod(0o755)
        old_path = env["PATH"]
        env["PATH"] = str(unsupported) + os.pathsep + old_path
        generation = os.readlink(active)
        assert "Unsupported architecture" in run("deploy", "--source", str(source), ok=False).stderr
        assert os.readlink(active) == generation
        env["PATH"] = old_path
        # Concurrent deploy is rejected by the same lock, before staging/activation.
        with (active.parent / "lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            assert "Another deployment" in run("deploy", "--source", str(source), ok=False).stderr
        # Dry-run changes neither payload nor state.
        snapshot = {str(p): p.read_bytes() for p in active.parent.rglob("*") if p.is_file() and not p.is_symlink()}
        run("deploy", "--source", str(source), "--dry-run")
        assert snapshot == {str(p): p.read_bytes() for p in active.parent.rglob("*") if p.is_file() and not p.is_symlink()}
        print("PASS: stable copies, merges/conflicts, structured policies, overrides, capture, rebind, rollback, concurrency and dry-run")


def working_tree_deployment():
    with tempfile.TemporaryDirectory(prefix="dfa-working-tree-") as tmp:
        temp = Path(tmp); source = temp / "source"; home = temp / "home"
        source.mkdir(); home.mkdir()
        def git(*args):
            return subprocess.run(["git", "-C", str(source), *args], check=True,
                                  capture_output=True, text=True).stdout.strip()
        git("init", "-b", "main")
        git("config", "user.email", "fixture@example.test"); git("config", "user.name", "Fixture")
        git("remote", "add", "origin", "https://github.com/example/anonymous.git")
        (source / "scripts").mkdir(); (source / "home").mkdir()
        (source / "scripts/sync.sh").write_text("#!/bin/bash\nexit 0\n")
        shell = source / "home/.bashrc"; shell.write_text("echo committed\n")
        deleted = source / "scripts/deleted.sh"; deleted.write_text("#!/bin/sh\nexit 0\n")
        (source / ".gitignore").write_text("ignored.txt\n")
        git("add", "."); git("commit", "-m", "fixture")
        env = dict(os.environ, HOME=str(home), USER_HOME_DIR=str(home),
                   CODEX_HOME=str(home / ".codex"), PI_CODING_AGENT_DIR=str(home / ".pi/agent"))
        def run(*args, ok=True):
            result = subprocess.run(["python3", str(CLI), *args, "--source", str(source)],
                                    env=env, capture_output=True, text=True)
            assert (result.returncode == 0) == ok, result.stdout + result.stderr
            return result
        run("deploy")
        head = git("rev-parse", "HEAD")
        shell.write_text("echo uncommitted\n")
        deleted.unlink()
        new = source / "scripts/new.sh"; new.write_text("#!/bin/sh\nexit 0\n"); new.chmod(0o755)
        (source / "scripts/new-link.sh").symlink_to("new.sh")
        (source / "ignored.txt").write_text("ignored\n")
        (source / ".env").write_text("SECRET=excluded\n")
        (source / "auth.json").write_text('{"token":"excluded"}\n')
        status = git("status", "--porcelain")
        run("deploy")
        active = home / ".local/share/workstation/config"
        assert (home / ".bashrc").read_text() == "echo uncommitted\n"
        assert not (active / "scripts/deleted.sh").exists()
        assert (active / "scripts/new.sh").stat().st_mode & 0o111
        assert (active / "scripts/new-link.sh").read_text() == new.read_text()
        assert all(not (active / name).exists() for name in ("ignored.txt", ".env", "auth.json"))
        assert git("rev-parse", "HEAD") == head and git("status", "--porcelain") == status
        generation = os.readlink(active)
        run("deploy"); assert os.readlink(active) == generation
        assert "dirty" in run("update", ok=False).stderr
        run("deploy", "--committed")
        assert (home / ".bashrc").read_text() == "echo committed\n"
        assert not (active / "scripts/new.sh").exists()
        run("deploy")
        generation = os.readlink(active)
        new.write_text("if\n")
        run("deploy", ok=False)
        assert os.readlink(active) == generation and (home / ".bashrc").read_text() == "echo uncommitted\n"
        new.write_text("#!/bin/sh\nexit 0\n")
        (source / "scripts/external.sh").symlink_to(temp / "outside.sh")
        (temp / "outside.sh").write_text("#!/bin/sh\nexit 0\n")
        assert "External source symlink" in run("deploy", ok=False).stderr
        assert os.readlink(active) == generation
        print("PASS: uncommitted edits/additions/deletions, executable links, exclusions, no pull/commit, syntax and ownership guards")


def full_repository():
    with tempfile.TemporaryDirectory(prefix="dfa-full-repository-") as tmp:
        temp = Path(tmp); source = temp / "source"; home = temp / "home"
        source.mkdir(); home.mkdir()
        tracked = subprocess.run(["git", "-C", str(ROOT), "ls-files", "-z"], check=True, capture_output=True).stdout
        paths = {os.fsdecode(p) for p in tracked.split(b"\0") if p}
        paths |= {"scripts/deployment.py", "home/.local/bin/dfa-deploy", "migrations/v4-to-v5-migration.sh", "docs/deployment.md"}
        for name in paths:
            src = ROOT / name; dst = source / name
            dst.parent.mkdir(parents=True, exist_ok=True)
            if src.is_symlink():
                dst.symlink_to(os.readlink(src))
            else:
                shutil.copy2(src, dst)
        (source / "scripts/dotheader.sh").write_text(
            '#!/bin/bash\nset -euo pipefail\nUSER_HOME_DIR="$TEST_HOME"\nexport USER_HOME_DIR\n'
            'DF_SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"\n# shellcheck source=/dev/null\nsource "$DF_SCRIPT_DIR/fn-lib.sh"\n')
        def git(*args):
            return subprocess.run(["git", "-C", str(source), *args], check=True, capture_output=True)
        git("init", "-b", "main"); git("config", "user.name", "Fixture")
        git("config", "user.email", "fixture@example.test")
        git("remote", "add", "origin", "https://github.com/example/public.git")
        git("add", "."); git("commit", "-m", "full supplied repository")
        env = dict(os.environ, HOME=str(home), TEST_HOME=str(home), USER_HOME_DIR=str(home),
                   CODEX_HOME=str(home / ".codex"), PI_CODING_AGENT_DIR=str(home / ".pi/agent"))
        def run(script, *args, ok=True):
            result = subprocess.run(["bash", str(source / script), *args], env=env, capture_output=True, text=True)
            assert (result.returncode == 0) == ok, result.stdout + result.stderr
            return result
        run("scripts/migrate.sh", "--dry-run")
        assert not (home / ".local/share/workstation").exists()
        assert "v4" in run("scripts/migrate.sh", "--dry-run").stdout
        run("scripts/migrate.sh")
        stamp = home / ".config/dotfiles-arch/.dotfiles_schema_version"
        assert stamp.read_text().strip() == "5"
        installed = home / ".local/share/workstation/config"
        assert (home / ".packages.md").read_text() == (source / "PACKAGES.md").read_text()
        assert (home / ".pi/agent/models-store.json").exists() is False
        assert not (home / ".pi/agent/auth.json").exists()
        targets = [p for root in (home / ".claude/skills", home / ".cursor/skills", home / ".codex/skills", home / ".pi/agent/skills") for p in root.iterdir()]
        assert targets and all(p.is_symlink() and str(installed) in os.readlink(p) for p in targets)
        previous = os.readlink(installed)
        run("scripts/migrate.sh")
        assert os.readlink(installed) == previous
        # Daily acquires/deploys before dependent steps; all external effects are supplied stubs.
        guard = temp / "daily stubs"; guard.mkdir()
        logfile = temp / "daily.log"
        real_git = shutil.which("git")
        (guard / "git").write_text(
            '#!/bin/bash\nif [[ "$1" == -C && "$3" == pull ]]; then\n'
            '  printf "source-acquisition\\n" >> "$DAILY_LOG"\n'
            '  exit "${MOCK_PULL_FAIL:-0}"\nfi\nexec "$REAL_GIT" "$@"\n')
        (guard / "git").chmod(0o755)
        for step in ("dfa-update-repos", "dfa-migrate", "dfa-update-system", "dfa-update-npm-clis",
                     "dfa-sync-skills", "dfa-sync-extensions", "dfa-sync-rules", "dfa-sync-harness-agents"):
            (guard / step).write_text(f'#!/bin/bash\nprintf "%s\\n" "{step}" >> "$DAILY_LOG"\n')
            (guard / step).chmod(0o755)
        env.update(PATH=str(guard) + os.pathsep + str(home / ".local/bin") + os.pathsep + os.environ["PATH"],
                   DAILY_LOG=str(logfile), REAL_GIT=real_git)
        original = (source / "home/.bashrc").read_text()
        (source / "home/.bashrc").write_text(original + "\n# supplied shared update\n")
        git("add", "."); git("commit", "-m", "daily shared change")
        daily = home / ".local/bin/dfa-daily"
        result = subprocess.run(["bash", str(daily), "--yes"], env=env, capture_output=True, text=True)
        assert result.returncode == 0, result.stdout + result.stderr
        steps = logfile.read_text().splitlines()
        assert steps[:2] == ["dfa-update-repos", "source-acquisition"]
        assert steps.count("dfa-update-repos") == 1 and steps.count("source-acquisition") == 1
        assert steps.index("dfa-migrate") < steps.index("dfa-update-system")
        assert (home / ".bashrc").read_text().endswith("# supplied shared update\n")
        logfile.write_text(""); env["MOCK_PULL_FAIL"] = "1"
        previous = os.readlink(installed)
        result = subprocess.run(["bash", str(daily)], env=env, capture_output=True, text=True)
        assert result.returncode != 0 and os.readlink(installed) == previous
        assert logfile.read_text().splitlines() == ["dfa-update-repos", "source-acquisition"]
        logfile.write_text("")
        result = subprocess.run(["bash", str(home / ".local/bin/dfa-weekly")], env=env, capture_output=True, text=True)
        assert result.returncode != 0
        assert logfile.read_text().splitlines() == ["dfa-update-repos", "source-acquisition"]
        env.pop("MOCK_PULL_FAIL")
        # The actual direct-sync wrapper deploys dirty files before executing setup.
        local_sync = source / "scripts/sync.sh"
        sync_before = local_sync.read_text()
        shell_before = (source / "home/.bashrc").read_text()
        local_sync.write_text('#!/bin/bash\nprintf "local-sync\\n" >> "$DAILY_LOG"\n')
        (source / "home/.bashrc").write_text(shell_before + "\n# uncommitted sync test\n")
        head = git("rev-parse", "HEAD").stdout; logfile.write_text("")
        result = subprocess.run(["bash", str(home / ".local/bin/dfa-sync-dotfiles")], env=env, capture_output=True, text=True)
        assert result.returncode == 0, result.stdout + result.stderr
        assert logfile.read_text().splitlines() == ["local-sync"]
        assert (home / ".bashrc").read_text().endswith("# uncommitted sync test\n")
        assert git("rev-parse", "HEAD").stdout == head
        local_sync.write_text(sync_before); (source / "home/.bashrc").write_text(shell_before)
        subprocess.run(["python3", str(source / "scripts/deployment.py"), "deploy"], env=env, check=True, capture_output=True)
        # Stamped v4 resolving links migrate, retain local edits/state and replay safely.
        legacy = temp / "legacy home"; legacy.mkdir()
        legacy_bin = legacy / ".local/bin"; legacy_bin.mkdir(parents=True)
        (legacy / ".bashrc").symlink_to(source / "home/.bashrc")
        (legacy / ".packages.md").symlink_to(source / "home/.packages.md")
        (legacy_bin / "dfa-daily").symlink_to(source / "home/.local/bin/dfa-daily")
        agent = legacy / ".pi/agent"; agent.mkdir(parents=True)
        (agent / "models-store.json").symlink_to(source / "pi/models-store.json")
        (agent / "auth.json").write_text('"machine-only credential"')
        legacy_stamp = legacy / ".config/dotfiles-arch/.dotfiles_schema_version"
        legacy_stamp.parent.mkdir(parents=True); legacy_stamp.write_text("4\n")
        env.update(HOME=str(legacy), TEST_HOME=str(legacy), USER_HOME_DIR=str(legacy),
                   CODEX_HOME=str(legacy / ".codex"), PI_CODING_AGENT_DIR=str(agent))
        marker = next((source / "skills").rglob("SKILL.md"))
        skill_target = legacy / ".claude/skills" / marker.parent.name
        skill_target.parent.mkdir(parents=True); skill_target.symlink_to(marker.parent)
        hidden = marker.parent / "local-support.txt"; hidden.write_text("preserve legacy local data\n")
        run("scripts/migrate.sh", ok=False)
        assert hidden.read_text() == "preserve legacy local data\n" and skill_target.resolve() == marker.parent
        assert legacy_stamp.read_text().strip() == "4"
        hidden.rename(temp / "preserved local-support.txt")
        committed_shell = (source / "home/.bashrc").read_text()
        (source / "home/.bashrc").write_text(committed_shell + "\n# legacy local edit\n")
        original_bytes = (legacy / ".bashrc").read_bytes()
        # Generated legacy instructions have no trusted baseline: retain them pending.
        old_rules = legacy / ".config/dotfiles-arch/rules-build/pi-agents.md"
        old_rules.parent.mkdir(parents=True); old_rules.write_text("old generated rules\n")
        (legacy / ".codex").mkdir(); (legacy / ".codex/AGENTS.md").symlink_to(old_rules)
        run("scripts/migrate.sh", ok=False)
        assert legacy_stamp.read_text().strip() == "4"
        assert (legacy / ".bashrc").read_bytes() == original_bytes
        assert (agent / "models-store.json").is_symlink()
        pending_input = next((legacy / ".local/share/workstation/staging").glob("*/pending/generated/AGENTS.md/I"))
        selected = subprocess.run(["python3", str(source / "scripts/deployment.py"), "override", "generated/AGENTS.md", str(pending_input)], env=env, capture_output=True, text=True)
        assert selected.returncode == 0, selected.stderr
        run("scripts/migrate.sh")
        assert legacy_stamp.read_text().strip() == "5"
        assert (legacy / ".bashrc").read_bytes() == original_bytes
        assert not (agent / "models-store.json").is_symlink()
        assert (agent / "auth.json").read_text() == '"machine-only credential"'
        # Clearing dirty source work does not erase the migrated local edit from installed L.
        (source / "home/.bashrc").write_text(committed_shell)
        reconcile = subprocess.run(["python3", str(source / "scripts/deployment.py"), "deploy"], env=env, capture_output=True, text=True)
        assert reconcile.returncode == 0, reconcile.stderr
        assert (legacy / ".bashrc").read_bytes() == original_bytes
        legacy_active = legacy / ".local/share/workstation/config"
        legacy_generation = os.readlink(legacy_active)
        run("migrations/v4-to-v5-migration.sh")
        assert os.readlink(legacy_active) == legacy_generation
        # --rerun-all replays the existing chain; substitute only its OS-changing Zed endpoint.
        zed = source / "scripts/setup-zed.sh"; original_zed = zed.read_text()
        zed.write_text("#!/bin/bash\nexit 0 # supplied setup effect; no package/service mutation\n")
        run("scripts/migrate.sh", "--rerun-all")
        assert legacy_stamp.read_text().strip() == "5"
        assert (legacy / ".bashrc").read_bytes() == original_bytes
        zed.write_text(original_zed)
        replay = subprocess.run(["python3", str(source / "scripts/deployment.py"), "deploy"], env=env, capture_output=True, text=True)
        assert replay.returncode == 0, replay.stderr
        # A real user file is an ownership conflict and prevents stamping.
        blocked_home = temp / "blocked home"; blocked_home.mkdir()
        protected = blocked_home / ".bashrc"; protected.write_text("user-owned\n")
        blocked_stamp = blocked_home / ".config/dotfiles-arch/.dotfiles_schema_version"
        blocked_stamp.parent.mkdir(parents=True); blocked_stamp.write_text("4\n")
        env.update(HOME=str(blocked_home), TEST_HOME=str(blocked_home), USER_HOME_DIR=str(blocked_home),
                   CODEX_HOME=str(blocked_home / ".codex"), PI_CODING_AGENT_DIR=str(blocked_home / ".pi/agent"))
        run("scripts/migrate.sh", ok=False)
        assert protected.read_text() == "user-owned\n" and blocked_stamp.read_text() == "4\n"
        protected.unlink(); protected.symlink_to(source / "missing-original-source")
        run("scripts/migrate.sh", ok=False)
        assert protected.is_symlink() and blocked_stamp.read_text() == "4\n"
        # Old rename landmarks still precede the resolving-link fallback.
        (blocked_home / ".local/bin").mkdir(parents=True)
        (blocked_home / ".local/bin/dfa-morning").symlink_to(source / "old-morning")
        blocked_stamp.unlink()
        assert "v2" in run("scripts/migrate.sh", "--dry-run").stdout
        # Restore fresh fixture home; installed source absence requires no credentials.
        env.update(HOME=str(home), TEST_HOME=str(home), USER_HOME_DIR=str(home),
                   CODEX_HOME=str(home / ".codex"), PI_CODING_AGENT_DIR=str(home / ".pi/agent"))
        # Installed helper dependency closure works after its source disappears.
        source.rename(temp / "removed checkout")
        helper = installed / "home/.local/bin/dfa-check-dotfiles"
        check = subprocess.run(["bash", str(helper)], env=env, capture_output=True, text=True)
        assert check.returncode == 0, check.stdout + check.stderr
        print("PASS: complete repository generation, fresh/unstamped migration, idempotence and missing-checkout runtime")


if __name__ == "__main__":
    main()
    working_tree_deployment()
    full_repository()
