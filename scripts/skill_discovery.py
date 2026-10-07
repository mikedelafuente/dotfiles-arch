#!/usr/bin/env python3
"""Discover skill parents and reject ambiguous installed names before linking."""
import argparse
import os
from pathlib import Path
import sys


def discover_skills(roots, overwritable=()):
    by_name = {}
    owners = {}
    overwritable = {root.resolve() for root in overwritable}
    for root in roots:
        root = root.resolve()
        source_names = set()
        for directory, children, files in os.walk(root):
            parent = Path(directory)
            candidates = [parent] if "SKILL.md" in files else []
            # Preserve supported leaf aliases without following directory cycles.
            candidates += [parent / child for child in children
                           if (parent / child).is_symlink()
                           and (parent / child / "SKILL.md").is_file()]
            for skill in candidates:
                if not (skill / "SKILL.md").is_file():
                    raise ValueError(f"Missing or broken skill marker: {skill}")
                resolved = skill.resolve()
                marker = (skill / "SKILL.md").resolve()
                if (resolved != root and root not in resolved.parents) or root not in marker.parents:
                    raise ValueError(f"External source skill symlink: {skill}")
                if skill.name in source_names:
                    raise ValueError(f"Duplicate skill name {skill.name}: "
                                     f"{by_name[skill.name]} and {skill}")
                source_names.add(skill.name)
                if skill.name in by_name and owners[skill.name] not in overwritable:
                    raise ValueError(f"Duplicate skill name {skill.name}: protected source "
                                     f"{owners[skill.name]} (overwritable=false) blocks "
                                     f"replacement of {by_name[skill.name]} by {skill}; "
                                     "set the losing source --overwritable true to allow it")
                by_name[skill.name] = skill
                owners[skill.name] = root
    return sorted(by_name.values())


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--overwritable", action="append", type=Path, default=[])
    parser.add_argument("roots", nargs="*", type=Path)
    args = parser.parse_args()
    try:
        skills = discover_skills(args.roots, args.overwritable)
    except (OSError, ValueError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
    for skill in skills:
        sys.stdout.buffer.write(os.fsencode(skill) + b"\0")
