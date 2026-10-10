"""Registered standard sources deliver Pi data through the installed copy."""
import json
import os
from pathlib import Path
import subprocess
import shutil
import tempfile


ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / "scripts/deployment.py"


def main():
    with tempfile.TemporaryDirectory(prefix="dfa-generic-consumer-") as raw:
        temp = Path(raw)
        home, primary, extra = temp / "home", temp / "primary", temp / "skills"
        home.mkdir(); primary.mkdir(); extra.mkdir()

        def git(*args):
            return subprocess.run(["git", "-C", str(primary), *args], check=True,
                                  capture_output=True, text=True).stdout.strip()

        git("init", "-b", "main")
        git("config", "user.email", "fixture@example.test")
        git("config", "user.name", "Fixture")
        git("remote", "add", "origin", "https://github.com/example/primary.git")
        (primary / "scripts").mkdir()
        (primary / "scripts/sync.sh").write_text("#!/bin/sh\nexit 0\n")
        (primary / "rules").mkdir()
        (primary / "rules/shared.mdc").write_text(
            "---\nalwaysApply: true\n---\nPRIMARY RULE\n")
        git("add", "."); git("commit", "-m", "primary")

        (extra / "skills/custom").mkdir(parents=True)
        (extra / "skills/custom/SKILL.md").write_text("custom skill\n")
        (extra / "rules").mkdir()
        (extra / "rules/shared.mdc").write_text(
            "---\nalwaysApply: true\n---\nEXTRA RULE\n")
        (extra / "pi/agents").mkdir(parents=True)
        (extra / "pi/prompts").mkdir(parents=True)
        (extra / "pi/extensions").mkdir(parents=True)
        (extra / "pi/models.json").write_text('{"model":"shared"}\n')
        (extra / "pi/settings.json").write_text('{"theme":"shared"}\n')
        (extra / "pi/agents/reviewer.md").write_text("review agent\n")
        (extra / "pi/prompts/review.md").write_text("review prompt\n")
        (extra / "pi/extensions/sample.ts").write_text("export default {};\n")
        (extra / "auth.json").write_text('{"token":"must stay excluded"}\n')
        (extra / "pi/models-store.json").write_text('{"runtime":"must stay excluded"}\n')
        marker = extra / "scripts/should-not-run.sh"
        marker.parent.mkdir()
        marker.write_text(f"#!/bin/sh\nprintf x > {temp / 'executed'}\n")
        (extra / "package.json").write_text('{"name":"@example/shared","pi":{"skills":["skills"]}}\n')
        for args in (("init", "-b", "main"), ("config", "user.name", "Fixture"),
                     ("config", "user.email", "fixture@example.test"),
                     ("remote", "add", "origin", "https://github.com/example/shared"),
                     ("add", "."), ("commit", "-m", "supplied shared source")):
            subprocess.run(["git", "-C", str(extra), *args], check=True, capture_output=True)

        registry = home / ".config/dotfiles-arch/sync-sources"
        registry.parent.mkdir(parents=True)
        registry.write_text(f"standard:{extra}\n")
        env = dict(os.environ, HOME=str(home), USER_HOME_DIR=str(home),
                   CODEX_HOME=str(home / ".codex"), PI_CODING_AGENT_DIR=str(home / ".pi/agent"))
        result = subprocess.run(["python3", str(CLI), "deploy", "--source", str(primary)],
                                env=env, capture_output=True, text=True)
        assert result.returncode == 0, result.stdout + result.stderr

        active = home / ".local/share/workstation/config"
        sources = json.loads((active / ".dfa/sources.json").read_text())
        extra_id = sources[1]["id"]
        assert extra_id == "skills"
        for relative in ("pi/models.json", "pi/settings.json", "pi/agents/reviewer.md", "pi/prompts/review.md"):
            target = home / ".pi/agent" / relative.removeprefix("pi/")
            assert target.is_symlink() and target.read_text() == (extra / relative).read_text()
            assert os.readlink(target).startswith(str(active))
            assert f"extras/{extra_id}/{relative}" in {p.relative_to(active).as_posix() for p in active.rglob("*")}
        assert (home / ".pi/agent/extensions/sample.ts").is_symlink()
        assert not (home / ".pi/agent/auth.json").exists()
        assert not (home / ".pi/agent/models-store.json").exists()
        assert not (temp / "executed").exists()

        rule = home / ".cursor/rules/shared.mdc"
        assert rule.is_symlink() and "PRIMARY RULE" in rule.read_text()
        pi_agents = home / ".pi/agent/AGENTS.md"
        assert "PRIMARY RULE" in pi_agents.read_text()
        assert "EXTRA RULE" not in pi_agents.read_text()
        assert (home / ".claude/skills/custom").is_symlink()
        # A package installed through Pi's native route cannot also load the
        # same source's extensions, skills and prompts from the installed copy.
        settings = home / ".pi/agent/settings.json"
        generation = os.readlink(active)
        for package_source in (str(extra), os.path.relpath(extra, settings.parent),
                               "git:github.com/example/shared@v1", "npm:@example/shared@1.0.0",
                               "npm:@example/shared", "git+https://github.com/example/shared.git#main",
                               {"source": "github:example/shared@main"}):
            settings.write_text(json.dumps({"packages": [package_source]}))
            duplicated = subprocess.run(["python3", str(CLI), "deploy", "--source", str(primary)],
                                        env=env, capture_output=True, text=True)
            assert duplicated.returncode != 0 and "duplicates registered source" in duplicated.stderr
            assert os.readlink(active) == generation
            assert json.loads(settings.read_text()) == {"packages": [package_source]}
        settings.write_text('{"skills":["~/.claude/skills"]}')
        duplicated = subprocess.run(["python3", str(CLI), "deploy", "--source", str(primary)],
                                    env=env, capture_output=True, text=True)
        assert duplicated.returncode != 0 and "cross-harness skills" in duplicated.stderr
        assert os.readlink(active) == generation
        settings.write_text('{}')
        # Translate legacy opaque IDs into readable folder names in both copies.
        state_root = active.parent
        legacy = state_root / "generations/old"
        shutil.copytree(active, legacy / "tree", symlinks=True)
        legacy_sources = json.loads((legacy / "tree/.dfa/sources.json").read_text())
        legacy_links = json.loads((legacy / "tree/.dfa/links.json").read_text())
        shutil.rmtree(legacy / "tree/.dfa")
        opaque = "607b49c05a5dd342"
        legacy_sources[1]["id"] = opaque
        (legacy / "tree/extras/skills").rename(legacy / "tree/extras" / opaque)
        for prefix in ("extras", "generated/rules"):
            folder = legacy / "tree" / prefix / "skills"
            if folder.exists():
                folder.rename(folder.parent / opaque)
        legacy_links = {k: {"artifact": v.replace("extras/skills/", f"extras/{opaque}/").replace("generated/rules/skills/", f"generated/rules/{opaque}/")} for k,v in legacy_links.items()}
        (legacy / "manifest.json").write_text(json.dumps({"version": 1, "sources": legacy_sources, "links": legacy_links}))
        active.unlink(); active.symlink_to(legacy / "tree")
        shutil.rmtree(state_root / "blue")
        result = subprocess.run(["python3", str(CLI), "deploy"], env=env, capture_output=True, text=True)
        assert result.returncode == 0, result.stdout + result.stderr
        assert json.loads((active / ".dfa/sources.json").read_text())[1]["id"] == "skills"
        assert json.loads((state_root / "previous/.dfa/sources.json").read_text())[1]["id"] == "skills"
        assert (state_root / "previous/extras/skills/pi/models.json").exists()
        assert not list(state_root.rglob("manifest.json"))
        # An extra-source rebind preserves its readable ID and updates registration atomically.
        original_registry = registry.read_text()
        moved = temp / "renamed shared source"
        extra.rename(moved)
        (moved / "invalid.json").write_text("bad JSON")
        for args in (("add", "."), ("commit", "-m", "invalid fixture")):
            subprocess.run(["git", "-C", str(moved), *args], check=True, capture_output=True)
        failed = subprocess.run(["python3", str(CLI), "rebind", str(moved), "--source-id", "skills"], env=env, capture_output=True, text=True)
        assert failed.returncode != 0 and registry.read_text() == original_registry
        (moved / "invalid.json").unlink()
        for args in (("add", "."), ("commit", "-m", "valid fixture")):
            subprocess.run(["git", "-C", str(moved), *args], check=True, capture_output=True)
        rebound = subprocess.run(["python3", str(CLI), "rebind", str(moved), "--source-id", "skills"], env=env, capture_output=True, text=True)
        assert rebound.returncode == 0, rebound.stdout + rebound.stderr
        assert str(moved) in registry.read_text()
        assert json.loads((active / ".dfa/sources.json").read_text())[1]["id"] == "skills"
        print("PASS: standard resources, precedence, exclusions, legacy IDs and atomic rebind")


if __name__ == "__main__":
    main()
