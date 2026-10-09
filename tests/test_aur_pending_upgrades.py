"""AUR query status checks with supplied facts; no network or package actions."""
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[1]
SCRIPT = r'''
source "$AUR_LIB"
print_error_message() { printf '%s\n' "$*" >&2; }
print_info_message() { printf '%s\n' "$*"; }
print_action_message() { printf '%s\n' "$*"; }
print_success_message() { printf '%s\n' "$*"; }
yay() { printf '%s' "$QUERY_OUT"; printf '%s' "$QUERY_ERR" >&2; return "$QUERY_RC"; }
aur_scan_package_tree() { printf 'scan:%s\n' "$1"; return "$SCAN_RC"; }
aur_scan_pending_upgrades
'''


def main():
    cases = [
        ("successful empty list", 0, "", "", 0, 0, "No pending AUR upgrades to scan"),
        ("yay empty-list status", 1, "", "", 0, 0, "No pending AUR upgrades to scan"),
        ("connection failure", 1, "", "request failed\n", 0, 1, ""),
        ("partial query failure", 1, "one 1 -> 2\n", "", 0, 1, ""),
        ("other empty failure", 2, "", "", 0, 2, ""),
        ("scan every update", 0, "one 1 -> 2\ntwo 3 -> 4\n", "", 0, 0, "scan:one\nscan:two"),
        ("scan failure", 0, "one 1 -> 2\n", "", 1, 1, "scan:one"),
    ]
    for name, rc, out, err, scan_rc, expected, message in cases:
        env = dict(os.environ, AUR_LIB=str(ROOT / "scripts/aur-lib.sh"), QUERY_RC=str(rc),
                   QUERY_OUT=out, QUERY_ERR=err, SCAN_RC=str(scan_rc))
        result = subprocess.run(["bash", "-eu", "-o", "pipefail", "-c", SCRIPT],
                                env=env, capture_output=True, text=True)
        assert result.returncode == expected, (name, result.stdout, result.stderr)
        assert message in result.stdout, (name, result.stdout)
        if rc and expected:
            assert "Cannot query pending AUR upgrades" in result.stderr
            assert "scan:" not in result.stdout
        if err:
            assert err.strip() in result.stderr
    print("PASS: empty AUR queries succeed; real query/scan failures remain blocked")


if __name__ == "__main__":
    main()
