#!/usr/bin/env python3
"""Discover skill parents and reject ambiguous installed names before linking."""
import os
from pathlib import Path
import sys


def discover_skills(roots):
    by_name = {}
    for root in roots:
        root = root.resolve()
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
                if skill.name in by_name:
                    raise ValueError(f"Duplicate skill name {skill.name}: "
                                     f"{by_name[skill.name]} and {skill}")
                by_name[skill.name] = skill
    return sorted(by_name.values())


if __name__ == "__main__":
    try:
        skills = discover_skills([Path(arg) for arg in sys.argv[1:]])
    except (OSError, ValueError) as error:
        print(error, file=sys.stderr)
        sys.exit(1)
    for skill in skills:
        sys.stdout.buffer.write(os.fsencode(skill) + b"\0")
