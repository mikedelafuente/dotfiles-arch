"""Supplied curl failures, with no network or real waits."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class Downloads(unittest.TestCase):
    def check_case(self, failures, status, expected_attempts, output=""):
        with tempfile.TemporaryDirectory() as tmp:
            script = r'''
source "$1/scripts/editor-tools-lib.sh"
fixture_calls="$2"; fixture_failures="$3"; fixture_status="$4"
print_warning_message() { echo "$*" >&2; }
print_error_message() { echo "$*" >&2; }
sleep() { :; }
curl() {
  local attempt=0
  [[ ! -f "$fixture_calls" ]] || attempt="$(cat "$fixture_calls")"
  attempt=$((attempt + 1))
  echo "$attempt" > "$fixture_calls"
  if (( attempt <= fixture_failures )); then
    echo 'incomplete metadata'
    return "$fixture_status"
  fi
  printf '%s' '{"complete":true}'
}
editor_https_fetch https://example.org/metadata
'''
            calls = Path(tmp) / "attempts"
            result = subprocess.run(["bash", "-eu", "-o", "pipefail", "-c", script,
                                     "test", str(ROOT), str(calls), str(failures), str(status)],
                                    capture_output=True, text=True)
            self.assertEqual(int(calls.read_text()), expected_attempts)
            self.assertEqual(result.returncode, 0 if output else status, result.stderr)
            self.assertEqual(result.stdout, output)

    def test_transient_dns_recovers_without_partial_output(self):
        self.check_case(2, 6, 3, '{"complete":true}')

    def test_persistent_network_failures_stop(self):
        for status in (5, 6, 7, 28):
            with self.subTest(status=status):
                self.check_case(9, status, 3)

    def test_http_and_tls_failures_are_not_retried(self):
        for status in (22, 60):
            with self.subTest(status=status):
                self.check_case(9, status, 1)


if __name__ == "__main__":
    unittest.main()
