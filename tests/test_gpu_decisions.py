"""Supplied GPU/source facts only. Left unrun under the implementation constraint."""
from pathlib import Path
import json
import os
import shlex
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    with tempfile.TemporaryDirectory(prefix="gpu-decisions-") as temp:
        guard = Path(temp) / "bin"
        guard.mkdir()
        for name in ("sudo", "pacman", "yay", "apt-get", "apt-cache", "dpkg-query",
                     "curl", "wget", "systemctl", "gsettings", "nvidia-smi",
                     "vulkaninfo", "ollama", "modprobe", "modinfo", "mokutil"):
            command = guard / name
            command.write_text('#!/bin/sh\necho "Forbidden GPU command" >&2\nexit 97\n')
            command.chmod(0o755)
        env = dict(os.environ, DF_SCRIPT_DIR=str(ROOT / "scripts"), USER_HOME_DIR=temp,
                   PATH=str(guard) + os.pathsep + os.environ["PATH"])

        def decide(*args, expected="", ok=True):
            result = subprocess.run(
                ["bash", "-eu", "-o", "pipefail", "-c",
                 'source "$DF_SCRIPT_DIR/fn-lib.sh"; ' + shlex.join(args)],
                env=env, capture_output=True, text=True,
            )
            assert "Forbidden GPU command" not in result.stdout + result.stderr
            assert result.returncode == (0 if ok else 1), result.stdout + result.stderr
            if ok:
                assert result.stdout.strip() == expected, result.stdout

        for distro in ("arch", "ubuntu"):
            decide("nvidia_setup_selection", distro, "false", "false", "true", expected="skip")
            decide("nvidia_setup_selection", distro, "true", "true", "true", expected="preserve")
            decide("nvidia_setup_selection", distro, "false", "true", "true", expected="preserve")
            decide("nvidia_setup_selection", distro, "true", "false", "false", expected="skip")
            decide("nvidia_setup_selection", distro, "true", "false", "true", expected="install")
        decide("nvidia_setup_selection", "fedora", "true", "false", "true", ok=False)
        for distro, package, kind in (("arch", "nvidia-open-dkms", "module"),
                                     ("arch", "nvidia-470xx-dkms", "module"),
                                     ("arch", "nvidia-utils", "stack"),
                                     ("ubuntu", "nvidia-driver-580-open", "module"),
                                     ("ubuntu", "linux-modules-nvidia-580-open-6.17.0-5-generic", "module"),
                                     ("ubuntu", "libnvidia-compute-580", "stack")):
            decide("gpu_nvidia_package_kind", distro, package, expected=kind)
        decide("gpu_nvidia_package_kind", "ubuntu", "nvidia-cuda-toolkit", ok=False)
        decide("gpu_nvidia_package_kind", "arch", "cuda", ok=False)
        decide("gpu_cuda_supported", "550.54.14, 8.6")
        decide("gpu_cuda_supported", "570.124.04, 6.1")
        decide("gpu_cuda_supported", "550.54.14, 6.1", ok=False)
        decide("gpu_cuda_supported", "535.54.03, 8.6", ok=False)
        decide("gpu_cuda_supported", "550.54.14, 3.5", ok=False)
        decide("gpu_cuda_supported", "not supported", ok=False)
        decide("gpu_cuda_supported", "535.54.03, 8.6\n580.65.06, 12.0")
        summary = "GPU0:\n apiVersion = 1.3.280\n deviceType = PHYSICAL_DEVICE_TYPE_DISCRETE_GPU\n"
        decide("gpu_vulkan_supported", summary)
        decide("gpu_vulkan_supported", summary.replace("DISCRETE_GPU", "INTEGRATED_GPU"))
        decide("gpu_vulkan_supported", summary.replace("DISCRETE_GPU", "CPU"), ok=False)
        decide("gpu_vulkan_supported", summary.replace("1.3.280", "1.1.180"), ok=False)
        decide("gpu_vulkan_supported", "ICD exists", ok=False)
        recommendation = "driver : nvidia-driver-580-open - distro non-free recommended"
        decide("ubuntu_nvidia_recommendation", recommendation, expected="nvidia-driver-580-open")
        decide("ubuntu_nvidia_recommendation", recommendation.replace("distro", "third-party"), ok=False)
        decide("ubuntu_nvidia_recommendation", recommendation + "\n" + recommendation, ok=False)
        gpu = "01:00.0 VGA compatible controller: NVIDIA Corporation GA104 [GeForce RTX 3070]"
        decide("gpu_nvidia_open_supported", gpu)
        decide("gpu_nvidia_open_supported", gpu.replace("GA104", "TU104GL"))
        decide("gpu_nvidia_open_supported", gpu.replace("GA104", "GP104"), ok=False)
        decide("gpu_nvidia_open_supported", gpu.replace("GA104", "Unknown chipset"), ok=False)
        decide("gpu_nvidia_open_supported", gpu + "\n" + gpu.replace("GA104", "GP104"), ok=False)
        for distro in ("arch", "ubuntu"):
            decide("ollama_gpu_selection", distro, "none", "", "true", "true", expected="cuda")
            decide("ollama_gpu_selection", distro, "none", "", "false", "true", expected="vulkan")
            decide("ollama_gpu_selection", distro, "none", "", "false", "false", expected="skip")
            decide("ollama_gpu_selection", distro, "unknown", "", "true", "true", ok=False)
            decide("ollama_gpu_selection", distro, "native", "cuda", "false", "true", ok=False)
            decide("ollama_gpu_selection", distro, "native", "vulkan", "true", "true", expected="vulkan")
            decide("ollama_gpu_selection", distro, "native", "", "true", "true", ok=False)
        metadata = {"tag_name": "v0.40.2", "draft": False, "prerelease": False, "assets": [{
            "name": "ollama-linux-amd64.tar.zst",
            "browser_download_url": "https://github.com/ollama/ollama/releases/download/v0.40.2/ollama-linux-amd64.tar.zst",
            "digest": "sha256:" + "a" * 64,
        }]}
        expected = "0.40.2 https://github.com/ollama/ollama/releases/download/v0.40.2/ollama-linux-amd64.tar.zst " + "a" * 64
        decide("editor_release_asset", "ollama", json.dumps(metadata), expected=expected)
        metadata["assets"][0]["digest"] = None
        decide("editor_release_asset", "ollama", json.dumps(metadata), ok=False)
        decide("editor_tool_version", "ollama", "Warning: client version is 0.40.2", expected="0.40.2")
        decide("editor_tool_version", "ollama", "Warning: client version is 0.40.2-rc1", ok=False)
    print("GPU decisions passed; no driver, inference, service or update workflows executed")


if __name__ == "__main__":
    main()
