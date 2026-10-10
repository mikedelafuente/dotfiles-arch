"""Supplied GNOME facts only. No desktop, service, package, or network commands."""
import io
import json
import os
from pathlib import Path
import runpy
import subprocess
import tarfile
import tempfile
import zipfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    api = runpy.run_path(str(ROOT / "scripts/gnome_desktop.py"))
    compatible = api["extension_compatible"]
    assert compatible({"uuid": "pop-shell@system76.com", "shell-version": ["49", "50"]},
                      "pop-shell@system76.com", "50.1")
    assert not compatible({"uuid": "pop-shell@system76.com", "shell-version": ["49"]},
                          "pop-shell@system76.com", "50.1")
    assert not compatible({"uuid": "foreign", "shell-version": ["50"]},
                          "pop-shell@system76.com", "50.1")
    assert not compatible({"uuid": "x", "shell-version": "50"}, "x", "50.1")
    assert not compatible({"uuid": "x", "shell-version": ["50"]}, "x", "unknown")
    skips = api["accepted_extension_skips"]
    assert skips("50.1") == []
    assert skips("49") == []
    assert skips("51.0") == []
    assert skips("52.0") == ["pop-shell@system76.com"]
    assert skips("unknown") == []
    assert skips("50.1", "ubuntu") == api["UBUNTU_REPLACEMENTS"]
    assert skips("52.0", "ubuntu") == api["UBUNTU_REPLACEMENTS"]
    assert not compatible({"uuid": "x", "shell-version": ["50"]}, "x", "51")

    assert compatible({"uuid": "pop-shell@system76.com", "shell-version": ["50", "51"]},
                      "pop-shell@system76.com", "51.0")

    required = ["ubuntu-dock@ubuntu.com", "tiling-assistant@ubuntu.com", "ubuntu-appindicators@ubuntu.com"]
    enabled, disabled = api["extension_lists"](
        "['ubuntu-dock@ubuntu.com', 'tiling-assistant@ubuntu.com', 'ding@rastersoft.com', "
        "'snapd-prompting@canonical.com', 'user-extension', 'pop-shell@system76.com', "
        "'dash-to-panel@jderose9.github.com', 'no-overview@fthx', 'appindicatorsupport@rgcjonas.gmail.com']",
        "@as ['pop-shell@system76.com', 'ubuntu-dock@ubuntu.com', 'tiling-assistant@ubuntu.com', "
        "'user-disabled']", required, "ubuntu",
    )
    assert enabled == [*required[:2], "ding@rastersoft.com", "snapd-prompting@canonical.com",
                       "user-extension", required[2]]
    assert disabled == ["pop-shell@system76.com", "user-disabled", *api["UBUNTU_REPLACEMENTS"][1:]]
    assert api["extension_lists"]("[]", "['ding@rastersoft.com']", required, "ubuntu")[1][0] == "ding@rastersoft.com"
    assert api["extension_lists"](repr(enabled), repr(disabled), required, "ubuntu") == (enabled, disabled)
    assert api["extension_lists"]("['ubuntu-dock@ubuntu.com']", "[]", ["pop-shell@system76.com"], "arch")[0] == [
        "ubuntu-dock@ubuntu.com", "pop-shell@system76.com"]
    gap_lists = api["extension_lists"](
        "['pop-shell@system76.com', 'user-extension']", "['user-disabled']",
        ["pop-shell@system76.com", "dash-to-panel@jderose9.github.com"], "arch", "52.0")
    assert gap_lists == (["user-extension", "dash-to-panel@jderose9.github.com"],
                         ["user-disabled", "pop-shell@system76.com"])
    assert api["extension_lists"](*map(repr, gap_lists),
                                  ["dash-to-panel@jderose9.github.com"], "arch", "52.0") == gap_lists
    assert api["merge_shortcuts"]("['/user/shortcut/']", ["/dfa/shortcut/"]) == [
        "/user/shortcut/", "/dfa/shortcut/"]
    # Run the actual shortcut reconciliation with supplied settings only.
    setup = (ROOT / "scripts/setup-gnome.sh").read_text()
    tools = setup.split('# Install GNOME Tools', 1)[1].split('# Change how sound power works', 1)[0]
    panel = setup.split('if [[ "$WORKSTATION_DISTRO" == ubuntu ]]; then\n    # Reuse Ubuntu', 1)[1].split('# GPaste uses', 1)[0]
    panel = 'if [[ "$WORKSTATION_DISTRO" == ubuntu ]]; then\n    # Reuse Ubuntu' + panel
    for distro in ("arch", "ubuntu"):
        result = subprocess.run(["bash", "-eu", "-c", r'''
print_info_message() { :; }
ensure_native_pkgs() { printf '%s\n' "$@"; }
ensure_gnome_extensions() { :; }
gnome_extension_setting() { echo "$1:$3=$4"; }
''' + tools + panel], env=dict(os.environ, WORKSTATION_DISTRO=distro, GNOME_SHELL_VERSION="50.1"),
            capture_output=True, text=True)
        assert result.returncode == 0, result.stderr
        assert ("gnome-shell-extensions" in result.stdout.splitlines()) == (distro == "arch")
        assert ("dash-to-panel@" in result.stdout) == (distro == "arch")
        if distro == "ubuntu":
            assert "ubuntu-dock@ubuntu.com:hot-keys=false" in result.stdout
            assert "ubuntu-dock@ubuntu.com:disable-overview-on-startup=true" in result.stdout
    shortcut_block = setup.split("# Update the custom keybindings list", 1)[1].split("\n", 1)[1].split("# Screenshot UI", 1)[0]
    retired = "/org/gnome/settings-daemon/plugins/media-keys/custom-keybindings/custom5/"
    for command in ("/usr/bin/voxtype record toggle", "/user/custom-command", ""):
        supplied = r'''
gsettings() {
    case "$1:${3:-}" in
        get:custom-keybindings) echo "$SUPPLIED_SHORTCUTS" ;;
        get:command) echo "$SUPPLIED_COMMAND" ;;
        reset-recursively:*) echo reset ;;
        set:custom-keybindings) echo "$4" ;;
        *) return 97 ;;
    esac
}
'''
        result = subprocess.run(["bash", "-eu", "-c", supplied + shortcut_block],
            env=dict(os.environ, DF_SCRIPT_DIR=str(ROOT / "scripts"),
                     SUPPLIED_SHORTCUTS=repr(["/user/shortcut/", retired]), SUPPLIED_COMMAND=repr(command),
                     CUSTOM_KB_TERMINAL="/terminal/", CUSTOM_KB_EMOJI="/emoji/",
                     CUSTOM_KB_BROWSER="/browser/", CUSTOM_KB_CLIPBOARD="/clipboard/"),
            capture_output=True, text=True)
        assert result.returncode == 0, result.stderr
        lines = result.stdout.splitlines()
        owned = command == "/usr/bin/voxtype record toggle"
        assert ("reset" in lines) == owned
        paths = api["string_list"](lines[-1])
        assert (retired not in paths) == owned
        assert "/user/shortcut/" in paths and "/terminal/" in paths
    action = api["policy_action"]
    assert action("", False) == "apply"
    assert action("# Managed by dotfiles-arch (setup-gnome.sh)\n[Login]\n", False) == "apply"
    assert action("# IT policy\n[Login]\nHandleLidSwitch=ignore\n", False) == "defer"
    assert action("", True) == "defer"
    assert action("options snd_hda_intel power_save=0\n", False, "audio") == "apply"
    power = api["power_policy_action"]
    assert power(False, False, "not-found", "inactive") == "install"
    assert power(False, True, "loaded", "active") == "apply"
    assert power(False, True, "loaded", "inactive") == "defer"
    assert power(False, True, "masked", "inactive") == "defer"
    assert power(True, False, "not-found", "inactive") == "defer"
    assert power(False, True, "not-found", "inactive") == "unavailable"
    # Stage only supplied archive data; links/traversal cannot escape temporary state.
    with tempfile.TemporaryDirectory(prefix="gnome-decisions-") as temp:
        guard = Path(temp) / "bin"
        guard.mkdir()
        for command in ("sudo", "pacman", "yay", "apt-get", "apt-cache", "dpkg-query",
                        "curl", "gsettings", "gnome-shell", "gnome-extensions", "tsc",
                        "systemctl", "powerprofilesctl", "udevadm", "wpctl"):
            stub = guard / command
            stub.write_text('#!/bin/sh\necho "Forbidden command" >&2\nexit 97\n')
            stub.chmod(0o755)
        env = dict(os.environ, PATH=str(guard) + os.pathsep + os.environ["PATH"])
        for distro, app, recipe in (
            ("ubuntu", "tray", "ubuntu-appindicators@ubuntu.com gnome-shell-ubuntu-extensions native"),
            ("ubuntu", "clipboard", "GPaste@gnome-shell-extensions.gnome.org gnome-shell-extension-gpaste native"),
            ("ubuntu", "dock", "ubuntu-dock@ubuntu.com gnome-shell-ubuntu-extensions native"),
            ("ubuntu", "tiling", "tiling-assistant@ubuntu.com gnome-shell-ubuntu-extensions native"),
            ("arch", "pop", "pop-shell@system76.com gnome-shell-extension-pop-shell-git aur"),
        ):
            result = subprocess.run(["bash", "-eu", "-o", "pipefail", "-c",
                'source "$1"; gnome_extension_recipe "$2" "$3"', "decide",
                str(ROOT / "scripts/gnome-lib.sh"), distro, app],
                env=env, capture_output=True, text=True)
            assert result.returncode == 0 and result.stdout.strip() == recipe, result.stderr
            assert "Forbidden command" not in result.stdout + result.stderr
        for distro in ("arch",):
            result = subprocess.run(["bash", "-eu", "-c",
                'source "$1"; gnome_extension_recipe "$2" pop 51.0', "decide",
                str(ROOT / "scripts/gnome-lib.sh"), distro], env=env, capture_output=True, text=True)
            assert result.returncode == 0, result.stderr
            assert result.stdout.strip() == "pop-shell@system76.com pop-31f04c3 pinned"
        for app in ("pop", "overview", "panel"):
            result = subprocess.run(["bash", "-eu", "-c",
                'source "$1"; gnome_extension_recipe ubuntu "$2" 51.0', "decide",
                str(ROOT / "scripts/gnome-lib.sh"), app], env=env, capture_output=True, text=True)
            assert result.returncode == 1, result.stderr
        # Run the real Ubuntu acquisition/list flow with supplied native metadata.
        extensions = Path(temp) / "extensions"
        for uuid in (*required, "GPaste@gnome-shell-extensions.gnome.org"):
            path = extensions / uuid
            path.mkdir(parents=True)
            (path / "metadata.json").write_text(json.dumps({"uuid": uuid, "shell-version": ["50"]}))
        result = subprocess.run(["bash", "-eu", "-o", "pipefail", "-c", r'''
source "$DF_SCRIPT_DIR/gnome-lib.sh"
print_info_message() { :; }
print_error_message() { echo "$*" >&2; }
native_package_installed() { return 0; }
core_cli_source_allowed() { return 0; }
readlink() { echo /usr/bin/gpaste-client; }
ensure_native_pkgs() {
    for package in "$@"; do
        case "$package" in
            gnome-shell-ubuntu-extensions|gnome-shell-extension-gpaste|gpaste-2|gir1.2-gpaste-2) ;;
            *) echo "Unexpected package: $package" >&2; return 97 ;;
        esac
    done
}
gnome_extension_path() { echo "$USER_HOME_DIR/extensions/$1"; }
dpkg-query() {
    local package=gnome-shell-ubuntu-extensions
    [[ "$2" != *GPaste@* ]] || package=gnome-shell-extension-gpaste
    echo "$package: $2"
}
gsettings() {
    case "$1:$3" in
        get:enabled-extensions) echo "['ubuntu-dock@ubuntu.com', 'pop-shell@system76.com', 'user-extension']" ;;
        get:disabled-extensions) echo "['tiling-assistant@ubuntu.com']" ;;
        set:enabled-extensions|set:disabled-extensions) echo "$3=$4" ;;
        set:disable-extension-version-validation|set:disable-user-extensions) ;;
        *) return 97 ;;
    esac
}
gnome-extensions() { echo "disable=$2"; }
ensure_gnome_extensions 50.1
[[ "$GNOME_POP_SHELL_AVAILABLE" == false ]]
'''], env=dict(env, USER_HOME_DIR=temp, WORKSTATION_DISTRO="ubuntu", DF_SCRIPT_DIR=str(ROOT / "scripts")),
            capture_output=True, text=True)
        assert result.returncode == 0, result.stdout + result.stderr
        assert "Forbidden command" not in result.stdout + result.stderr
        assert "disable=ubuntu-dock@ubuntu.com" not in result.stdout
        assert "disable=tiling-assistant@ubuntu.com" not in result.stdout
        assert "disable=ding@rastersoft.com" not in result.stdout
        assert "disable=pop-shell@system76.com" in result.stdout
        assert "disable=dash-to-panel@jderose9.github.com" in result.stdout
        output_lists = dict(line.split("=", 1) for line in result.stdout.splitlines() if "-extensions=" in line)
        assert all(uuid in api["string_list"](output_lists["enabled-extensions"]) for uuid in required)
        assert "user-extension" in api["string_list"](output_lists["enabled-extensions"])
        archive = Path(temp) / "extension.zip"
        metadata = {"uuid": "x", "shell-version": ["50"]}
        with zipfile.ZipFile(archive, "w") as supplied:
            supplied.writestr("metadata.json", json.dumps(metadata))
            supplied.writestr("extension.js", "// supplied data")
        api["stage_extension"]("zip", archive, Path(temp) / "good")
        assert json.loads((Path(temp) / "good/metadata.json").read_text()) == metadata
        for name in ("../escape.js", "/absolute.js"):
            with zipfile.ZipFile(archive, "w") as supplied:
                supplied.writestr(name, "// unsafe")
            try:
                api["stage_extension"]("zip", archive, Path(temp) / "bad")
            except ValueError:
                pass
            else:
                raise AssertionError("Unsafe extension path accepted")
        archive = Path(temp) / "extension.tar"
        with tarfile.open(archive, "w") as supplied:
            member = tarfile.TarInfo("extension-pin/metadata.json")
            data = json.dumps(metadata).encode()
            member.size = len(data)
            supplied.addfile(member, io.BytesIO(data))
        api["stage_extension"]("tar", archive, Path(temp) / "tar-good")
        assert (Path(temp) / "tar-good/metadata.json").is_file()
        with tarfile.open(archive, "w") as supplied:
            member = tarfile.TarInfo("extension-pin/link")
            member.type = tarfile.SYMTYPE
            member.linkname = "/outside"
            supplied.addfile(member)
        try:
            api["stage_extension"]("tar", archive, Path(temp) / "tar-bad")
        except ValueError:
            pass
        else:
            raise AssertionError("Extension archive link accepted")


if __name__ == "__main__":
    main()
