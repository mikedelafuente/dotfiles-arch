#!/usr/bin/env python3
"""Enable Codex hooks without rewriting unrelated TOML preferences."""
from pathlib import Path
import os
import re
import sys
import tempfile
import tomllib


def enable_codex_hooks(text):
    expected = tomllib.loads(text)
    features = expected.setdefault("features", {})
    features.pop("codex_hooks", None)
    features["hooks"] = True
    header = re.search(r'^\[[ \t]*(?:features|"features"|\'features\')[ \t]*\][ \t]*(?:#.*)?$', text, re.M)
    if header:
        start = header.end()
        next_header = re.search(r'^\s*\[', text[start:], re.M)
        end = start + next_header.start() if next_header else len(text)
        body = text[start:end]
        body = re.sub(r'^\s*(?:codex_hooks|"codex_hooks"|\'codex_hooks\')\s*=.*\n?', '', body, flags=re.M)
        hook = r'^(\s*)(?:hooks|"hooks"|\'hooks\')\s*=.*$'
        if re.search(hook, body, re.M):
            body = re.sub(hook, r'\1hooks = true', body, flags=re.M)
        else:
            body = '\nhooks = true\n' + body.lstrip('\n')
        result = text[:start] + body + text[end:]
    else:
        # Inline/dotted feature tables need a deliberate edit, not a blind append.
        if "features" in tomllib.loads(text):
            raise ValueError("Cannot safely edit inline/dotted features; config preserved")
        result = text.rstrip() + '\n\n[features]\nhooks = true\n'
    if tomllib.loads(result) != expected:
        raise ValueError("Hook edit would change unrelated preferences; config preserved")
    return result


def main():
    path = Path(sys.argv[1])
    # Follow an existing config link, preserving its ownership/layout.
    path = path.resolve()
    original = path.read_text() if path.exists() else ""
    updated = enable_codex_hooks(original)
    if updated == original:
        return
    path.parent.mkdir(parents=True, exist_ok=True)
    fd, temporary = tempfile.mkstemp(dir=path.parent)
    try:
        with os.fdopen(fd, "w") as output:
            output.write(updated)
        if path.exists():
            os.chmod(temporary, path.stat().st_mode & 0o777)
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, TypeError) as error:
        sys.exit(str(error))
