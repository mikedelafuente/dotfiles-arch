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
    assert skips("51.0") == ["pop-shell@system76.com"]
    assert skips("unknown") == []
    assert not compatible({"uuid": "x", "shell-version": ["50"]}, "x", "51")

    required = ["pop-shell@system76.com", "ubuntu-appindicators@ubuntu.com"]
    enabled, disabled = api["extension_lists"](
        "['ubuntu-dock@ubuntu.com', 'tiling-assistant@ubuntu.com', 'ding@rastersoft.com', "
        "'snapd-prompting@canonical.com', 'user-extension', 'appindicatorsupport@rgcjonas.gmail.com']",
        "@as ['pop-shell@system76.com', 'user-disabled']", required, "ubuntu",
    )
    assert enabled == ["snapd-prompting@canonical.com", "user-extension", *required]
    assert disabled == ["user-disabled", "ubuntu-dock@ubuntu.com", "tiling-assistant@ubuntu.com",
                        "ding@rastersoft.com", "appindicatorsupport@rgcjonas.gmail.com"]
    assert api["extension_lists"](repr(enabled), repr(disabled), required, "ubuntu") == (enabled, disabled)
    assert api["extension_lists"]("['ubuntu-dock@ubuntu.com']", "[]", ["pop-shell@system76.com"], "arch")[0] == [
        "ubuntu-dock@ubuntu.com", "pop-shell@system76.com"]
    gap_lists = api["extension_lists"](
        "['pop-shell@system76.com', 'user-extension']", "['user-disabled']",
        ["pop-shell@system76.com", "dash-to-panel@jderose9.github.com"], "arch", "51.0")
    assert gap_lists == (["user-extension", "dash-to-panel@jderose9.github.com"],
                         ["user-disabled", "pop-shell@system76.com"])
    assert api["extension_lists"](*map(repr, gap_lists),
                                  ["dash-to-panel@jderose9.github.com"], "arch", "51.0") == gap_lists
    assert api["merge_shortcuts"]("['/user/shortcut/']", ["/dfa/shortcut/"]) == [
        "/user/shortcut/", "/dfa/shortcut/"]
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
            ("ubuntu", "pop", "pop-shell@system76.com pop-7898b65 pinned"),
            ("arch", "pop", "pop-shell@system76.com gnome-shell-extension-pop-shell-git aur"),
        ):
            result = subprocess.run(["bash", "-eu", "-o", "pipefail", "-c",
                'source "$1"; gnome_extension_recipe "$2" "$3"', "decide",
                str(ROOT / "scripts/gnome-lib.sh"), distro, app],
                env=env, capture_output=True, text=True)
            assert result.returncode == 0 and result.stdout.strip() == recipe, result.stderr
            assert "Forbidden command" not in result.stdout + result.stderr
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
