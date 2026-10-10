"""Public CLI proof for registered source identity moves; no live workstation writes."""
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
CLI = ROOT / "scripts/deployment.py"


def check(mode):
    with tempfile.TemporaryDirectory(prefix="dfa-source-handoff-") as tmp:
        root = Path(tmp)
        home, primary, extra = (root / name for name in ("home", "primary", "extra"))
        for path, url in ((primary, "workstation"), (extra, "shared")):
            path.mkdir()
            for args in (("init", "-b", "main"), ("config", "user.name", "Fixture"),
                         ("config", "user.email", "fixture@example.test"),
                         ("remote", "add", "origin", f"https://github.com/example/{url}")):
                subprocess.run(["git", "-C", str(path), *args], check=True, capture_output=True)
        (primary / "scripts").mkdir()
        (primary / "scripts/sync.sh").write_text("#!/bin/bash\nexit 0\n")
        resource = primary / "skills/example/SKILL.md"
        resource.parent.mkdir(parents=True)
        resource.write_text("one\ntwo\nthree\nfour\nfive\n")
        rule = primary / "rules/shared.mdc"
        rule.parent.mkdir()
        rule.write_text("---\nalwaysApply: true\n---\nORIGINAL RULE\n")
        state = primary / "pi/models-store.json"
        state.parent.mkdir()
        state.write_text('{"machine":"private"}\n')
        (primary / "pi/models.json").write_text('{"shared":"old","local":0}\n')
        home.mkdir()
        agent = home / ".pi/agent"
        agent.mkdir(parents=True)
        (agent / "models-store.json").symlink_to(state)
        (agent / "auth.json").write_text('{"credential":"private"}\n')
        env = dict(os.environ, HOME=str(home), USER_HOME_DIR=str(home),
                   CODEX_HOME=str(home / ".codex"), PI_CODING_AGENT_DIR=str(agent))

        def commit(path):
            for args in (("add", "."), ("commit", "--allow-empty", "-m", "supplied fixture")):
                subprocess.run(["git", "-C", str(path), *args], check=True, capture_output=True)

        def run(*args, ok=True):
            result = subprocess.run(["python3", str(CLI), *args], env=env,
                                    capture_output=True, text=True)
            assert (result.returncode == 0) == ok, result.stdout + result.stderr
            return result

        commit(primary)
        if mode == "legacy-broken":
            state.unlink()
            result = run("deploy", "--source", str(primary), ok=False)
            assert "Broken models-store link preserved" in result.stderr
            assert (agent / "models-store.json").is_symlink()
            assert (agent / "auth.json").read_text() == '{"credential":"private"}\n'
            assert not (home / ".local/share/workstation/config").exists()
            return
        run("deploy", "--source", str(primary))
        live = home / ".claude/skills/example/SKILL.md"
        active = home / ".local/share/workstation/config"
        original_generation = os.readlink(active)
        if mode == "rule-edited":
            (home / ".cursor/rules/shared.mdc").write_text("---\nalwaysApply: true\n---\nLOCAL RULE\n")
        if mode == "model-edited":
            (agent / "models.json").write_text('{"shared":"old","local":1}\n')
        assert not (agent / "models-store.json").is_symlink()
        assert (agent / "models-store.json").read_text() == state.read_text()
        old_key = "skills/example/SKILL.md"
        if mode in {"edited", "conflict", "preregistered", "dual-edits"}:
            live.write_text("LOCAL\ntwo\nthree\nfour\nfive\n")
        moved = extra / old_key
        moved.parent.mkdir(parents=True)
        moved.write_text("SHARED\ntwo\nthree\nfour\nfive\n" if mode == "conflict"
                         else "one\ntwo\nthree\nfour\nINCOMING\n")
        replacement_rule = extra / "rules/shared.mdc"
        replacement_rule.parent.mkdir()
        replacement_rule.write_text(rule.read_text())
        (extra / "pi").mkdir()
        (extra / "pi/models.json").write_text('{"shared":"new","local":0}\n')
        commit(extra)
        registry = home / ".config/dotfiles-arch/sync-sources"
        registry.parent.mkdir(parents=True, exist_ok=True)
        registry.write_text(f"standard:{extra}\toverwritable=true\n")
        if mode in {"preregistered", "dual-edits"}:
            run("deploy", "--source", str(primary))
            original_generation = os.readlink(active)
            if mode == "dual-edits":
                destination = next(active.glob("extras/*/" + old_key))
                destination.write_text("OTHER LOCAL EDIT\n")
        if mode == "unregistered":
            registry.unlink()
        shutil.rmtree(primary / "skills")
        shutil.rmtree(primary / "rules")
        shutil.rmtree(primary / "pi")
        (primary / ".dfa-source-handoffs.json").write_text(json.dumps({"version": 1, "moves": [
            {"from": "skills", "to": "skills", "source": "https://github.com/example/shared"},
            {"from": "rules", "to": "rules", "source": "https://github.com/example/shared"},
            {"from": "pi", "to": "pi", "source": "https://github.com/example/shared"}
        ]}))
        commit(primary)
        blocked_cases = {"unregistered"}
        result = run("deploy", "--source", str(primary), ok=mode not in blocked_cases)
        if mode in blocked_cases:
            reason = "manually registered"
            assert reason in result.stderr.lower()
            assert os.readlink(active) == original_generation
            assert live.read_text().startswith("one" if mode == "unregistered" else "LOCAL")
            assert run("deploy", "--source", str(primary), ok=False).stderr == result.stderr
            return
        expected = ("SHARED\ntwo\nthree\nfour\nfive\n" if mode == "conflict" else
                    "one\ntwo\nthree\nfour\nINCOMING\n")
        assert live.read_text() == expected
        if mode == "rule-edited":
            assert "ORIGINAL RULE" in (home / ".cursor/rules/shared.mdc").read_text()
        assert json.loads((agent / "models.json").read_text()) == {"shared": "new", "local": 0}
        sources = json.loads((active / ".dfa/sources.json").read_text())
        assert sources[1]["id"] == "extra"
        assert not (active / old_key).exists()
        assert (active / "extras/extra" / old_key).read_text() == expected
        generation = os.readlink(active)
        run("deploy", "--source", str(primary))
        assert os.readlink(active) == generation
        assert (agent / "auth.json").read_text() == '{"credential":"private"}\n'
        assert (agent / "models-store.json").read_text() == '{"machine":"private"}\n'
        run("rollback")
        assert live.read_text().endswith("five\n")
        assert (agent / "models-store.json").is_file()
        run("deploy", "--source", str(primary))
        assert live.read_text() == expected
        extra.rename(root / "missing-extra")
        generation = os.readlink(active)
        assert "unavailable" in run("deploy", "--source", str(primary), ok=False).stderr.lower()
        assert os.readlink(active) == generation


if __name__ == "__main__":
    for case in ("clean", "edited", "conflict", "preregistered", "dual-edits", "unregistered", "rule-edited", "model-edited", "legacy-broken"):
        check(case)
    print("PASS: source-owned handoffs, missing-source protection, machine-local state and rollback")
