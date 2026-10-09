"""Supplied dictation facts only. Written for the spec seam; deliberately unrun."""
from pathlib import Path
import json
import os
import shlex
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    with tempfile.TemporaryDirectory(prefix="dictation-decisions-") as temp:
        guard = Path(temp) / "bin"
        guard.mkdir()
        for name in ("sudo", "pacman", "yay", "apt-get", "apt-cache", "apt-mark",
                     "dpkg", "dpkg-query", "dpkg-deb", "curl", "wget", "go",
                     "systemctl", "gsettings", "nvidia-smi", "vulkaninfo", "voxtype",
                     "dotool", "usermod", "udevadm", "modprobe"):
            command = guard / name
            command.write_text('#!/bin/sh\necho "Forbidden dictation command" >&2\nexit 97\n')
            command.chmod(0o755)
        env = dict(os.environ, DF_SCRIPT_DIR=str(ROOT / "scripts"), USER_HOME_DIR=temp,
                   PATH=str(guard) + os.pathsep + os.environ["PATH"])

        def decide(*args, expected="", ok=True):
            result = subprocess.run(
                ["bash", "-eu", "-o", "pipefail", "-c",
                 'source "$DF_SCRIPT_DIR/fn-lib.sh"; ' + shlex.join(args)],
                env=env, capture_output=True, text=True,
            )
            assert "Forbidden dictation command" not in result.stdout + result.stderr
            assert result.returncode == (0 if ok else 1), result.stdout + result.stderr
            if ok:
                assert result.stdout.strip() == expected, result.stdout

        for distro in ("arch", "ubuntu"):
            decide("dictation_source_selection", distro, "voxtype", "none", "", expected="aur" if distro == "arch" else "release")
            decide("dictation_source_selection", distro, "dotool", "none", "", expected="aur" if distro == "arch" else "build")
            decide("dictation_source_selection", distro, "voxtype", "unknown", "1.1.0", ok=False)
            decide("dictation_source_selection", distro, "voxtype", "native", "1.1.0", expected="native")
            for app, version, owners in (("voxtype", "0.7.0", ("native", "aur", "release")),
                                         ("dotool", "1.5.0", ("native", "aur", "build"))):
                for owner in owners:
                    decide("dictation_source_selection", distro, app, owner, version, expected=owner)
                decide("dictation_version_supported", app, version, ok=False)
                decide("dictation_source_selection", distro, app, "unknown", version, ok=False)
                decide("dictation_source_selection", distro, app, "native", "malformed", ok=False)
            decide("dictation_source_selection", distro, "dotool", "native", "1.6.0", expected="native")
        decide("dictation_version_supported", "voxtype", "1.1.0")
        decide("dictation_version_supported", "dotool", "1.6.0")
        flags = "sse4_2 ssse3 popcnt cx16 lahf_lm"
        decide("voxtype_backend_selection", "new", flags, "false", "false", "", "false", expected="voxtype-baseline")
        decide("voxtype_backend_selection", "new", flags + " avx2", "false", "true", "", "false", expected="voxtype-vulkan")
        decide("voxtype_backend_selection", "new", flags + " avx2", "true", "false", "", "false", expected="voxtype-avx2")
        decide("voxtype_backend_selection", "new", flags + " avx2 avx512f", "true", "true", "", "false", expected="voxtype-onnx-cuda-13")
        decide("voxtype_backend_selection", "whisper", flags + " avx2", "true", "true", "voxtype-avx2", "false", expected="voxtype-avx2")
        decide("voxtype_backend_selection", "parakeet", flags + " avx2", "false", "true", "voxtype-onnx-avx2", "false", expected="voxtype-onnx-avx2")
        decide("voxtype_backend_selection", "parakeet", flags + " avx2", "true", "true", "voxtype-onnx-cuda-13", "false", ok=False)
        decide("voxtype_backend_selection", "parakeet", flags + " avx2 avx512f", "false", "true", "voxtype-onnx-cuda-12", "true", expected="voxtype-onnx-cuda-12")
        decide("voxtype_backend_selection", "parakeet", flags + " avx2 avx512f", "true", "true", "voxtype-onnx-cuda-12", "false", ok=False)
        decide("voxtype_backend_selection", "whisper", flags, "false", "true", "voxtype-vulkan", "false", ok=False)
        decide("voxtype_backend_selection", "parakeet", flags, "false", "false", "", "false", ok=False)
        decide("voxtype_backend_selection", "whisper", "", "false", "false", "", "false", ok=False)
        decide("voxtype_cuda13_supported", "580.65.06, 12.0")
        decide("voxtype_cuda13_supported", "570.124.04, 8.6", ok=False)
        decide("voxtype_cuda13_supported", "580.65.06, 6.1", ok=False)
        decide("voxtype_cuda13_supported", "580.65.06, 8.6\n580.65.06, 6.1", ok=False)
        decide("voxtype_cuda13_supported", "not supported", ok=False)
        decide("voxtype_cuda12_supported", "550.54.14, 8.6")
        decide("voxtype_cuda12_supported", "580.65.06, 12.0", ok=False)
        decide("voxtype_cuda12_supported", "550.54.14, 6.1", ok=False)
        release = {"tag_name": "v1.1.0", "draft": False, "prerelease": False, "assets": [{
            "name": "voxtype_1.1.0-1_amd64.deb",
            "browser_download_url": "https://github.com/peteonrails/voxtype/releases/download/v1.1.0/voxtype_1.1.0-1_amd64.deb",
            "digest": "sha256:" + "a" * 64}]}
        decide("editor_release_asset", "voxtype", json.dumps(release), expected="1.1.0 " + release["assets"][0]["browser_download_url"] + " " + "a" * 64)
        release["assets"][0]["digest"] = None
        decide("editor_release_asset", "voxtype", json.dumps(release), ok=False)
        source = "deb [arch=amd64 signed-by=/usr/share/keyrings/cuda.gpg] https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2604/x86_64/ /"
        decide("work_app_apt_key", "voxtype-cuda", source, expected="/usr/share/keyrings/cuda.gpg")
        decide("work_app_apt_key", "voxtype-cuda", source.replace("ubuntu2604", "ubuntu2404"), ok=False)
        decide("work_app_apt_key", "voxtype-cuda", source.replace(" signed-by=/usr/share/keyrings/cuda.gpg", ""), ok=False)
        config = Path(temp) / "config.toml"
        original = '[hotkey]\nenabled=false\n[output]\nmode="type"\ndriver_order=["dotool", "clipboard"]\n[whisper]\nmodel="base.en"\n'
        config.write_text(original)
        decide("python3", str(ROOT / "scripts/dictation_metadata.py"), "config", str(config), expected="whisper")
        assert config.read_text() == original
        config.write_text(original.replace('mode="type"', 'mode="clipboard"'))
        decide("python3", str(ROOT / "scripts/dictation_metadata.py"), "config", str(config), ok=False)
        config.write_text(original.replace('["dotool", "clipboard"]', '"dotool"'))
        decide("python3", str(ROOT / "scripts/dictation_metadata.py"), "config", str(config), ok=False)
        decide("python3", str(ROOT / "scripts/dictation_metadata.py"), "cuda-plan", "Inst libcublas-13-4 (13.8.0.4-1 NVIDIA:localhost [amd64])")
        decide("python3", str(ROOT / "scripts/dictation_metadata.py"), "cuda-plan", "Inst nvidia-driver-580 (580.65.06 NVIDIA:localhost [amd64])", ok=False)
        decide("python3", str(ROOT / "scripts/dictation_metadata.py"), "cuda-plan", "Remv libcudnn9-cuda-12 [9.0.0]", ok=False)
        marker = Path(temp) / "voxtype-source"
        decide("voxtype_release_owner_allowed", str(marker))
        marker.write_text("https://github.com/peteonrails/voxtype\n")
        decide("voxtype_release_owner_allowed", str(marker))
        marker.write_text("unrelated owner\n")
        decide("voxtype_release_owner_allowed", str(marker), ok=False)
    print("Dictation decisions passed; no installation, build, model, service or typing workflows executed")


if __name__ == "__main__":
    main()
