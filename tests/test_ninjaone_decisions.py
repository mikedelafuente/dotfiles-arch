"""Pure supplied NinjaOne facts only; intentionally left unrun during implementation."""
from pathlib import Path
import hashlib
import os
import shlex
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    with tempfile.TemporaryDirectory(prefix="ninjaone-decisions-") as temp:
        guard = Path(temp) / "bin"
        guard.mkdir()
        for name in ("sudo", "pacman", "yay", "apt-get", "dpkg", "dpkg-deb",
                     "dpkg-query", "curl", "wget", "systemctl", "makepkg", "bsdtar"):
            command = guard / name
            command.write_text('#!/bin/sh\necho "Forbidden agent command" >&2\nexit 97\n')
            command.chmod(0o755)
        env = dict(os.environ, DF_SCRIPT_DIR=str(ROOT / "scripts"), USER_HOME_DIR=temp,
                   PATH=str(guard) + os.pathsep + os.environ["PATH"])

        def decide(*args, expected=None, ok=True):
            result = subprocess.run(
                ["bash", "-eu", "-o", "pipefail", "-c",
                 'source "$DF_SCRIPT_DIR/fn-lib.sh"; source "$DF_SCRIPT_DIR/ninjaone-lib.sh"; '
                 'NINJAONE_OWNER_FILE="$USER_HOME_DIR/owner"; ' + shlex.join(args)],
                env=env, capture_output=True, text=True,
            )
            assert "Forbidden agent command" not in result.stdout + result.stderr
            assert result.returncode == (0 if ok else 1), result.stdout + result.stderr
            if expected is not None:
                assert result.stdout.strip() == expected, result.stdout

        url = "https://eu.ninjarmm.com/agent/installer/example_uid/6.2.3/agent.deb"
        decide("ninjaone_url_valid", url)
        decide("ninjaone_url_valid", url.replace("ninjarmm", "rmmservice"))
        for unsafe in (url.replace("https:", "http:"),
                       url.replace("eu.ninjarmm.com", "eu.ninjarmm.com.evil.com"),
                       url.replace("eu.ninjarmm.com", "user@eu.ninjarmm.com"),
                       url.replace("eu.ninjarmm.com", "-eu.ninjarmm.com"),
                       url + "?token=secret", url + "#secret", url + '\n',
                       url.replace("example_uid", 'example\"uid'),
                       url.replace("example_uid", 'example\\uid')):
            decide("ninjaone_url_valid", unsafe, ok=False)
        decide("ninjaone_url_host", url, expected="eu.ninjarmm.com")
        decide("ninjaone_url_version", url, expected="6.2.3")
        digest = hashlib.sha256(b"https://eu.ninjarmm.com/agent/installer/example_uid").hexdigest()
        decide("ninjaone_enrollment_id", url, expected=digest)
        (Path(temp) / "owner").write_text("ninjarmm-agent " + digest + "\n")
        decide("ninjaone_enrollment_matches", url.replace("6.2.3", "6.2.4"))
        decide("ninjaone_enrollment_matches", url.replace("example_uid", "another_uid"), ok=False)
        decide("ninjaone_enrollment_matches", url.replace("eu.", "us."), ok=False)
        decide("ninjaone_version_gt", "6.10.0", "6.9.99")
        for target, current in (("6.9.99", "6.10.0"), ("6.2.3", "6.2.3"),
                                ("6.02.3", "6.2.3"), ("6.2.3", ""), ("invalid", "6.2.3")):
            decide("ninjaone_version_gt", target, current, ok=False)
        for facts, outcome in ((("arch", "ninjaone-agent", "", "true"), "owned"),
                               (("arch", "", "", "true"), "managed"),
                               (("ubuntu", "ninjarmm-agent", "ninjarmm-agent", "true"), "owned"),
                               (("ubuntu", "ninjarmm-agent", "", "true"), "managed"),
                               (("ubuntu", "ninjarmm-agent", "ninjarmm-agent-other", "true"), "managed"),
                               (("ubuntu", "", "", "true"), "managed"),
                               (("ubuntu", "", "", "false"), "absent")):
            decide("ninjaone_ownership", *facts, expected=outcome)
        decide("ninjaone_ownership", "fedora", "", "", "false", ok=False)
        for package in ("ninjarmm-agent", "ninjaone-agent", "ninjarmm-agent-org-site"):
            decide("ninjaone_native_package_valid", package)
        for package in ("other-agent", "ninjarmm-agent evil", "ninjarmm-agent;echo secret"):
            decide("ninjaone_native_package_valid", package, ok=False)
        for path in ("./", "./opt/NinjaRMMAgent/programfiles/ninjarmm-linagent",
                     "./tmp/ninja-uninstall/ninja-deb-uninstall.sh"):
            decide("ninjaone_archive_path_valid", path)
        for path in ("/opt/NinjaRMMAgent/file", "./etc/passwd", "./opt/NinjaRMMAgent/../../etc/passwd",
                     "./tmp/unrelated/file", "./opt/NinjaRMMAgent/file\n./etc/passwd"):
            decide("ninjaone_archive_path_valid", path, ok=False)
    print("NinjaOne decisions passed; no installation, uninstall, service or network workflow executed")


if __name__ == "__main__":
    main()
