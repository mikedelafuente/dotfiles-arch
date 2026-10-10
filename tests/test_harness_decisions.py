"""Supplied-fact source decisions only; never execute setup/update entrypoints."""
from pathlib import Path
import importlib.util
import tomllib
import sys
sys.dont_write_bytecode = True
import os
import shlex
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    with tempfile.TemporaryDirectory(prefix="harness-decisions-") as temp:
        guard = Path(temp) / "bin"
        guard.mkdir()
        for name in ("sudo", "pacman", "yay", "apt", "apt-get", "dpkg", "dpkg-query",
                     "curl", "wget", "npm", "node", "claude", "codex", "pi", "opencode",
                     "chatgpt", "ollama", "systemctl", "gsettings"):
            script = guard / name
            script.write_text('#!/bin/sh\necho "Forbidden command" >&2\nexit 97\n')
            script.chmod(0o755)
        env = dict(os.environ, DF_SCRIPT_DIR=str(ROOT / "scripts"), USER_HOME_DIR=temp,
                   PATH=str(guard) + os.pathsep + os.environ["PATH"])

        def decide(args, expected="", ok=True):
            result = subprocess.run(
                ["bash", "-eu", "-o", "pipefail", "-c",
                 'source "$DF_SCRIPT_DIR/fn-lib.sh"; ' + shlex.join(args)],
                env=env, capture_output=True, text=True,
            )
            assert "Forbidden command" not in result.stdout + result.stderr
            assert result.returncode == (0 if ok else 1), result.stdout + result.stderr
            if ok:
                assert result.stdout.strip() == expected, result.stdout

        decide(["harness_update_owner", "ubuntu", "opencode", "false", "", "false", "false"], "npm")
        decide(["harness_update_owner", "ubuntu", "claude", "false", "", "false", "false"], "claude-native")
        decide(["harness_update_owner", "arch", "claude", "false", "", "false", "false"], "npm")
        decide(["harness_update_owner", "ubuntu", "claude", "true", "/usr/bin/claude", "false", "false"], "native")
        decide(["harness_update_owner", "ubuntu", "claude", "true", "/user/claude", "false", "true"], ok=False)
        decide(["claude_release_checksum", "2.1.286", '{"version":"2.1.286","platforms":{"linux-x64":{"checksum":"' + "a" * 64 + '"}}}'], "a" * 64)
        decide(["claude_release_checksum", "2.1.286", '{"version":"2.1.285","platforms":{"linux-x64":{"checksum":"' + "a" * 64 + '"}}}'], ok=False)
        decide(["claude_release_checksum", "2.1.88", '{}'], ok=False)
        decide(["claude_update_policy", "1", "{}"], "defer")
        decide(["claude_update_policy", "", '{"env":{"DISABLE_UPDATES":"1"}}'], "defer")
        decide(["claude_update_policy", "", '{"env":{"DISABLE_AUTOUPDATER":"1"}}'], "update")
        decide(["claude_update_policy", "", 'invalid'], ok=False)
        for distro in ("arch", "ubuntu"):
            decide(["harness_update_owner", distro, "codex", "false", "/user/codex", "true", "false"], "npm")
            decide(["harness_update_owner", distro, "claude", "false", "/user/native", "false", "true"], "claude-native")
            decide(["harness_update_owner", distro, "pi", "false", "/unknown/pi", "false", "false"], ok=False)
        decide(["harness_update_owner", "arch", "opencode", "true", "/usr/bin/opencode", "false", "false"], "native")
        decide(["harness_update_owner", "arch", "opencode", "true", "/user/opencode", "true", "false"], ok=False)
        decide(["harness_update_owner", "ubuntu", "opencode", "true", "/usr/bin/opencode", "false", "false"], ok=False)
        decide(["chatgpt_update_owner", "ubuntu", "true", "/usr/bin/chatgpt", "true"], "apt")
        decide(["chatgpt_update_owner", "ubuntu", "true", "/usr/bin/chatgpt", "false"], ok=False)
        decide(["chatgpt_update_owner", "arch", "true", "/usr/bin/chatgpt", "false"], "aur")
        decide(["chatgpt_update_owner", "ubuntu", "false", "", "false"], "apt")
        decide(["chatgpt_update_owner", "ubuntu", "true", "/snap/bin/chatgpt", "true"], ok=False)
        source = """# Official vendor source
X-Repolib-Name: ChatGPT
Types: deb
URIs: https://persistent.oaistatic.com/codex-app-prod/linux/deb
Suites: stable
Components: main
Architectures: amd64
Signed-By: /usr/share/keyrings/chatgpt-archive-keyring.gpg
"""
        decide(["chatgpt_apt_source_valid", source])
        decide(["chatgpt_apt_source_valid", source.replace("stable", "testing")], ok=False)
        decide(["chatgpt_apt_source_valid", source + "Trusted: yes\n"], ok=False)
        for entrypoint in ("setup-claude.sh", "setup-codex.sh", "setup-opencode.sh"):
            decide(["require_workstation_entrypoint", "ubuntu", entrypoint])
    spec = importlib.util.spec_from_file_location("harness_config", ROOT / "scripts/harness-config.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    config = '[features]\nhooks = false\ncodex_hooks = true\nother = true\n[profiles.work]\nhooks = false\n'
    updated = module.enable_codex_hooks(config)
    parsed = tomllib.loads(updated)
    assert parsed["features"] == {"hooks": True, "other": True}
    assert parsed["profiles"]["work"]["hooks"] is False
    assert module.enable_codex_hooks(updated) == updated
    for config in ('[features]\n[profiles.work]\nmodel="example"\n',
                   '["features"]\n"hooks" = false # disabled\nother=true\n',
                   '[profiles.work]\nhooks=false\n', ''):
        before = tomllib.loads(config)
        after = tomllib.loads(module.enable_codex_hooks(config))
        before.setdefault("features", {})["hooks"] = True
        assert after == before
    for invalid in ('[features]\nhooks=true\nhooks=false\n', 'features = { hooks = false }'):
        try:
            module.enable_codex_hooks(invalid)
        except ValueError:
            pass
        else:
            raise AssertionError("Unsafe existing config must be retained")
    print("Harness source decisions passed (no setup/update workflows executed)")


if __name__ == "__main__":
    main()
