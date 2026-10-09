"""Supplied-fact CLI decisions only; never run setup or package managers."""
from pathlib import Path
import os
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    with tempfile.TemporaryDirectory(prefix="core-cli-decisions-") as temp:
        guard = Path(temp) / "bin"
        guard.mkdir()
        for name in ("sudo", "pacman", "yay", "apt", "apt-get", "apt-cache",
                     "dpkg", "dpkg-query", "curl", "wget", "git", "npm", "node",
                     "systemctl", "gsettings", "chsh"):
            script = guard / name
            script.write_text('#!/bin/sh\necho "Forbidden command" >&2\nexit 97\n')
            script.chmod(0o755)
        env = dict(os.environ, DF_SCRIPT_DIR=str(ROOT / "scripts"),
                   USER_HOME_DIR=temp, PATH=str(guard) + os.pathsep + os.environ["PATH"])

        def decide(command, expected="", ok=True):
            result = subprocess.run(
                ["bash", "-eu", "-o", "pipefail", "-c",
                 'source "$DF_SCRIPT_DIR/fn-lib.sh"; ' + command],
                env=env, capture_output=True, text=True,
            )
            assert "Forbidden command" not in result.stdout + result.stderr
            assert result.returncode == (0 if ok else 1), result.stdout + result.stderr
            if ok:
                assert result.stdout.strip() == expected, result.stdout

        decide("core_cli_recipe ubuntu fd", "fd-find fdfind native 8.0.0")
        decide("core_cli_recipe arch fd", "fd fd native 8.0.0")
        decide("core_cli_recipe ubuntu github-cli", "gh gh native 2.0.0")
        decide("core_cli_recipe ubuntu glow", "glow glow charm 1.0.0")
        decide("core_cli_recipe ubuntu unknown", ok=False)
        for version, ok in (("0.48.0", True), ("0.67.0", True), ("1.0.0", True),
                            ("0.47.9", False), ("unknown", False), ("$(exit 97)", False)):
            decide(f"core_cli_version_at_least '{version}' 0.48.0", ok=ok)
        decide("core_cli_source_allowed true /usr/bin/gh /usr/bin/gh")
        decide("core_cli_source_allowed false '' /usr/bin/gh")
        decide("core_cli_source_allowed false /usr/local/bin/gh /usr/bin/gh", ok=False)
        decide("core_cli_source_allowed true /snap/bin/gh /usr/bin/gh", ok=False)
        target = Path(temp) / "command"
        source = Path(temp) / "native"
        source.write_text("native command")
        decide(f'core_cli_link_allowed "{source}" "{target}"')
        target.write_text("unrelated user command")
        decide(f'core_cli_link_allowed "{source}" "{target}"', ok=False)
        target.unlink()
        target.symlink_to(source)
        decide(f'core_cli_link_allowed "{source}" "{target}"')
        target.unlink()
        target.symlink_to(Path(temp) / "missing")
        decide(f'core_cli_link_allowed "{source}" "{target}"', ok=False)
        parent_link = Path(temp) / "parent-link"
        parent_link.symlink_to(guard, target_is_directory=True)
        decide(f'core_cli_link_allowed "{source}" "{parent_link}/config"', ok=False)
        for entrypoint in ("setup-essentials.sh", "setup-bash.sh", "setup-git.sh",
                           "setup-github-cli.sh", "setup-node.sh"):
            decide(f"require_workstation_entrypoint ubuntu {entrypoint}")
    print("Core CLI decisions passed (no setup workflows executed)")


if __name__ == "__main__":
    main()
