#!/usr/bin/env python3
"""GNOME decisions from supplied facts and safe staging of verified archives."""
import ast
import json
import posixpath
from pathlib import Path, PurePosixPath
import re
import shutil
import sys
import tarfile
import zipfile

UBUNTU_REPLACEMENTS = ["pop-shell@system76.com", "dash-to-panel@jderose9.github.com",
                       "no-overview@fthx", "appindicatorsupport@rgcjonas.gmail.com"]


def extension_compatible(metadata, uuid, shell):
    if not re.fullmatch(r"[0-9]+(?:\.[0-9]+)*", shell):
        return False
    versions = metadata.get("shell-version")
    return (metadata.get("uuid") == uuid and isinstance(versions, list)
            and shell.split(".")[0] in versions)


def accepted_extension_skips(shell, distro="arch"):
    if distro == "ubuntu":
        return UBUNTU_REPLACEMENTS
    # Accepted Pop Shell gap above our GNOME 51 support; no other feature is exempt.
    if re.fullmatch(r"[0-9]+(?:\.[0-9]+)*", shell) and int(shell.split(".")[0]) > 51:
        return ["pop-shell@system76.com"]
    return []


def string_list(raw):
    values = ast.literal_eval(raw.removeprefix("@as "))
    if not isinstance(values, list) or not all(isinstance(v, str) for v in values):
        raise ValueError("Invalid GNOME string list")
    return values


def extension_lists(enabled, disabled, required, distro, shell=""):
    skipped = accepted_extension_skips(shell, distro)
    required = [v for v in required if v not in skipped]
    enabled = [v for v in string_list(enabled) if v not in skipped]
    disabled = [v for v in string_list(disabled) if v not in required]
    return (list(dict.fromkeys(enabled + required)),
            list(dict.fromkeys(disabled + skipped)))


def merge_shortcuts(existing, required):
    return list(dict.fromkeys(string_list(existing) + required))


def policy_action(existing, conflict, kind=""):
    owned = existing.startswith("# Managed by dotfiles-arch (setup-gnome.sh)")
    legacy_audio = kind == "audio" and existing.strip() == "options snd_hda_intel power_save=0"
    return "apply" if not conflict and (not existing or owned or legacy_audio) else "defer"


def power_policy_action(alternate, existed, load_state, active_state):
    if alternate or load_state == "masked":
        return "defer"
    if not existed:
        return "install"
    if load_state != "loaded":
        return "unavailable"
    return "apply" if active_state == "active" else "defer"


def stage_extension(kind, artifact, dest):
    dest.mkdir(parents=True, exist_ok=True)
    archive = zipfile.ZipFile(artifact) if kind == "zip" else tarfile.open(artifact)
    with archive:
        members = archive.infolist() if kind == "zip" else archive.getmembers()
        root = None
        for member in members:
            name = member.filename if kind == "zip" else member.name
            path = PurePosixPath(name)
            if path.is_absolute() or ".." in path.parts or not path.parts:
                raise ValueError("Unsafe GNOME archive path")
            if kind == "zip":
                if member.is_dir():
                    continue
                mode = (member.external_attr >> 16) & 0o170000
                if mode not in (0, 0o100000):
                    raise ValueError("Non-file GNOME archive member")
                source = archive.open(member)
            else:
                if root is None:
                    root = path.parts[0]
                if path.parts[0] != root:
                    raise ValueError("Multiple GNOME archive roots")
                if member.isdir():
                    continue
                if len(path.parts) < 2:
                    raise ValueError("Non-file GNOME archive member")
                if member.issym():
                    # Pop shares config.ts through a relative source link. Copy
                    # only an in-root regular archive member, never create links.
                    linked = PurePosixPath(posixpath.normpath(str(path.parent / member.linkname)))
                    if (PurePosixPath(member.linkname).is_absolute() or ".." in linked.parts
                            or not linked.parts or linked.parts[0] != root):
                        raise ValueError("Unsafe GNOME archive link")
                    member = archive.getmember(str(linked))
                if not member.isfile():
                    raise ValueError("Non-file GNOME archive member")
                path = PurePosixPath(*path.parts[1:])
                source = archive.extractfile(member)
            target = dest / path
            target.parent.mkdir(parents=True, exist_ok=True)
            with source, target.open("xb") as output:
                shutil.copyfileobj(source, output)
    if not (dest / "metadata.json").is_file():
        raise ValueError("Missing GNOME extension metadata")


if __name__ == "__main__":
    operation, *args = sys.argv[1:]
    if operation == "compatible":
        metadata, uuid, shell = args
        if not extension_compatible(json.loads(Path(metadata).read_text()), uuid, shell):
            sys.exit(f"Required GNOME extension {uuid} does not support shell {shell}; preserved. "
                     "Update its selected source or obtain an explicit feature exception.")
    elif operation == "lists":
        enabled, disabled = extension_lists(args[2], args[3], args[4:], args[0], args[1])
        print(repr(enabled))
        print(repr(disabled))
    elif operation == "skips":
        print("\n".join(accepted_extension_skips(*args)))
    elif operation == "shortcuts":
        print(repr(merge_shortcuts(args[0], args[1:])))
    elif operation == "remove-shortcut":
        print(repr([path for path in string_list(args[0]) if path != args[1]]))
    elif operation == "policy":
        print(policy_action(args[0], args[1] == "true", args[2]))
    elif operation == "power":
        print(power_policy_action(args[0] == "true", args[1] == "true", args[2], args[3]))
    elif operation == "stage":
        stage_extension(args[0], Path(args[1]), Path(args[2]))
    else:
        sys.exit("Unknown GNOME operation")
