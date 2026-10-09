"""Supplied appearance facts only. Never run setup or gather host font state."""
import os
import io
import runpy
import tarfile
import zipfile
from pathlib import Path
import shlex
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    with tempfile.TemporaryDirectory() as temp:
        guard = Path(temp) / "bin"
        guard.mkdir()
        for name in ("sudo", "pacman", "yay", "apt-get", "dpkg-query", "curl",
                     "fc-list", "fc-cache", "gsettings", "systemctl", "bat", "batcat"):
            script = guard / name
            script.write_text('#!/bin/sh\necho "Forbidden command" >&2\nexit 97\n')
            script.chmod(0o755)
        env = dict(os.environ, PATH=str(guard) + os.pathsep + os.environ["PATH"])

        def decide(*args, expected="", ok=True):
            result = subprocess.run(["bash", "-eu", "-o", "pipefail", "-c",
                f'source {shlex.quote(str(ROOT / "scripts/appearance-lib.sh"))}; '
                + shlex.join(args)], env=env, capture_output=True, text=True)
            assert "Forbidden command" not in result.stdout + result.stderr
            assert result.returncode == (0 if ok else 1), result.stderr
            assert result.stdout.strip() == expected, result.stdout

        decide("appearance_font_packages", "ubuntu", expected="fonts-adwaita-sans fonts-noto-core fonts-noto-mono fonts-noto-color-emoji fonts-liberation fontconfig")
        decide("appearance_font_packages", "arch", expected="adwaita-fonts noto-fonts noto-fonts-emoji ttf-liberation fontconfig ttf-meslo-nerd ttf-ubuntu-nerd ttf-firacode-nerd ttf-jetbrains-mono-nerd ttf-hack-nerd")
        decide("appearance_font_packages", "fedora", ok=False)
        # Exact family match; aliases supplied by fc-list may share a comma-separated line.
        families = "Adwaita Sans\nAdwaita Mono\nNoto Sans\nNoto Serif\nNoto Sans Mono\nNoto Color Emoji\nLiberation Sans\nLiberation Serif\nLiberation Mono\nJetBrainsMono Nerd Font,JetBrainsMono NF\nMesloLGS Nerd Font\nUbuntu Nerd Font\nFiraCode Nerd Font\nHack Nerd Font"
        decide("appearance_missing_families", families)
        decide("appearance_missing_families", families.replace("JetBrainsMono Nerd Font,", ""), expected="JetBrainsMono Nerd Font", ok=False)
        decide("appearance_missing_families", families.replace("Adwaita Mono", "Adwaita Mono Nerd Font"), expected="Adwaita Mono", ok=False)
        root = Path(temp) / "managed"
        root.mkdir()
        target = Path(temp) / "theme"
        decide("appearance_link_allowed", str(root), str(target))
        target.write_text("user asset")
        decide("appearance_link_allowed", str(root), str(target), ok=False)
        target.unlink()
        target.symlink_to(root / "old" / "theme")
        decide("appearance_link_allowed", str(root), str(target), ok=False)
        (root / "old").mkdir()
        (root / "old/.dfa-appearance").write_text("dotfiles-arch appearance\n")
        decide("appearance_link_allowed", str(root), str(target))
        target.unlink()
        target.symlink_to(Path(temp) / "foreign")
        decide("appearance_link_allowed", str(root), str(target), ok=False)

        # Archive checks use tiny supplied data only; no font/theme host commands.
        stage = runpy.run_path(str(ROOT / "scripts/appearance-assets.py"))["stage"]
        archive = Path(temp) / "fonts.tar"
        with tarfile.open(archive, "w") as supplied:
            for name, content in (("Example.ttf", b"font-data"), ("LICENSE.txt", b"license"),
                                  ("install.sh", b"must not be installed")):
                member = tarfile.TarInfo(name)
                member.size = len(content)
                supplied.addfile(member, io.BytesIO(content))
        dest = Path(temp) / "fonts"
        stage("fonts", archive, dest)
        assert (dest / "Example.ttf").read_bytes() == b"font-data"
        assert (dest / "LICENSE.txt").read_bytes() == b"license"
        assert not (dest / "install.sh").exists()
        for name in ("../escaped.ttf", "/absolute.ttf"):
            with tarfile.open(archive, "w") as supplied:
                member = tarfile.TarInfo(name)
                supplied.addfile(member, io.BytesIO(b""))
            try:
                stage("fonts", archive, Path(temp) / "unsafe")
            except ValueError:
                pass
            else:
                raise AssertionError("Unsafe archive path accepted")
        with tarfile.open(archive, "w") as supplied:
            member = tarfile.TarInfo("linked.ttf")
            member.type = tarfile.SYMTYPE
            member.linkname = "/outside"
            supplied.addfile(member)
        try:
            stage("fonts", archive, Path(temp) / "unsafe-link")
        except ValueError:
            pass
        else:
            raise AssertionError("Archive link accepted")
        archive = Path(temp) / "gtk.zip"
        theme = "catppuccin-mocha-lavender-standard+default"
        with zipfile.ZipFile(archive, "w") as supplied:
            supplied.writestr(f"{theme}/index.theme", "[Icon Theme]")
            supplied.writestr(f"{theme}/gtk-3.0/gtk.css", "/* data */")
        dest = Path(temp) / "gtk"
        stage("gtk", archive, dest)
        assert (dest / theme / "gtk-3.0/gtk.css").read_text() == "/* data */"


if __name__ == "__main__":
    main()
