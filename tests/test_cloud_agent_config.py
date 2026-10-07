"""Run with python3 tests/test_cloud_agent_config.py; all writes stay in /tmp."""
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def run(source, home, *, success=True, codex_home=None):
    env = dict(os.environ)
    env.pop("CODEX_HOME", None)
    env["PATH"] = str(source.parent / "guard-bin") + os.pathsep + env["PATH"]
    if codex_home:
        env["CODEX_HOME"] = str(codex_home)
    result = subprocess.run(["bash", str(source / "scripts/install-cloud-agent-config.sh"),
                             "--home", str(home)], env=env, capture_output=True, text=True)
    assert (result.returncode == 0) == success, result.stdout + result.stderr
    return result


def main():
    with tempfile.TemporaryDirectory(prefix="dotfiles-cloud-test-") as temp:
        tmp = Path(temp)
        # Copy the actual checkout into a different cloud-like path, with spaces.
        source = tmp / "workspace" / "dotfiles checkout"
        source.mkdir(parents=True)
        for name in ("scripts", "skills", "rules"):
            shutil.copytree(ROOT / name, source / name)
        guard = source.parent / "guard-bin"
        guard.mkdir()
        for command in ("pacman", "yay", "sudo", "systemctl", "gsettings", "git", "curl", "wget"):
            sentinel = guard / command
            sentinel.write_text("#!/bin/sh\necho 'Forbidden cloud install side effect' >&2\nexit 97\n")
            sentinel.chmod(0o755)
        home = tmp / "cloud-user"
        target = home / ".agents/skills"
        target.mkdir(parents=True)
        unrelated = target / "user-owned"
        unrelated.mkdir()
        (unrelated / "SKILL.md").write_text("My existing skill")
        agents = home / ".codex/AGENTS.md"
        agents.parent.mkdir()
        agents.write_text("# Existing global agreement\nKeep this verbatim.\n")
        agents.chmod(0o600)
        project = tmp / "workspace/Trellis"
        project.mkdir()
        (project / "AGENTS.md").write_text("# Trellis\nProject-specific instructions.\n")
        before = (project / "AGENTS.md").read_bytes()

        (home / ".bashrc").write_text("SHELL SETTINGS SENTINEL")
        (home / ".codex/config.toml").write_text("CODEX SETTINGS SENTINEL")
        (target / "manual-alias").symlink_to(source / "skills/mikedelafuente/advising")
        # Conditional rules and README never become unconditional instructions.
        (source / "rules/conditional.md").write_text(
            "---\nalwaysApply: false\nglobs: *.py\n---\nCONDITIONAL SENTINEL\n")
        (source / "rules/README.md").write_text(
            "---\nalwaysApply: true\n---\nREADME SENTINEL\n")
        run(source, home)
        expected_paths = {p.parent.name: p.parent for p in (source / "skills").rglob("SKILL.md")}
        expected = set(expected_paths)
        assert expected <= {p.name for p in target.iterdir()}
        for name in expected:
            assert (target / name).is_symlink()
            assert (target / name).resolve() == expected_paths[name]
            assert (target / name / "SKILL.md").is_file()
        for skill, ref in (("advising", "../../mattpocock/productivity/grilling/SKILL.md"),
                           ("agent-council", "../advising/SKILL.md"),
                           ("advise-with-docs", "../../mattpocock/engineering/domain-modeling/SKILL.md"),
                           ("review-changes", "../adversarial-code-review/SKILL.md")):
            assert (target / skill / ref).is_file()
        assert (target / "agent-council/references/record.md").is_file()
        content = agents.read_text()
        assert content.startswith("# Existing global agreement\nKeep this verbatim.\n")
        assert "# Ponytail, lazy senior dev mode" in content
        assert "CONDITIONAL SENTINEL" not in content and "README SENTINEL" not in content
        assert "Arch Linux workstation" not in content
        assert agents.stat().st_mode & 0o777 == 0o600
        assert (project / "AGENTS.md").read_bytes() == before
        assert (unrelated / "SKILL.md").read_text() == "My existing skill"
        run(source, home)
        assert agents.read_text() == content
        assert agents.read_text().count("<!-- dotfiles-arch cloud baseline begin -->") == 1

        # Moves update owned links, including the former flat layout.
        old = source / "skills/mattpocock/productivity/wait-what"
        old.rename(source / "skills/wait-what")
        run(source, home)
        assert (target / "wait-what").resolve() == source / "skills/wait-what"
        (source / "skills/wait-what").rename(old)
        run(source, home)
        assert (target / "wait-what").resolve() == old
        assert not any((target / group).exists() for group in
                       ("mattpocock", "mikedelafuente"))
        snapshot = {p.name: os.readlink(p) for p in target.iterdir() if p.is_symlink()}
        duplicate = source / "skills/other/advising"
        duplicate.mkdir(parents=True)
        (duplicate / "SKILL.md").write_text("duplicate")
        result = run(source, home, success=False)
        assert "Duplicate skill name" in result.stderr
        assert {p.name: os.readlink(p) for p in target.iterdir() if p.is_symlink()} == snapshot
        assert agents.read_text() == content
        shutil.rmtree(duplicate.parent)

        # Source removals prune only this checkout's managed links.
        shutil.rmtree(source / "skills/mattpocock/productivity/wait-what")
        run(source, home)
        assert not (target / "wait-what").is_symlink()
        assert unrelated.exists()
        assert (target / "manual-alias").resolve() == source / "skills/mikedelafuente/advising"
        assert (home / ".bashrc").read_text() == "SHELL SETTINGS SENTINEL"
        assert (home / ".codex/config.toml").read_text() == "CODEX SETTINGS SENTINEL"

        # A collision must fail before touching skills or global instructions.
        collision_home = tmp / "collision-user"
        real = collision_home / ".agents/skills/advising"
        real.mkdir(parents=True)
        (real / "SKILL.md").write_text("USER SENTINEL")
        run(source, collision_home, success=False)
        assert (real / "SKILL.md").read_text() == "USER SENTINEL"
        assert not (collision_home / ".codex").exists()
        assert list(real.parent.iterdir()) == [real]
        real.rename(real.with_name("custom-advising"))
        real.symlink_to(unrelated)
        run(source, collision_home, success=False)
        assert real.resolve() == unrelated

        # Destination directory redirects cannot write into unrelated checkouts.
        external = tmp / "unrelated-checkout/skills"
        external.mkdir(parents=True)
        (external / "keep.md").write_text("EXTERNAL SENTINEL")
        for name, ancestor in (("target-link-user", False), ("ancestor-link-user", True)):
            redirected_home = tmp / name
            if ancestor:
                redirected_home.mkdir()
                (redirected_home / ".agents").symlink_to(external.parent)
            else:
                (redirected_home / ".agents").mkdir(parents=True)
                (redirected_home / ".agents/skills").symlink_to(external)
            result = run(source, redirected_home, success=False)
            assert "redirected skill directory" in result.stderr
            assert list(external.iterdir()) == [external / "keep.md"]
            assert (external / "keep.md").read_text() == "EXTERNAL SENTINEL"
            assert not (redirected_home / ".codex").exists()

        # Supported internal source-directory symlinks remain rerunnable/prunable.
        alias = source / "skills/internal-alias"
        alias.symlink_to("mikedelafuente/advising", target_is_directory=True)
        run(source, home)
        run(source, home)
        assert (target / "internal-alias").resolve() == source / "skills/mikedelafuente/advising"
        alias.unlink()
        run(source, home)
        assert not (target / "internal-alias").is_symlink()
        assert (target / "manual-alias").is_symlink()

        # Honor an existing CODEX_HOME without editing config, tokens, or override.
        relocated = tmp / "relocated-codex"
        run(source, tmp / "relocated-user", codex_home=relocated)
        assert (relocated / "AGENTS.md").is_file()
        assert not (tmp / "relocated-user/.codex").exists()
        (relocated / "AGENTS.override.md").write_text("Must remain active")
        result = run(source, tmp / "override-user", codex_home=relocated, success=False)
        assert "mask the baseline" in result.stderr
        assert not (tmp / "override-user").exists()
        (relocated / "AGENTS.override.md").unlink()
        (relocated / "AGENTS.md").write_text("<!-- dotfiles-arch cloud baseline begin -->")
        run(source, tmp / "bad-marker-user", codex_home=relocated, success=False)
        assert not (tmp / "bad-marker-user").exists()
        (relocated / "AGENTS.md").unlink()
        (relocated / "AGENTS.md").symlink_to(agents)
        run(source, tmp / "global-link-user", codex_home=relocated, success=False)
        assert agents.read_text() == content

        # Refuse external/broken source dependencies, even in supporting assets.
        (source / "skills/mikedelafuente/agent-council/outside").symlink_to(unrelated)
        run(source, tmp / "external-link-user", success=False)
        assert not (tmp / "external-link-user").exists()
        print(f"PASS: {len(expected)} skills, relocated checkout/home, references, rules, reruns,")
        print("owned pruning, collision/override/marker/symlink failures, project preservation")


if __name__ == "__main__":
    main()
