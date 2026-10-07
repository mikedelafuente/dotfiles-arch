"""Run with python3 tests/test_skill_sync.py; all mutations stay in /tmp."""
import os
from pathlib import Path
import shutil
import shlex
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    with tempfile.TemporaryDirectory(prefix="nested-skill-sync-") as temp:
        tmp = Path(temp)
        repo = tmp / "source checkout"
        shutil.copytree(ROOT / "scripts", repo / "scripts")
        # Keep real library/installer code; redirect only the machine home header.
        (repo / "scripts/dotheader.sh").write_text(
            'set -euo pipefail\nUSER_HOME_DIR="$TEST_HOME"\n'
            'DF_SCRIPT_DIR="$(dirname "${BASH_SOURCE[0]}")"\n'
            'source "$DF_SCRIPT_DIR/fn-lib.sh"\n')
        home = tmp / "test home"
        skill = repo / "skills/author/deep/example"
        skill.mkdir(parents=True)
        (skill / "SKILL.md").write_text("example")
        (skill.parent / "notes.md").write_text("Not a skill")
        guard = tmp / "bin"
        guard.mkdir()
        (guard / "codex").write_text("#!/bin/sh\nexit 0\n")
        (guard / "codex").chmod(0o755)
        env = dict(os.environ, TEST_HOME=str(home),
                   CODEX_HOME=str(home / ".codex"), PI_CODING_AGENT_DIR=str(home / ".pi/agent"),
                   PATH=str(guard) + os.pathsep + os.environ["PATH"])
        targets = [home / p for p in
                   (".claude/skills", ".cursor/skills", ".codex/skills", ".pi/agent/skills")]

        def run(success=True):
            result = subprocess.run(["bash", str(repo / "scripts/sync-skills.sh")],
                                    env=env, text=True, capture_output=True)
            assert (result.returncode == 0) == success, result.stdout + result.stderr
            return result

        # External leaf aliases must fail even on a first install.
        external_skill = tmp / "external skill"
        external_skill.mkdir()
        (external_skill / "SKILL.md").write_text("unapproved external skill")
        external_alias = repo / "skills/external-alias"
        external_alias.symlink_to(external_skill, target_is_directory=True)
        assert "External source skill symlink" in run(False).stderr
        assert not home.exists()
        external_alias.unlink()
        # A marker symlink cannot load an unaudited prompt from outside the root.
        marker = skill / "SKILL.md"
        marker.unlink()
        marker.symlink_to(external_skill / "SKILL.md")
        run(False)
        assert not home.exists()
        marker.unlink(); marker.write_text("example")
        run()
        for target in targets:
            assert list(target.iterdir()) == [target / "example"]
            assert (target / "example").resolve() == skill
        # Link failures must propagate despite the caller's conditional function call.
        (guard / "ln").write_text("#!/bin/sh\nexit 1\n")
        (guard / "ln").chmod(0o755)
        failed = run(False)
        assert "Linked:" not in failed.stdout and "Skills synced:" not in failed.stdout
        (guard / "ln").unlink()
        run()
        # A former flat link is upgraded after the source moves into a group.
        old = repo / "skills/example"
        skill.rename(old)
        run()
        assert all((t / "example").resolve() == old for t in targets)
        old.rename(skill)
        run()
        assert all((t / "example").resolve() == skill for t in targets)
        alias = repo / "skills/internal-alias"
        alias.symlink_to(skill, target_is_directory=True)
        run()
        run()
        alias.unlink()
        run()
        assert all(not (t / "internal-alias").is_symlink() for t in targets)
        # Collision in another configured source fails before any mutations.
        extra = tmp / "extra source"
        duplicate = extra / "nested/example"
        duplicate.mkdir(parents=True)
        (duplicate / "SKILL.md").write_text("duplicate")
        config = home / ".config/dotfiles-arch/sync-sources"
        config.parent.mkdir(parents=True, exist_ok=True)
        config.write_text(f"skills-root:{extra}\n")
        snapshot = {str(t): {p.name: os.readlink(p) for p in t.iterdir()} for t in targets}
        assert "Duplicate skill name" in run(False).stderr
        assert {str(t): {p.name: os.readlink(p) for p in t.iterdir()} for t in targets} == snapshot
        # An overwritable company source loses silently to dotfiles-arch.
        config.write_text(f"skills-root:{extra}\toverwritable=true\n")
        allowed = run()
        assert "Duplicate skill name" not in allowed.stderr
        assert all((t / "example").resolve() == skill for t in targets)
        # Between extras, a later source may replace only an overwritable owner.
        second = tmp / "second source"
        for directory in (extra / "shared", second / "shared"):
            directory.mkdir(parents=True)
            (directory / "SKILL.md").write_text("shared")
        config.write_text(f"skills-root:{extra}\toverwritable=true\nskills-root:{second}\n")
        run()
        assert all((t / "shared").resolve() == second / "shared" for t in targets)
        config.write_text(f"skills-root:{extra}\nskills-root:{second}\n")
        assert "overwritable=false" in run(False).stderr
        assert all((t / "shared").resolve() == second / "shared" for t in targets)
        # Permission to overwrite another source never hides duplicates within one root.
        internal = extra / "another/shared"
        internal.mkdir(parents=True)
        (internal / "SKILL.md").write_text("ambiguous")
        config.write_text(f"skills-root:{extra}\toverwritable=true\n")
        assert "Duplicate skill name" in run(False).stderr
        shutil.rmtree(internal.parent)
        # CLI add/update/list and config rewrites preserve/default the setting.
        def sources(*args, success=True):
            result = subprocess.run(["bash", str(repo / "scripts/sync-sources.sh"), *args],
                                    env=env, text=True, capture_output=True)
            assert (result.returncode == 0) == success, result.stdout + result.stderr
            return result
        def manage(keys):
            result = subprocess.run(
                ["script", "--quiet", "--return", "--command",
                 shlex.join(["bash", str(repo / "scripts/sync-sources.sh"), "manage"]),
                 "/dev/null"], input=keys, env=env, text=True, capture_output=True, timeout=10)
            assert result.returncode == 0, result.stdout + result.stderr
            return result
        config.write_text("")
        assert "No extra sources to change" in manage("5\nq\n").stdout
        sources("add", str(extra), "--type", "skills-root")
        assert "overwritable=false" in sources("list").stdout
        before = config.read_text()
        manage("5\n\nq\n")
        manage("5\ninvalid\nq\n")
        assert config.read_text() == before
        manage("5\n1\nq\n")
        assert "overwritable=true" in sources("list").stdout
        manage("5\n1\nq\n")
        assert "overwritable=false" in sources("list").stdout
        sources("add", str(extra), "--type", "skills-root", "--overwritable", "true")
        sources("add", str(second), "--type", "skills-root")
        assert "overwritable=true" in sources("list").stdout
        # The reorder writer keeps the flag attached to its source, not its index.
        subprocess.run(["bash", "-c",
                        'source "$1/scripts/fn-lib.sh"; source "$1/scripts/sync-sources-lib.sh"; '
                        '_read_sync_source_repo_lines; '
                        'SYNC_SOURCE_REPOS=("${SYNC_SOURCE_REPO_LINES[1]}" "${SYNC_SOURCE_REPO_LINES[0]}"); '
                        'SYNC_SOURCE_REPO_TYPES=("${SYNC_SOURCE_REPO_LINE_TYPES[1]}" "${SYNC_SOURCE_REPO_LINE_TYPES[0]}"); '
                        'write_sync_source_repos', "test", str(repo)],
                       env=dict(env, USER_HOME_DIR=str(home)), check=True, capture_output=True)
        entries = [line for line in config.read_text().splitlines() if not line.startswith("#")]
        assert entries == [f"skills-root:{second}", f"skills-root:{extra}\toverwritable=true"]
        sources("add", str(extra), "--type", "skills-root")
        assert "overwritable=true" in config.read_text()
        sources("remove", str(second), "--type", "skills-root")
        assert "overwritable=true" in config.read_text()
        sources("add", str(extra), "--type", "skills-root", "--overwritable=false")
        assert "overwritable=false" in sources("list").stdout
        before = config.read_text()
        sources("add", str(extra), "--overwritable=maybe", success=False)
        assert config.read_text() == before
        config.write_text(f"skills-root:{extra}\toverwritable=maybe\n")
        assert "Invalid overwritable value" in run(False).stderr
        config.write_text("")
        # An unrelated destination blocks all destinations, even later ones.
        (targets[-1] / "example").unlink()
        (targets[-1] / "example").mkdir()
        new = repo / "skills/author/another"
        new.mkdir(); (new / "SKILL.md").write_text("another")
        run(False)
        assert all(not (t / "another").exists() for t in targets)
        (targets[-1] / "example").rmdir()
        external = tmp / "external"; external.mkdir()
        (targets[-1] / "example").symlink_to(external)
        run(False)
        assert (targets[-1] / "example").resolve() == external
        (targets[-1] / "example").unlink()
        run()
        # Stale managed links are pruned; unrelated links and aliases survive.
        for target in targets:
            (target / "manual-alias").symlink_to(skill)
            (target / "unrelated").symlink_to(external)
        shutil.rmtree(skill)
        run()
        for target in targets:
            assert not (target / "example").is_symlink()
            assert (target / "manual-alias").is_symlink()
            assert (target / "unrelated").resolve() == external
        # Explicit source removal understands nested managed links.
        managed = targets[0] / "example"
        managed.symlink_to(duplicate)
        subprocess.run(["bash", "-c",
                        'source "$1/scripts/fn-lib.sh"; source "$1/scripts/sync-sources-lib.sh"; '
                        'prune_sync_source_repo_symlinks "$2" skills-root "$3"',
                        "test", str(repo), str(extra), str(targets[0])],
                       env=dict(env, USER_HOME_DIR=str(home)), check=True, capture_output=True)
        assert not managed.is_symlink()
        # Verify the actual author/category tree, not only synthetic nested folders.
        shutil.rmtree(repo / "skills")
        shutil.copytree(ROOT / "skills", repo / "skills")
        run()
        expected = {marker.parent.name: marker.parent
                    for marker in (repo / "skills").rglob("SKILL.md")}
        for target in targets:
            for name, parent in expected.items():
                assert (target / name).is_symlink()
                assert (target / name).resolve() == parent.resolve()
                assert (target / name / "SKILL.md").is_file()
            for group in ("mattpocock", "mikedelafuente", "engineering", "productivity", "misc"):
                assert not (target / group).exists()
        run()
        print("PASS: nested workstation mapping, all harnesses, moves, aliases, collisions,")
        print("preflight preservation, pruning, and explicit nested-source removal")


if __name__ == "__main__":
    main()
