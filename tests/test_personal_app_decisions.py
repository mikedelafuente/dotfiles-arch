"""Supplied personal-app facts only; deliberately left unrun by user request."""
from pathlib import Path
import os
import shlex
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    with tempfile.TemporaryDirectory(prefix="personal-decisions-") as temp:
        guard = Path(temp) / "bin"
        guard.mkdir()
        for name in ("sudo", "pacman", "yay", "apt-get", "apt-cache", "dpkg", "dpkg-query",
                     "apt-mark", "snap", "flatpak", "curl", "gpg", "systemctl", "gsettings",
                     "steam", "discord", "firefox", "mullvad", "add-apt-repository"):
            target = guard / name
            target.write_text('#!/bin/sh\necho "Forbidden command" >&2\nexit 97\n')
            target.chmod(0o755)
        env = dict(os.environ, DF_SCRIPT_DIR=str(ROOT / "scripts"), USER_HOME_DIR=temp,
                   PATH=str(guard) + os.pathsep + os.environ["PATH"])

        def decide(*args, expected="", ok=True):
            result = subprocess.run(["bash", "-eu", "-o", "pipefail", "-c",
                'source "$DF_SCRIPT_DIR/fn-lib.sh"; ' + shlex.join(args)],
                env=env, capture_output=True, text=True)
            assert "Forbidden command" not in result.stdout + result.stderr
            assert result.returncode == (0 if ok else 1), result.stdout + result.stderr
            if ok:
                assert result.stdout.strip() == expected, result.stdout

        for app, arch, ubuntu in (("steam", "steam native", "steam-installer native"),
                                  ("discord", "discord native", "discord self-deb"),
                                  ("firefox", "firefox native", "firefox self"),
                                  ("mullvad", "mullvad-vpn-bin aur", "mullvad-vpn apt")):
            for distro, recipe in (("arch", arch), ("ubuntu", ubuntu)):
                decide("personal_app_selection", distro, app, "none", "", "false", "", expected=recipe)
            for source, launcher, alternate in (("unknown", "owned", "false"),
                                                 ("none", "unknown", "false"),
                                                 ("none", "", "true")):
                decide("personal_app_selection", "ubuntu", app, source, launcher, alternate, "", ok=False)
            decide("require_workstation_entrypoint", "ubuntu", f"setup-{app}.sh")
        decide("personal_app_selection", "ubuntu", "discord", "self-deb", "owned", "false", "1.0.161", expected="discord self-deb")
        decide("personal_app_selection", "ubuntu", "discord", "self-deb", "owned", "false", "0.0.90", ok=False)
        decide("personal_app_selection", "ubuntu", "discord", "snap", "owned", "false", "1.0.161", expected="discord snap")
        decide("personal_app_selection", "ubuntu", "firefox", "apt", "owned", "false", "157.0.1", expected="firefox apt")
        decide("personal_app_selection", "ubuntu", "firefox", "snap", "owned", "false", "157.0.1", expected="firefox snap")
        decide("personal_app_selection", "ubuntu", "firefox", "self", "owned", "false", "157.0.1", expected="firefox self")
        for channel in ("latest/stable", "latest/stable/ubuntu-26.04"):
            decide("personal_snap_stable_channel", channel)
        for channel in ("latest/beta", "latest/stable/…", "latest/stable/"):
            decide("personal_snap_stable_channel", channel, ok=False)
        digest = "a" * 64
        sums = digest + "  linux-x86_64/en-US/firefox-157.0.1.tar.xz"
        decide("firefox_release_asset", "157.0.1", sums, expected="https://archive.mozilla.org/pub/firefox/releases/157.0.1/linux-x86_64/en-US/firefox-157.0.1.tar.xz " + digest)
        decide("firefox_release_asset", "157.0.1", sums + "\n" + sums, ok=False)
        decide("firefox_release_asset", "157.0.1-beta", sums, ok=False)
        decide("firefox_apparmor_profile", "/home/test*/firefox", "dfa-firefox-123456789abcdef0", ok=False)
        decide("personal_browser_selection", "work personal", "google-chrome-stable", "firefox_firefox.desktop", expected="google-chrome.desktop google-chrome-stable")
        decide("personal_browser_selection", "personal", "google-chrome", "firefox_firefox.desktop", expected="firefox_firefox.desktop firefox")
        decide("personal_browser_selection", "personal", "google-chrome", "firefox.desktop", expected="firefox.desktop firefox")
        decide("personal_browser_selection", "work personal", "", "firefox.desktop", ok=False)
        for app, url, suite in (("mullvad", "https://repository.mullvad.net/deb/stable", "stable"),
                                ("firefox", "https://packages.mozilla.org/apt", "mozilla")):
            source = f"deb [arch=amd64 signed-by=/usr/share/keyrings/{app}.gpg] {url} {suite} main"
            decide("work_app_apt_key", app, source, expected=f"/usr/share/keyrings/{app}.gpg")
            for bad in ("# " + source, source.replace("https:", "http:"), source + "\n" + source):
                decide("work_app_apt_key", app, bad, ok=False)
        policy = "  Candidate: 1:1.0.0.85~ds-2build1\n  Version table:\n     1:1.0.0.85~ds-2build1 500\n        500 https://mirror.example/ubuntu resolute/multiverse amd64 Packages"
        indexes = " 500 https://mirror.example/ubuntu resolute/multiverse amd64 Packages\n     release v=26.04,o=Ubuntu,a=resolute,n=resolute,l=Ubuntu,c=multiverse,b=amd64\n"
        # Pure metadata parser; guarded package managers cannot be called.
        decide("python3", str(ROOT / "scripts/work_app_metadata.py"), "steam-candidate", "steam-installer", policy, indexes, expected="1:1.0.0.85~ds-2build1")
        decide("python3", str(ROOT / "scripts/work_app_metadata.py"), "steam-candidate", "steam-installer", policy, indexes.replace("o=Ubuntu", "o=Other"), ok=False)
        i386_policy = "  Candidate: 1:1.0.0.85~ds-2build1\n  Version table:\n     1:1.0.0.85~ds-2build1 500\n        500 https://mirror.example/ubuntu resolute/universe i386 Packages"
        i386_indexes = " 500 https://mirror.example/ubuntu resolute/universe i386 Packages\n     release v=26.04,o=Ubuntu,a=resolute,n=resolute,l=Ubuntu,c=universe,b=i386\n"
        decide("python3", str(ROOT / "scripts/work_app_metadata.py"), "steam-candidate", "steam-libs-i386:i386", i386_policy, i386_indexes, expected="1:1.0.0.85~ds-2build1")
        decide("python3", str(ROOT / "scripts/work_app_metadata.py"), "steam-candidate", "steam-libs-i386:i386", i386_policy, i386_indexes.replace("i386", "amd64"), ok=False)
    print("Personal app supplied-fact checks passed")


if __name__ == "__main__":
    main()
