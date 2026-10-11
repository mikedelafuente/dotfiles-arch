"""Supplied package facts only; never install workstation packages."""
from pathlib import Path
import subprocess
import unittest

LIB = Path(__file__).resolve().parents[1] / "scripts/gpu-tools-lib.sh"


class SteamNvidiaLibraries(unittest.TestCase):
    def check_case(self, records, candidate="595.99", installed="", stack="", ok=True, added="", distro="ubuntu"):
        script = r'''
source "$1"
WORKSTATION_DISTRO="$2"
fixture_records="$3"; fixture_candidate="$4"; fixture_installed="$5"; fixture_stack="$6"; added=""
print_error_message() { echo "$*" >&2; }
print_info_message() { :; }
dpkg-query() {
  if [[ "$*" == *'${Architecture}'* ]]; then printf '%s\n' "$fixture_records"
  else printf '%s' "$fixture_installed"; fi
}
apt-cache() { printf '  Candidate: %s\n' "$fixture_candidate"; }
native_package_installed() { [[ -n "$fixture_installed" ]]; }
gpu_installed_nvidia_packages() { printf '%s' "$fixture_stack"; }
gpu_nvidia_module_loaded() { return 1; }
ensure_native_pkgs() { added="$*"; fixture_installed="$fixture_candidate"; }
if ensure_ubuntu_steam_nvidia_libraries; then status=0; else status=1; fi
printf '%s' "$added"
exit "$status"
'''
        result = subprocess.run(["bash", "-eu", "-o", "pipefail", "-c", script,
                                 "test", str(LIB), distro, records, candidate, installed, stack],
                                capture_output=True, text=True)
        self.assertEqual(result.returncode, 0 if ok else 1, result.stderr)
        self.assertEqual(result.stdout, added)

    def test_matching_libraries_and_server_flavor(self):
        for flavor in ("595", "595-server"):
            self.check_case(f"libnvidia-gl-{flavor}:amd64 amd64 595.99 ok installed",
                            added=f"libnvidia-gl-{flavor}:i386")

    def test_already_installed(self):
        self.check_case("libnvidia-gl-595:amd64 amd64 595.99 ok installed", installed="595.99")

    def test_conflicts_do_not_install(self):
        record = "libnvidia-gl-595:amd64 amd64 595.99 ok installed"
        self.check_case(record, candidate="(none)", ok=False)
        self.check_case(record, candidate="595.100", ok=False)
        self.check_case(record, installed="595.98", ok=False)
        self.check_case(record + "\nlibnvidia-gl-580:amd64 amd64 580.1 ok installed", ok=False)
        self.check_case("", stack="nvidia-driver-595-open", ok=False)

    def test_arch_and_amd_or_intel_skip(self):
        self.check_case("", distro="arch")
        self.check_case("libnvidia-gl-595:i386 i386 595.99 ok installed\n"
                        "libnvidia-gl-580:amd64 amd64 580.1 ok config-files")


if __name__ == "__main__":
    unittest.main()
