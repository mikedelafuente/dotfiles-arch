"""Offline supplied-fact utility decisions. Left unrun under the user's constraint."""
from pathlib import Path
import os
import shlex
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    with tempfile.TemporaryDirectory(prefix="utility-decisions-") as temp:
        guard = Path(temp) / "bin"
        guard.mkdir()
        for name in ("sudo", "pacman", "yay", "apt-get", "apt-cache", "dpkg-query",
                     "dpkg-deb", "apt-mark", "snap", "flatpak", "curl", "wget", "gpg",
                     "systemctl", "udevadm", "groupadd", "usermod", "gsettings",
                     "tableplus", "postman", "spotify", "obsidian", "keymapp"):
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

        for app, arch, ubuntu in (("tableplus", "tableplus aur", "tableplus apt"),
                                  ("postman", "postman-bin aur", "postman snap"),
                                  ("spotify", "spotify aur", "spotify-client apt"),
                                  ("obsidian", "obsidian native", "obsidian release-deb"),
                                  ("keymapp", "zsa-keymapp-bin aur", "keymapp pinned-archive")):
            for distro, recipe in (("arch", arch), ("ubuntu", ubuntu)):
                decide("desktop_utility_selection", distro, app, "none", "", "false", "",
                       expected=recipe)
            decide("desktop_utility_selection", "ubuntu", app, "unknown", "owned", "false", "1.3.7", ok=False)
            decide("desktop_utility_selection", "ubuntu", app, "none", "unknown", "false", "", ok=False)
            decide("desktop_utility_selection", "ubuntu", app, "none", "", "true", "", ok=False)
        decide("desktop_utility_selection", "ubuntu", "spotify", "snap", "owned", "false", "1.2.95",
               expected="spotify snap")
        decide("desktop_utility_vendor_desktop", "spotify", expected="/usr/share/spotify/spotify.desktop")
        decide("desktop_utility_vendor_desktop", "tableplus", expected="/opt/tableplus/tableplus.desktop")
        decide("desktop_utility_vendor_desktop", "unknown", ok=False)
        decide("desktop_utility_selection", "ubuntu", "postman", "self", "owned", "false", "11.71.7",
               expected="postman self")
        decide("desktop_utility_selection", "ubuntu", "postman", "self", "owned", "false", "8.0.0", ok=False)
        decide("desktop_utility_selection", "arch", "obsidian", "aur", "owned", "false", "1.14.4",
               expected="obsidian-bin aur")
        decide("desktop_utility_selection", "ubuntu", "obsidian", "release-deb", "owned", "false", "1.14.4",
               expected="obsidian release-deb")
        decide("desktop_utility_selection", "ubuntu", "keymapp", "pinned-archive", "owned", "false", "1.3.7",
               expected="keymapp pinned-archive")
        for app in ("tableplus", "spotify"):
            component = "non-free" if app == "spotify" else "main"
            url, suite = (("https://deb.tableplus.com/debian/26", "tableplus") if app == "tableplus"
                          else ("https://repository.spotify.com", "stable"))
            source = f"deb [arch=amd64 signed-by=/usr/share/keyrings/{app}.gpg] {url} {suite} {component}"
            decide("work_app_apt_key", app, source, expected=f"/usr/share/keyrings/{app}.gpg")
            for bad in (source.replace("https:", "http:"), "# " + source, source + "\n" + source,
                        source.replace(f" signed-by=/usr/share/keyrings/{app}.gpg", "")):
                decide("work_app_apt_key", app, bad, ok=False)
            version = "1:1.2.95.453.g0eeebbed" if app == "spotify" else "1.7.0"
            candidate = f"  Candidate: {version}\n  Version table:\n     {version} 500\n        500 {url} {suite}/{component} amd64 Packages"
            decide("work_app_apt_candidate", app, candidate, expected=version)
            decide("work_app_apt_candidate", app, candidate.replace(url, "https://example.org"), ok=False)
        digest = "a" * 64
        metadata = '{"draft":false,"prerelease":false,"tag_name":"v1.14.4","assets":[{"name":"obsidian_1.14.4_amd64.deb","browser_download_url":"https://github.com/obsidianmd/obsidian-releases/releases/download/v1.14.4/obsidian_1.14.4_amd64.deb","digest":"sha256:' + digest + '"}]}'
        decide("desktop_utility_obsidian_asset", metadata,
               expected=f"1.14.4 https://github.com/obsidianmd/obsidian-releases/releases/download/v1.14.4/obsidian_1.14.4_amd64.deb {digest}")
        for bad in (metadata.replace("sha256:", "md5:"), metadata.replace("amd64", "arm64"),
                    metadata.replace('"prerelease":false', '"prerelease":true')):
            decide("desktop_utility_obsidian_asset", bad, ok=False)
        for app in ("tableplus", "postman", "spotify", "obsidian", "moonlander"):
            decide("require_workstation_entrypoint", "ubuntu", f"setup-{app}.sh")
    print("Desktop utility decisions passed (offline)")


if __name__ == "__main__":
    main()
