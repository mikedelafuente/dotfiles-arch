"""Picker guidance and dispatch checks; no workstation actions."""
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]
PICKER = ROOT / "home/.local/bin/dfa"


def main():
    with tempfile.TemporaryDirectory(prefix="dfa-picker-") as temp:
        stub = Path(temp) / "dfa-deploy"
        stub.write_text('#!/bin/sh\nprintf "%s\\n" "$@"\n')
        stub.chmod(0o755)
        env = dict(os.environ, PATH=temp + os.pathsep + os.environ["PATH"])
        def run(*args):
            return subprocess.run(["bash", str(PICKER), *args], env=env,
                                  check=True, capture_output=True, text=True).stdout
        assert run("deploy") == "deploy\n"
        assert run("deploy", "update") == "update\n"
        assert run("deploy", "deploy", "--dry-run") == "deploy\n--dry-run\n"
        rows = run("list")
        assert "Daily/weekly need a clean dotfiles checkout" in rows
        assert rows.index("dfa-daily") < rows.index("dfa-weekly") < rows.index("dfa-deploy")
        assert "uncommitted changes" in run("__preview__", "daily")
        assert "no pull, installs or setup" in run("__preview__", "deploy")
    print("PASS: action guide, deploy default and explicit subcommand dispatch")


if __name__ == "__main__":
    main()
