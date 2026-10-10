"""Deployment CLI checks with temporary homes; no workstation mutations."""
import fcntl
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / "scripts/deployment.py"


def main():
    with tempfile.TemporaryDirectory(prefix="dfa-copy-") as raw:
        temp = Path(raw)
        home, source = temp / "home", temp / "source"
        home.mkdir(); source.mkdir()
        def git(*args):
            return subprocess.run(["git", "-C", str(source), *args], check=True,
                                  capture_output=True, text=True).stdout.strip()
        git("init", "-b", "main")
        git("config", "user.name", "Fixture")
        git("config", "user.email", "fixture@example.test")
        git("remote", "add", "origin", "https://github.com/example/source.git")
        (source / "scripts").mkdir()
        (source / "scripts/sync.sh").write_text("#!/bin/bash\nexit 0\n")
        (source / "home").mkdir()
        (source / "home/.bashrc").write_text("source one\n")
        git("add", "."); git("commit", "-m", "fixture")
        env = dict(os.environ, HOME=str(home), USER_HOME_DIR=str(home),
                   CODEX_HOME=str(home / ".codex"), PI_CODING_AGENT_DIR=str(home / ".pi/agent"))
        def run(*args, ok=True):
            result = subprocess.run(["python3", str(CLI), *args], env=env,
                                    capture_output=True, text=True)
            assert (result.returncode == 0) == ok, result.stdout + result.stderr
            return result
        run("deploy", "--source", str(source))
        live = home / ".bashrc"
        live.write_text("installed edit\n")
        (source / "home/.bashrc").write_text("source two\n")
        run("deploy")
        assert live.read_text() == "source two\n", "Installed edits must be replaced from source"
        state = home / ".local/share/workstation"
        assert (state / "previous/home/.bashrc").read_text() == "installed edit\n"
        assert not (state / "generations").exists()
        assert not list(state.rglob("manifest.json"))
        assert not (state / "staging").exists()
        run("rollback")
        assert live.read_text() == "installed edit\n"
        # Migration preserves the active legacy bytes and prunes only managed history.
        run("deploy")
        live.write_text("legacy installed edit\n")
        legacy = state / "generations/old-id"
        legacy.parent.mkdir()
        shutil.copytree(state / "config", legacy / "tree", symlinks=True)
        sources = json.loads((legacy / "tree/.dfa/sources.json").read_text())
        links = json.loads((legacy / "tree/.dfa/links.json").read_text())
        shutil.rmtree(legacy / "tree/.dfa")
        (legacy / "manifest.json").write_text(json.dumps({"version": 1, "sources": sources,
            "links": {k: {"artifact": v} for k,v in links.items()}, "artifacts": {}}))
        shutil.copytree(legacy, state / "generations/older-id")
        (state / "config").unlink(); (state / "config").symlink_to(legacy / "tree")
        (state / "previous").unlink()
        shutil.rmtree(state / "blue"); shutil.rmtree(state / "green")
        overrides = state / "overrides/home"
        overrides.mkdir(parents=True); (overrides / ".bashrc").write_text("retired override\n")
        (source / "bad.json").write_text("invalid json")
        run("deploy", ok=False)
        assert live.read_text() == "legacy installed edit\n"
        assert legacy.exists() and (state / "generations/older-id").exists()
        (source / "bad.json").unlink()
        run("deploy")
        assert (state / "config").resolve() == state / "green"
        assert (state / "previous/home/.bashrc").read_text() == "legacy installed edit\n"
        assert not (state / "generations").exists() and not (state / "overrides").exists()
        assert not list(state.rglob("manifest.json"))
        current = os.readlink(state / "config")
        run("deploy")
        assert os.readlink(state / "config") == current
        run("rollback")
        assert live.read_text() == "legacy installed edit\n"
        assert (state / "config").resolve() == state / "blue"
        # Faults occur at OS boundaries, after real filesystem writes.
        faults = temp / "faults"
        faults.mkdir()
        (faults / "sitecustomize.py").write_text(
            "import os\n"
            "original = os.replace\n"
            "def replace(src, dst, *args, **kwargs):\n"
            "    original(src, dst, *args, **kwargs)\n"
            "    if str(dst) == os.environ['FAIL_TARGET']:\n"
            "        os._exit(91)\n"
            "os.replace = replace\n")
        before = live.read_text()
        for target in (state / "config", live):
            (source / "home/.bashrc").write_text("after interruption\n")
            env.update(PYTHONPATH=str(faults), FAIL_TARGET=str(target))
            assert run("deploy", ok=False).returncode == 91
            env.pop("PYTHONPATH"); env.pop("FAIL_TARGET")
            run("status", ok=False)
            run("recover")
            assert live.read_text() == before
            assert not (state / "staging").exists() and not (state / "transaction.json").exists()
        # Syntax/copy ownership failures preserve the active configuration.
        (source / "bad.sh").write_text("#!/bin/bash\nif\n")
        pointer = os.readlink(state / "config")
        run("deploy", ok=False)
        assert os.readlink(state / "config") == pointer and live.read_text() == before
        (source / "bad.sh").unlink()
        live.unlink(); live.write_text("foreign file\n")
        run("deploy", ok=False)
        assert live.read_text() == "foreign file\n"
        live.unlink(); live.symlink_to(state / "config/home/.bashrc")
        with (state / "lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            assert "Another deployment" in run("deploy", ok=False).stderr
        run("deploy")
        # Repeated updates only alternate blue/green; no accumulating history.
        for number in range(3):
            (source / "home/.bashrc").write_text(f"source {number}\n")
            run("deploy")
            assert {p.name for p in state.iterdir() if p.is_dir() and not p.is_symlink()} == {"blue", "green"}
        assert live.read_text() == "source 2\n"
        print("PASS: copying, migration, rollback, interruption, failure preservation and concurrency")


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
        paths |= {"scripts/deployment.py", "home/.local/bin/dfa-deploy", "migrations/v4-to-v5-migration.sh", "docs/deployment.md", "migrations/v5-to-v6-migration.sh"}
        for name in paths:
            src = ROOT / name; dst = source / name
            if not src.exists() and not src.is_symlink():
                continue  # Include pending working-tree deletions in the fixture.
            dst.parent.mkdir(parents=True, exist_ok=True)
            if src.is_symlink():
                dst.symlink_to(os.readlink(src))
            else:
                shutil.copy2(src, dst)
        (source / "scripts/dotheader.sh").write_text(
            '#!/bin/bash\nset -euo pipefail\nUSER_HOME_DIR="$TEST_HOME"\nexport USER_HOME_DIR\n'
            'DF_SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"\n# shellcheck source=/dev/null\nsource "$DF_SCRIPT_DIR/fn-lib.sh"\n')
        # Synthetic shared data exercises legacy migration after payload contraction.
        marker = source / "skills/fixture/SKILL.md"
        marker.parent.mkdir(parents=True, exist_ok=True); marker.write_text("fixture skill\n")
        state = source / "pi/models-store.json"
        state.parent.mkdir(parents=True, exist_ok=True); state.write_text("{}\n")
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
        assert stamp.read_text().strip() == "6"
        installed = home / ".local/share/workstation/config"
        # The installed manager must identify the edit checkout, not its runtime.
        listed = run(str(installed / "scripts/sync-sources.sh"), "list").stdout
        assert f"Primary (always, standard): {source}" in listed, listed
        assert (home / ".packages.md").read_text() == (source / "PACKAGES.md").read_text()
        assert (home / ".pi/agent/models-store.json").exists() is False
        assert not (home / ".pi/agent/auth.json").exists()
        targets = [p for root in (home / ".claude/skills", home / ".cursor/skills", home / ".codex/skills", home / ".pi/agent/skills") for p in root.iterdir()]
        assert targets and all(p.is_symlink() and str(installed) in os.readlink(p) for p in targets)
        previous = os.readlink(installed)
        run("scripts/migrate.sh")
        assert os.readlink(installed) == previous
        # The real schema runner must neither stamp nor prune a failed v5 conversion.
        state_root = home / ".local/share/workstation"
        legacy = state_root / "generations/legacy-active"
        shutil.copytree(installed, legacy / "tree", symlinks=True)
        sources = json.loads((legacy / "tree/.dfa/sources.json").read_text())
        links = json.loads((legacy / "tree/.dfa/links.json").read_text())
        shutil.rmtree(legacy / "tree/.dfa")
        (legacy / "manifest.json").write_text(json.dumps({"version": 1, "sources": sources,
            "links": {k: {"artifact": v} for k,v in links.items()}}))
        (legacy / "tree/home/.bashrc").write_text("# preserved installed change\n")
        installed.unlink(); installed.symlink_to(legacy / "tree")
        shutil.rmtree(state_root / "blue")
        stamp.write_text("5\n")
        run("scripts/migrate.sh", "--dry-run")
        assert stamp.read_text() == "5\n" and legacy.exists()
        (source / "invalid.json").write_text("bad JSON")
        run("scripts/migrate.sh", ok=False)
        assert stamp.read_text() == "5\n" and legacy.exists()
        assert installed.resolve() == legacy / "tree"
        (source / "invalid.json").unlink()
        run("scripts/migrate.sh")
        assert stamp.read_text() == "6\n" and not legacy.exists()
        assert installed.resolve() == state_root / "green"
        assert (state_root / "previous/home/.bashrc").read_text() == "# preserved installed change\n"
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
        # Runtime remains usable after many blue/green switches and source disappearance.
        for number in range(3):
            (source / "home/.bashrc").write_text(shell_before + f"\n# switch {number}\n")
            subprocess.run(["python3", str(source / "scripts/deployment.py"), "deploy"], env=env, check=True, capture_output=True)
        source.rename(temp / "removed checkout")
        helper = installed / "home/.local/bin/dfa-check-dotfiles"
        checked = subprocess.run(["bash", str(helper)], env=env, capture_output=True, text=True)
        assert checked.returncode == 0, checked.stdout + checked.stderr
        print("PASS: fresh schema migration, daily ordering, repeated switching, source-independent runtime")


if __name__ == "__main__":
    main()
    working_tree_deployment()
    full_repository()
