#!/usr/bin/env python3
"""Stage checksum-verified appearance data; never execute archive contents."""
from pathlib import Path, PurePosixPath
import shutil
import sys
import tarfile
import zipfile

THEME = "catppuccin-mocha-lavender-standard+default"


def stage(kind, artifact, dest):
    dest.mkdir(parents=True, exist_ok=True)
    if kind == "bat":
        shutil.copyfile(artifact, dest / "Catppuccin Mocha.tmTheme")
        return
    if kind == "overlay":
        for theme in ("Papirus", "Papirus-Dark"):
            native = Path("/usr/share/icons") / theme
            if not (native / "index.theme").is_file():
                raise ValueError(f"Missing native {theme} index")
            shutil.copytree(native, dest / theme, symlinks=True)
            # The packaged cache describes the original icons, not this recolored copy.
            cache = dest / theme / "icon-theme.cache"
            if cache.exists() or cache.is_symlink():
                cache.unlink()
        # Follow upstream's color selection algorithm, entirely in the private copy.
        # Papirus-Dark inherits/links to Papirus. Neither package-owned tree is modified.
        for svg in artifact.rglob("*-cat-mocha-lavender*.svg"):
            relative = svg.relative_to(artifact)
            target = dest / "Papirus" / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(svg, target)
        count = 0
        for theme in ("Papirus", "Papirus-Dark"):
            for svg in (dest / theme).glob("*/places/*-cat-mocha-lavender*.svg"):
                target = svg.with_name(svg.name.replace("-cat-mocha-lavender", ""))
                if target.exists() or target.is_symlink():
                    target.unlink()
                target.symlink_to(svg.name)
                count += 1
        if not count:
            raise ValueError("Missing Catppuccin Mocha Lavender folder assets")
        return
    archive = zipfile.ZipFile(artifact) if kind == "gtk" else tarfile.open(artifact)
    with archive:
        members = archive.infolist() if kind == "gtk" else archive.getmembers()
        count = 0
        for member in members:
            name = member.filename if kind == "gtk" else member.name
            path = PurePosixPath(name)
            if path.is_absolute() or ".." in path.parts:
                raise ValueError("Unsafe appearance archive path")
            if kind == "gtk":
                if member.is_dir():
                    continue
                # UNIX zip symlinks and other special files are never extracted.
                mode = (member.external_attr >> 16) & 0o170000
                if mode not in (0, 0o100000) or path.parts[0] not in {
                    THEME, THEME + "-hdpi", THEME + "-xhdpi"
                }:
                    raise ValueError("Unexpected GTK archive member")
                relative = path
                source = archive.open(member)
            else:
                if member.isdir():
                    continue
                if not member.isfile():
                    raise ValueError("Non-file appearance archive member")
                if kind == "fonts":
                    if path.suffix.lower() not in (".ttf", ".otf") and not any(
                        token in path.name.lower() for token in ("license", "licence", "ofl")
                    ):
                        continue
                    relative = path
                elif kind == "adwaita":
                    if path.name != "LICENSE" and (
                        len(path.parts) != 3 or path.parts[1] != "mono" or path.suffix != ".ttf"
                    ):
                        continue
                    relative = PurePosixPath(path.name)
                elif kind == "papirus":
                    if path.name == "LICENSE":
                        relative = PurePosixPath("LICENSE")
                    elif (len(path.parts) >= 3 and path.parts[1] == "src"
                          and path.suffix == ".svg" and "-cat-mocha-lavender" in path.name):
                        relative = PurePosixPath(*path.parts[2:])
                    else:
                        continue
                else:
                    raise ValueError("Unknown appearance archive kind")
                source = archive.extractfile(member)
            target = dest / relative
            target.parent.mkdir(parents=True, exist_ok=True)
            with source, target.open("xb") as output:
                shutil.copyfileobj(source, output)
            count += 1
        if not count:
            raise ValueError("Appearance archive has no required assets")
    if kind == "gtk" and not (dest / THEME / "gtk-3.0/gtk.css").is_file():
        raise ValueError("GTK stylesheet is missing")


if __name__ == "__main__":
    stage(sys.argv[1], Path(sys.argv[2]), Path(sys.argv[3]))
