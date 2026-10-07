#!/usr/bin/env python3
"""Portable filesystem installer used by install-cloud-agent-config.sh."""
import argparse
import os
from pathlib import Path
import re
import stat
import sys
import tempfile
from skill_discovery import discover_skills

BEGIN = "<!-- dotfiles-arch cloud baseline begin -->"
END = "<!-- dotfiles-arch cloud baseline end -->"


def install(source, home, baseline):
    source = source.resolve()
    skills = source / "skills"
    skill_dirs = discover_skills([skills])
    if not skill_dirs:
        raise ValueError("No source skills found")
    for skill in skill_dirs:
        # Never propagate laptop-only or broken source symlinks into a cloud task.
        for entry in [skill, *skill.rglob("*")]:
            if entry.is_symlink() and (
                not entry.exists() or source not in entry.resolve().parents
            ):
                raise ValueError(f"Broken or external source symlink: {entry}")

    home = home.expanduser().resolve()
    skill_target = home / ".agents" / "skills"
    for directory in (home / ".agents", skill_target):
        if directory.is_symlink():
            raise ValueError(f"Preserving redirected skill directory: {directory}")
    codex_home = Path(os.environ.get("CODEX_HOME") or home / ".codex").expanduser().resolve()
    agents = codex_home / "AGENTS.md"
    override = codex_home / "AGENTS.override.md"
    if override.exists() and override.read_text().strip():
        raise ValueError(f"Global override would mask the baseline: {override}")
    if agents.is_symlink():
        raise ValueError(f"Preserving existing AGENTS.md symlink: {agents}")
    existing = agents.read_text() if agents.exists() else ""
    if existing.count(BEGIN) != existing.count(END) or existing.count(BEGIN) > 1:
        raise ValueError(f"Malformed managed baseline block: {agents}")
    if BEGIN in existing and existing.index(BEGIN) > existing.index(END):
        raise ValueError(f"Reversed managed baseline markers: {agents}")

    # Preflight all collisions before any target mutation. Only links owned by
    # this checkout's skills directory may be updated or pruned.
    for skill in skill_dirs:
        dest = skill_target / skill.name
        if dest.is_symlink():
            old = Path(os.path.abspath(dest.parent / os.readlink(dest)))
            owned = skills in old.parents and old.name == dest.name
            if dest.resolve() != skill.resolve() and not owned:
                raise ValueError(f"Preserving unrelated skill symlink: {dest}")
        elif dest.exists():
            raise ValueError(f"Preserving existing real skill entry: {dest}")
    stale = []
    if skill_target.exists():
        names = {skill.name for skill in skill_dirs}
        stale = [p for p in skill_target.iterdir() if p.is_symlink()
                 and skills in Path(os.path.abspath(p.parent / os.readlink(p))).parents
                 and Path(os.readlink(p)).name == p.name and p.name not in names]

    body = baseline.read_text().strip()
    block = f"{BEGIN}\n\n# Shared dotfiles baseline\n\n{body}\n\n{END}"
    if BEGIN in existing:
        updated = re.sub(re.escape(BEGIN) + r".*?" + re.escape(END),
                         lambda _: block, existing, count=1, flags=re.DOTALL)
    else:
        updated = existing + ("\n\n" if existing else "") + block + "\n"

    skill_target.mkdir(parents=True, exist_ok=True)
    for skill in skill_dirs:
        dest = skill_target / skill.name
        if dest.is_symlink() and os.readlink(dest) != str(skill):
            dest.unlink()
        if not dest.is_symlink():
            dest.symlink_to(skill, target_is_directory=True)
    for dest in stale:
        dest.unlink()
    codex_home.mkdir(parents=True, exist_ok=True)
    if updated != existing:
        # Atomic replacement preserves user text outside our block and mode.
        mode = stat.S_IMODE(agents.stat().st_mode) if agents.exists() else 0o644
        fd, tmp = tempfile.mkstemp(prefix=".dotfiles-agents-", dir=codex_home)
        try:
            with os.fdopen(fd, "w") as stream:
                stream.write(updated)
            os.chmod(tmp, mode)
            os.replace(tmp, agents)
        finally:
            if os.path.exists(tmp):
                os.unlink(tmp)
    print(f"Installed {len(skill_dirs)} shared skills in {skill_target}")
    print(f"Shared alwaysApply rule baseline: {agents}")
    print("Project AGENTS.md remains unchanged; verify discovery in a fresh cloud task.")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, required=True)
    parser.add_argument("--home", type=Path, required=True,
                        help="Cloud user's home (recommended: --home \"$HOME\")")
    parser.add_argument("--baseline", type=Path, required=True)
    args = parser.parse_args()
    try:
        install(args.source, args.home, args.baseline)
    except (OSError, ValueError) as error:
        print(f"Cloud agent config install failed: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
