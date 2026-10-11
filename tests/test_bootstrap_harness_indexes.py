"""Verify source/key checks can precede refresh without consulting stale indexes."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class HarnessIndexes(unittest.TestCase):
    def test_source_checks_and_candidate_checks_remain_separate(self):
        for app in ("claude", "chatgpt"):
            with self.subTest(app=app), tempfile.TemporaryDirectory() as tmp:
                script = r'''
source "$1/scripts/harness-lib.sh"
WORKSTATION_DISTRO=ubuntu
native_package_installed() { return 0; }
work_app_apt_source() { echo '/etc/apt/sources.list.d/vendor.list /usr/share/keyrings/vendor.gpg'; }
stage_work_app_key() { echo key >> "$fixture_log"; }
apt-cache() { echo stale >> "$fixture_log"; return 97; }
work_app_apt_candidate() { return 1; }
'''
                # Stub tools capture effects in a fixture, never inspect native packages.
                script += r'''
fixture_log="$2"
checker="check_${3}_apt_owner"
"$checker" --source-only || exit 1
[[ "$(cat "$fixture_log")" == key ]] || exit 1
if "$checker"; then exit 1; fi
[[ "$(cat "$fixture_log")" == $'key\nkey\nstale' ]]
'''
                result = subprocess.run(["bash", "-eu", "-o", "pipefail", "-c", script,
                                         "test", str(ROOT), str(Path(tmp) / "calls"), app],
                                        capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)


if __name__ == "__main__":
    unittest.main()
