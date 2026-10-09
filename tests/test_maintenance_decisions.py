"""Read-only maintenance decisions; run with python3 tests/test_maintenance_decisions.py."""
from pathlib import Path
import os
import shlex
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
NOW = 2_000_000_000
LEGACY = (".last_pacman_update", ".last_pacman_upgrade", ".last_yay_update")


def decision(home, distro, command):
    env = dict(os.environ, USER_HOME_DIR=str(home), WORKSTATION_DISTRO=distro,
               DF_SCRIPT_DIR=str(ROOT / "scripts"),
               PATH=str(home / "guard-bin") + os.pathsep + os.environ["PATH"])
    result = subprocess.run(
        ["bash", "-eu", "-o", "pipefail", "-c",
         'source "$1/scripts/fn-lib.sh"; ' + command, "check", str(ROOT)],
        env=env, capture_output=True, text=True,
    )
    assert result.returncode in (0, 1), result.stdout + result.stderr
    assert "Forbidden maintenance command" not in result.stdout + result.stderr
    return result.returncode == 0


def main():
    with tempfile.TemporaryDirectory(prefix="maintenance-decisions-") as temp:
        home = Path(temp)
        guard = home / "guard-bin"
        guard.mkdir()
        for name in ("sudo", "pacman", "pacman-conf", "yay", "apt", "apt-get", "dpkg",
                     "dpkg-query", "systemctl", "gsettings", "curl", "wget", "git"):
            command = guard / name
            command.write_text('#!/bin/sh\necho "Forbidden maintenance command" >&2\nexit 97\n')
            command.chmod(0o755)
        state = home / ".config/dotfiles-arch"
        state.mkdir(parents=True)
        for stamp in LEGACY:
            (state / stamp).write_text(str(NOW - 60))
        assert decision(home, "ubuntu", f"system_upgrade_cooldown_expired {NOW}"), \
            "Arch timestamps must not suppress Ubuntu updates"
        assert not decision(home, "arch", f"system_upgrade_cooldown_expired {NOW}"), \
            "Existing successful Arch state must survive migration"
        before = {p.name: p.read_bytes() for p in state.iterdir()}
        for value in (NOW - 86400, 0, NOW + 1, "broken", "$(exit 97)", "9" * 30):
            (state / LEGACY[2]).write_text(str(value))
            assert decision(home, "arch", f"system_upgrade_cooldown_expired {NOW}"), value
        (state / LEGACY[2]).unlink()
        assert decision(home, "arch", f"system_upgrade_cooldown_expired {NOW}")
        for distro in ("arch", "ubuntu"):
            current = state / f".last_system_upgrade_{distro}"
            for value, expired in ((NOW - 86399, False), (NOW - 86400, True),
                                   (NOW + 1, True), ("invalid", True),
                                   ("0" + str(NOW - 60), False)):
                current.write_text(str(value))
                snapshot = {p.name: p.read_bytes() for p in state.iterdir()}
                assert decision(home, distro, f"system_upgrade_cooldown_expired {NOW}") == expired
                assert snapshot == {p.name: p.read_bytes() for p in state.iterdir()}, \
                    "Cooldown decisions must not write or migrate state"
        assert before[LEGACY[0]] == (state / LEGACY[0]).read_bytes()
        assert decision(home, "arch", "orphan_removal_allowed true true remove")
        for flags in ("false true remove", "true false remove", "true true yes",
                      "true true ''", "false false remove"):
            assert not decision(home, "ubuntu", f"orphan_removal_allowed {flags}"), flags
        for entrypoint in ("dfa-daily", "dfa-weekly", "update-system.sh", "dfa-remove-orphans",
                           "migrate.sh", "sync-skills.sh", "sync-rules.sh", "sync-extensions.sh",
                           "update-npm-clis.sh", "setup-harness-agents.sh"):
            assert decision(home, "ubuntu", f"require_workstation_entrypoint ubuntu {entrypoint}")
        for entrypoint in ("bootstrap.sh", "sync.sh", "setup-zed.sh", "update-ninjaone.sh"):
            assert not decision(home, "ubuntu", f"require_workstation_entrypoint ubuntu {entrypoint}")
        assert decision(home, "arch", "select_workstation_distro arch '' x86_64")
        assert decision(home, "ubuntu", "select_workstation_distro ubuntu 26.04 amd64")
        assert not decision(home, "ubuntu", "select_workstation_distro ubuntu 24.04 x86_64")
        assert not decision(home, "ubuntu", "select_workstation_distro ubuntu 26.04 aarch64")
        package_dir = home / "npm source/node_modules/agent"
        package_dir.mkdir(parents=True)
        (package_dir / "package.json").write_text('{"name":"agent"}')
        for launcher, owned in ((package_dir / "bin/agent", True),
                                (home / "vendor/agent", False),
                                (Path(str(package_dir) + "-other/bin/agent"), False)):
            command = f"npm_harness_owns_launcher {shlex.quote(str(package_dir))} {shlex.quote(str(launcher))}"
            assert decision(home, "ubuntu", command) == owned
        (package_dir / "package.json").unlink()
        command = f"npm_harness_owns_launcher {shlex.quote(str(package_dir))} {shlex.quote(str(package_dir / 'bin/agent'))}"
        assert not decision(home, "arch", command)
    print("Maintenance decisions passed (no update/cleanup workflows executed)")


if __name__ == "__main__":
    main()
