"""Registered standard sources deliver Pi data through a retained generation."""
import json
import os
from pathlib import Path
import subprocess
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

        registry = home / ".config/dotfiles-arch/sync-sources"
        registry.parent.mkdir(parents=True)
        registry.write_text(f"standard:{extra}\n")
        env = dict(os.environ, HOME=str(home), USER_HOME_DIR=str(home),
                   CODEX_HOME=str(home / ".codex"), PI_CODING_AGENT_DIR=str(home / ".pi/agent"))
        result = subprocess.run(["python3", str(CLI), "deploy", "--source", str(primary)],
                                env=env, capture_output=True, text=True)
        assert result.returncode == 0, result.stdout + result.stderr

        active = home / ".local/share/workstation/config"
        manifest = json.loads((active.resolve().parent / "manifest.json").read_text())
        extra_id = manifest["sources"][1]["id"]
        for relative in ("pi/models.json", "pi/settings.json", "pi/agents/reviewer.md", "pi/prompts/review.md"):
            target = home / ".pi/agent" / relative.removeprefix("pi/")
            assert target.is_symlink() and target.read_text() == (extra / relative).read_text()
            assert os.readlink(target).startswith(str(active))
            assert f"extras/{extra_id}/{relative}" in manifest["artifacts"]
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
        print("PASS: standard-source Pi data, primary rule precedence, exclusions and no source execution")


if __name__ == "__main__":
    main()
