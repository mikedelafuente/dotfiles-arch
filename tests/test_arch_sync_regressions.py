"""Arch sync regressions with supplied package/launcher facts; no workstation writes."""
import os
from pathlib import Path
import shlex
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    with tempfile.TemporaryDirectory(prefix="arch-sync-regressions-") as temp:
        guard = Path(temp) / "bin"
        guard.mkdir()
        for name in ("sudo", "yay", "apt-get", "curl", "systemctl", "gsettings", "rustup", "go"):
            stub = guard / name
            stub.write_text('#!/bin/sh\necho "Forbidden command" >&2\nexit 97\n')
            stub.chmod(0o755)
        env = dict(os.environ, DF_SCRIPT_DIR=str(ROOT / "scripts"), USER_HOME_DIR=temp,
                   HOME=temp, WORKSTATION_DISTRO="arch", PATH=str(guard) + os.pathsep + os.environ["PATH"])
        facts = r'''
source "$DF_SCRIPT_DIR/fn-lib.sh"
pacman() {
  case "$1:$2" in
    -Q:rust|-Q:cargo) echo 'rustup 1.29.1-1' ;;
    -Qq:rust|-Qq:cargo) echo rustup ;;
    -Q:rustup) echo 'rustup 1.29.1-1' ;;
    -Qq:rustup) echo rustup ;;
    -Q:voxtype-bin) echo 'voxtype-bin 1.1.0-2' ;;
    -Qq:voxtype-bin) echo voxtype-bin ;;
    -Q:mullvad-vpn-bin) echo 'mullvad-vpn-bin 2026.5-1' ;;
    -Qq:mullvad-vpn-bin) echo mullvad-vpn-bin ;;
    -Q:mullvad-vpn-daemon-bin) echo 'mullvad-vpn-daemon-bin 2026.5-1' ;;
    -Qq:mullvad-vpn-daemon-bin) echo mullvad-vpn-daemon-bin ;;
    -Qoq:/usr/lib/voxtype/voxtype-vulkan|-Qoq:/usr/lib/voxtype/cuda-13/voxtype-onnx-cuda-13) echo "${VOXTYPE_FILE_OWNER:-voxtype-bin}" ;;
    -Qqo:/usr/bin/mullvad) echo "${MULLVAD_FILE_OWNER:-mullvad-vpn-daemon-bin}" ;;
    -Q:*|-Qq:*|-Qoq:*|-Qqo:*) return 1 ;;
    *) echo 'Forbidden command' >&2; return 97 ;;
  esac
}
type() {
  [[ "$1" == -P ]] || { builtin type "$@"; return; }
  case "$2" in voxtype|mullvad) printf '/usr/bin/%s\n' "$2" ;; *) return 1 ;; esac
}
command() {
  if [[ "$1" == -v && ( "$2" == snap || "$2" == flatpak ) ]]; then return 1; fi
  builtin command "$@"
}
'''
        wrapper = Path(temp) / "voxtype"
        wrapper.write_text('#!/bin/sh\n# voxtype dispatch wrapper.\nexec /usr/lib/voxtype/cuda-13/voxtype-onnx-cuda-13 "$@"\n')
        env["VOXTYPE_WRAPPER"] = str(wrapper)
        facts += r'''
# Supply the generated launcher without reading the workstation launcher.
if declare -F voxtype_dispatch_target >/dev/null; then
  eval "$(declare -f voxtype_dispatch_target | sed '1s/voxtype_dispatch_target/fixture_dispatch_target/')"
fi
voxtype_dispatch_target() { fixture_dispatch_target "$VOXTYPE_WRAPPER"; }
readlink() {
  if [[ "$1:$2" == -f:/usr/bin/voxtype ]]; then
    if [[ "${VOXTYPE_DISPATCH:-false}" == true ]]; then echo /usr/bin/voxtype
    else echo /usr/lib/voxtype/voxtype-vulkan; fi
  else command readlink "$@"; fi
}
'''
        failures = []
        cases = [
            ("provider is not installed package", "! native_package_installed rust && ! native_package_installed cargo && native_package_installed rustup", "", 0),
            ("Go build experiment suffix", shlex.join(["language_command_version", "go", "go version go1.27.2-X:nodwarf5 linux/amd64"]), "1.27.2", 0),
            ("Go prerelease still rejected", shlex.join(["language_command_version", "go", "go version go1.28rc1 linux/amd64"]), "", 1),
            ("Voxtype selected package binary", "dictation_app_owner voxtype verify", "aur", 0),
            ("Voxtype generated CUDA wrapper", "VOXTYPE_DISPATCH=true dictation_app_owner voxtype verify", "aur", 0),
            ("Voxtype CUDA target parsed", 'fixture_dispatch_target "$VOXTYPE_WRAPPER"', "/usr/lib/voxtype/cuda-13/voxtype-onnx-cuda-13", 0),
            ("Voxtype CUDA12 target parsed", 'sed -i s/cuda-13/cuda-12/g "$VOXTYPE_WRAPPER"; fixture_dispatch_target "$VOXTYPE_WRAPPER"', "/usr/lib/voxtype/cuda-12/voxtype-onnx-cuda-12", 0),
            ("Voxtype CUDA13 restored", 'sed -i s/cuda-12/cuda-13/g "$VOXTYPE_WRAPPER"; fixture_dispatch_target "$VOXTYPE_WRAPPER"', "/usr/lib/voxtype/cuda-13/voxtype-onnx-cuda-13", 0),
            ("Voxtype CUDA foreign binary rejected", "VOXTYPE_DISPATCH=true VOXTYPE_FILE_OWNER=foreign dictation_app_owner voxtype", "", 1),
            ("Voxtype modified wrapper rejected", '''printf '\\necho unexpected\\n' >>"$VOXTYPE_WRAPPER"; VOXTYPE_DISPATCH=true dictation_app_owner voxtype''', "", 1),
            ("Voxtype foreign binary rejected", "VOXTYPE_FILE_OWNER=foreign dictation_app_owner voxtype", "", 1),
            ("Mullvad split daemon package", "personal_app_installed_selection mullvad", "mullvad-vpn-bin aur", 0),
            ("Mullvad foreign CLI rejected", "MULLVAD_FILE_OWNER=foreign personal_app_installed_selection mullvad", "", 1),
        ]
        for name, action, expected, status in cases:
            result = subprocess.run(["bash", "-eu", "-o", "pipefail", "-c", facts + action],
                                    env=env, capture_output=True, text=True)
            assert "Forbidden command" not in result.stdout + result.stderr, result.stderr
            if result.returncode != status or result.stdout.strip() != expected:
                failures.append(f"{name}: status={result.returncode}, output={result.stdout + result.stderr!r}")
        assert not failures, "\n".join(failures)
    print("Arch sync regressions passed (offline; ownership conflicts still rejected)")


if __name__ == "__main__":
    main()
