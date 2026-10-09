"""Offline work-app decisions with supplied facts; no setup/update entrypoints."""
from pathlib import Path
import os
import sys
import shlex
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    with tempfile.TemporaryDirectory(prefix="work-app-decisions-") as temp:
        guard = Path(temp) / "bin"
        guard.mkdir()
        for name in ("sudo", "pacman", "yay", "apt", "apt-get", "apt-cache", "dpkg",
                     "dpkg-query", "dpkg-deb", "apt-mark", "ar", "curl", "wget", "snap", "flatpak",
                     "gpg", "systemctl", "gsettings", "xdg-settings", "zoom", "slack",
                     "google-chrome", "google-chrome-stable"):
            script = guard / name
            script.write_text('#!/bin/sh\necho "Forbidden command" >&2\nexit 97\n')
            script.chmod(0o755)
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

        decide("work_app_selection", "ubuntu", "chrome", "false", "", "false", "none",
               expected="google-chrome-stable apt")
        for distro in ("arch", "ubuntu"):
            for app, package, owner in (("chrome", "google-chrome-stable" if distro == "ubuntu" else "google-chrome", "apt" if distro == "ubuntu" else "aur"),
                                        ("slack", "slack-desktop", "apt" if distro == "ubuntu" else "aur"),
                                        ("zoom", "zoom", "vendor-deb" if distro == "ubuntu" else "aur")):
                source = "apt" if owner == "apt" else "none"
                decide("work_app_selection", distro, app, "true", "owned", "false", source,
                       expected=f"{package} {owner}")
                for installed, launcher, alternate, state in (("false", "owned", "false", source),
                        ("true", "/snap/bin/slack", "false", source),
                        ("true", "", "false", source),
                        ("true", "owned", "true", source), ("true", "owned", "false", "conflict")):
                    decide("work_app_selection", distro, app, installed, launcher, alternate, state, ok=False)
        for app in ("chrome", "slack"):
            decide("work_app_selection", "ubuntu", app, "true", "owned", "false", "none", ok=False)
        decide("work_app_selection", "ubuntu", "zoom", "true", "owned", "false", "apt", ok=False)
        decide("work_app_selection", "fedora", "chrome", "false", "", "false", "none", ok=False)
        # APT parsing retains a scoped vendor source; duplicate/disabled/unscoped sources fail.
        source = "deb [arch=amd64 signed-by=/etc/apt/keyrings/slack.gpg] https://packagecloud.io/slacktechnologies/slack/debian/ jessie main"
        decide("work_app_apt_key", "slack", source, expected="/etc/apt/keyrings/slack.gpg")
        chrome = """X-Repolib-Name: Google Chrome
Types: deb
URIs: https://dl.google.com/linux/chrome-stable/deb/
Suites: stable
Components: main
Architectures: amd64
Signed-By: /usr/share/keyrings/google-chrome.gpg"""
        decide("work_app_apt_key", "chrome", chrome, expected="/usr/share/keyrings/google-chrome.gpg")
        for bad in (source.replace(" signed-by=/etc/apt/keyrings/slack.gpg", ""),
                    "# " + source, source + "\n" + source,
                    source.replace("jessie", "resolute"), source.replace("https:", "http:"),
                    source.replace("arch=amd64", "arch=arm64"),
                    source.replace("/etc/apt/keyrings/slack.gpg", "/etc/apt/trusted.gpg")):
            decide("work_app_apt_key", "slack", bad, ok=False)
        apt = Path(temp) / "apt"
        parts = apt / "sources.list.d"
        parts.mkdir(parents=True)
        decide("work_app_apt_source", "chrome", str(apt))
        (parts / "google-chrome.sources").write_text(chrome)
        decide("work_app_apt_source", "chrome", str(apt),
               expected=f"{parts}/google-chrome.sources /usr/share/keyrings/google-chrome.gpg")
        (parts / "extra.list").write_text("deb [signed-by=/etc/apt/keyrings/google.asc] https://dl.google.com/linux/chrome/deb stable main")
        decide("work_app_apt_source", "chrome", str(apt), ok=False)
        (parts / "extra.list").unlink()
        (parts / "zoom.list").write_text("deb https://unofficial.zoom.us/apt stable main")
        decide("work_app_apt_source", "zoom", str(apt), ok=False)
        candidate = "slack-desktop:\n  Installed: (none)\n  Candidate: 4.52.178\n  Version table:\n     4.52.178 500\n        500 https://packagecloud.io/slacktechnologies/slack/debian jessie/main amd64 Packages"
        decide("work_app_apt_candidate", "slack", candidate, expected="4.52.178")
        for bad in (candidate.replace("4.52.178", "4.30.0"),
                    candidate.replace("https://packagecloud.io/slacktechnologies/slack/debian", "https://example.org/apt"),
                    candidate.replace("Candidate: 4.52.178", "Candidate: (none)")):
            decide("work_app_apt_candidate", "slack", bad, ok=False)
        decide("work_app_package_version", "slack", "4.52.178", expected="4.52.178")
        for app, version in (("slack", "4.30.0"), ("slack", "4.52.178~rc1"), ("zoom", "6.7.4.1"), ("zoom", "garbage")):
            decide("work_app_package_version", app, version, ok=False)
        decide("work_app_package_version", "zoom", "6.7.11.4156", expected="6.7.11.4156")
        decide("work_app_apt_key", "slack", "deb http://archive.ubuntu.com/ubuntu resolute main\n" + source,
               expected="/etc/apt/keyrings/slack.gpg")
        decide("work_app_apt_key", "chrome", "Types: deb\nURIs: http://archive.ubuntu.com/ubuntu\nSuites: resolute\nComponents: main\n\n" + chrome,
               expected="/usr/share/keyrings/google-chrome.gpg")
        # Validate supplied authenticated Zoom manifest against temporary inert ar bytes.
        sys.path.insert(0, str(ROOT / "scripts"))
        sys.dont_write_bytecode = True
        from work_app_metadata import zoom_manifest
        members = [("debian-binary", b"2.0\n"), ("control.tar.gz", b"control"),
                   ("data.tar.xz", b"data"), ("_gpgbuilder", b"supplied signature fact")]
        import hashlib
        package = Path(temp) / "zoom.deb"
        def archive(items):
            data = b"!<arch>\n"
            for name, content in items:
                header = f"{name + '/':<16}{0:<12}{0:<6}{0:<6}{'100644':<8}{len(content):<10}`\n"
                data += header.encode() + content + (b"\n" if len(content) % 2 else b"")
            return data
        package.write_bytes(archive(members))
        manifest = "Version: 4\nRole: builder\nFiles:\n" + "\n".join(
            f" {hashlib.md5(data).hexdigest()} {hashlib.sha1(data).hexdigest()} {len(data)} {name}"
            for name, data in members[:-1])
        zoom_manifest(package, manifest)
        for bad in (manifest.replace("Role: builder", "Role: unknown"),
                    manifest.replace("Version: 4", "Version: 3"),
                    manifest.rsplit("\n", 1)[0], manifest + "\n" + manifest.splitlines()[-1]):
            try:
                zoom_manifest(package, bad)
            except ValueError:
                pass
            else:
                raise AssertionError("invalid Zoom manifest accepted")
        for items in (members + [("extra", b"unsigned")], members + [members[0]],
                      [("debian-binary", b"BAD!"), *members[1:]], members[:-1]):
            package.write_bytes(archive(items))
            try:
                zoom_manifest(package, manifest)
            except ValueError:
                pass
            else:
                raise AssertionError("unsigned/modified Zoom contents accepted")
        # The shared profile decision remains additive and the Ubuntu guard enables only these app paths.
        for profiles, selected in (("work", True), ("work personal devcontainer", True), ("personal", False)):
            result = subprocess.run(["bash", "-eu", "-c",
                'source "$DF_SCRIPT_DIR/fn-lib.sh"; SETUP_PROFILES="$1"; has_setup_profile work', "check", profiles],
                env=env, capture_output=True, text=True)
            assert result.returncode == (0 if selected else 1)
        for app in ("chrome", "slack", "zoom"):
            decide("require_workstation_entrypoint", "ubuntu", f"setup-{app}.sh")
    print("Work app decisions passed (offline; no setup/update/desktop execution)")


if __name__ == "__main__":
    main()
