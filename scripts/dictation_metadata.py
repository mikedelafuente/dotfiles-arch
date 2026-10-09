"""Read-only dictation config, source/build plans and runtime prerequisites."""
import ctypes
import os
from pathlib import Path
import sys
import tomllib


def config(path):
    with Path(path).open("rb") as stream:
        data = tomllib.load(stream)
    engine = data.get("engine", "whisper")
    if not isinstance(engine, str) or engine not in {"whisper", "parakeet"}:
        raise ValueError("existing engine requires an explicit supported backend choice; config retained")
    output, hotkey = data.get("output", {}), data.get("hotkey", {})
    if not isinstance(output, dict) or not isinstance(hotkey, dict) or not isinstance(data.get(engine, {}), dict):
        raise ValueError("malformed config sections; config retained")
    drivers = output.get("driver_order", [])
    if (hotkey.get("enabled", True) is not False or output.get("mode", "type") != "type"
            or not isinstance(drivers, list) or "dotool" not in drivers):
        raise ValueError("GNOME toggle requires hotkey.enabled=false and output.mode=type with dotool; config retained")
    return engine, data


def user_paths(home):
    """Do not repair ownership by recursively chowning existing real trees."""
    root = Path(home)
    for variable, relative in (("XDG_CONFIG_HOME", ".config"), ("XDG_DATA_HOME", ".local/share")):
        override = Path(os.environ.get(variable, ""))
        base = override if override.is_absolute() else root / relative
        for path in (base / "voxtype", base):
            if path.is_symlink():
                raise ValueError(f"user path link retained: {path}; resolve config/model owner explicitly")
            if path.exists() and (not path.is_dir() or path.stat().st_uid != os.getuid() or not os.access(path, os.W_OK)):
                raise ValueError(f"user path owner/access conflict retained: {path}")


def model(path, home):
    engine, data = config(path)
    name = data.get(engine, {}).get("model", "base.en" if engine == "whisper" else "parakeet-tdt-0.6b-v3")
    if not isinstance(name, str) or not name:
        raise ValueError("missing configured model; config retained")
    override = Path(os.environ.get("XDG_DATA_HOME", ""))
    models = (override if override.is_absolute() else Path(home) / ".local/share") / "voxtype/models"
    if engine == "whisper":
        candidate = models / name if name.endswith(".bin") else models / f"ggml-{name}.bin"
        if not candidate.is_file() or candidate.stat().st_size < 1_000_000:
            raise ValueError(f"Whisper model missing/incomplete: {candidate}; run voxtype setup --download --model {name!r} --no-post-install as your user")
    else:
        candidate = Path(name) if name.startswith("/") else models / name
        def present(*names):
            return any((candidate / file).is_file() and (candidate / file).stat().st_size > 0 for file in names)
        if not candidate.is_dir() or not present("vocab.txt") or not (
                present("model.onnx", "model.int8.onnx") or (
                    present("encoder-model.onnx", "encoder-model.int8.onnx")
                    and present("decoder_joint-model.onnx", "decoder_joint-model.int8.onnx"))):
            raise ValueError(f"Parakeet model missing/incomplete: {candidate}; download your selected model explicitly as your user; config retained")
    # Presence is a prerequisite, not verification of model inference/integrity.


def cuda_plan(text):
    allowed = {"cuda-cudart-13-4", "libcublas-13-4", "libcufft-13-4", "libcurand-13-4", "libcudnn9-cuda-13",
               "cuda-toolkit-config-common", "cuda-toolkit-13-config-common", "cuda-toolkit-13-4-config-common",
               "libc6", "libgcc-s1", "libstdc++6", "zlib1g"}
    for line in text.splitlines():
        if line.startswith("Remv "):
            raise ValueError("CUDA runtime plan removes packages; preserve managed software")
        if line.startswith("Inst "):
            package = line.split()[1].split(":")[0]
            if package not in allowed:
                raise ValueError(f"CUDA runtime plan changes unexpected package {package}; preserve drivers/toolkits")


def runtime(variant, binary):
    if variant.startswith("voxtype-onnx-"):
        libc = ctypes.CDLL(None)
        libc.gnu_get_libc_version.restype = ctypes.c_char_p
        version = tuple(map(int, libc.gnu_get_libc_version().decode().split(".")))
        if version < (2, 39):
            raise ValueError("ONNX binaries require glibc 2.39+")
    if variant == "voxtype-vulkan":
        ctypes.CDLL("libvulkan.so.1")
    if variant in {"voxtype-onnx-cuda-12", "voxtype-onnx-cuda-13"}:
        major = int(variant.rsplit("-", 1)[1])
        directory = Path(binary).resolve(strict=True).parent
        if directory.name != f"cuda-{major}":
            raise ValueError("CUDA binary/providers must be co-located in their canonical package directory")
        cudart = ctypes.CDLL(f"libcudart.so.{major}", mode=ctypes.RTLD_GLOBAL)
        version = ctypes.c_int()
        if cudart.cudaRuntimeGetVersion(ctypes.byref(version)) != 0 or version.value // 1000 != major:
            raise ValueError(f"CUDA{major} runtime ABI unavailable")
        cudnn = ctypes.CDLL("libcudnn.so.9", mode=ctypes.RTLD_GLOBAL)
        cudnn.cudnnGetVersion.restype = ctypes.c_size_t
        if not 90000 <= cudnn.cudnnGetVersion() < 100000:
            raise ValueError("CUDA backend requires cuDNN9")
        for soname in (f"libcublas.so.{major}", f"libcublasLt.so.{major}",
                       "libcufft.so.12" if major == 13 else "libcufft.so.11", "libcurand.so.10"):
            ctypes.CDLL(soname, mode=ctypes.RTLD_GLOBAL)
        if major == 13:
            ctypes.CDLL(str(directory / "libonnxruntime.so"), mode=ctypes.RTLD_GLOBAL)
        for soname in ("libonnxruntime_providers_shared.so", "libonnxruntime_providers_cuda.so"):
            ctypes.CDLL(str(directory / soname), mode=ctypes.RTLD_GLOBAL)


def main():
    try:
        action, *args = sys.argv[1:]
        if action == "config":
            print(config(*args)[0])
        elif action == "paths":
            user_paths(*args)
        elif action == "model":
            model(*args)
        elif action == "cuda-plan":
            cuda_plan(*args)
        elif action == "runtime":
            runtime(*args)
        else:
            raise ValueError("unknown dictation metadata action")
    except (ValueError, OSError, KeyError, AttributeError, tomllib.TOMLDecodeError) as error:
        print(f"Dictation prerequisite/source conflict: {error}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
