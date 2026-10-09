"""Supplied editor facts only; no setup, updates, network, or live editor launch."""
from pathlib import Path
import os
import json
import shlex
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    with tempfile.TemporaryDirectory(prefix="editor-decisions-") as temp:
        guard = Path(temp) / "bin"
        guard.mkdir()
        for name in ("sudo", "pacman", "yay", "apt", "apt-get", "apt-cache",
                     "dpkg", "dpkg-query", "curl", "wget", "git", "npm",
                     "systemctl", "gsettings", "nvim", "tmux", "lazydocker"):
            script = guard / name
            script.write_text('#!/bin/sh\necho "Forbidden command" >&2\nexit 97\n')
            script.chmod(0o755)
        env = dict(os.environ, DF_SCRIPT_DIR=str(ROOT / "scripts"),
                   USER_HOME_DIR=temp, PATH=str(guard) + os.pathsep + os.environ["PATH"])

        def decide(*args, expected="", ok=True):
            command = shlex.join(args)
            result = subprocess.run(
                ["bash", "-eu", "-o", "pipefail", "-c",
                 'source "$DF_SCRIPT_DIR/fn-lib.sh"; ' + command],
                env=env, capture_output=True, text=True,
            )
            assert "Forbidden command" not in result.stdout + result.stderr
            assert result.returncode == (0 if ok else 1), result.stdout + result.stderr
            if ok:
                assert result.stdout.strip() == expected, result.stdout

        decide("editor_tool_selection", "ubuntu", "nvim", "none", "", "0.11.6",
               expected="upstream")
        for distro in ("arch", "ubuntu"):
            decide("editor_tool_selection", distro, "nvim", "native", "0.12.0", "0.12.5",
                   expected="native")
            decide("editor_tool_selection", distro, "nvim", "native", "0.11.6", "0.12.5", ok=False)
            decide("editor_tool_selection", distro, "tree-sitter", "none", "", "0.25.9",
                   expected="upstream")
            decide("editor_tool_selection", distro, "tree-sitter", "none", "", "0.26.1",
                   expected="native")
            decide("editor_tool_selection", distro, "tree-sitter", "native", "0.26.0", "", ok=False)
            decide("editor_tool_selection", distro, "nvim", "upstream", "0.12.0", "0.13.0",
                   expected="upstream")
            decide("editor_tool_selection", distro, "nvim", "unknown", "0.12.5", "0.12.5", ok=False)
            decide("editor_tool_selection", distro, "lazydocker", "none", "", "",
                   expected="upstream")
            decide("editor_tool_selection", distro, "tmux", "none", "", "3.6.0", expected="native")
            decide("editor_tool_selection", distro, "tmux", "none", "", "", ok=False)
        for app, output, expected in (("nvim", "NVIM v0.12.5\nBuild type: Release", "0.12.5"),
                                      ("tree-sitter", "tree-sitter 0.26.1 (8a3dcc6)", "0.26.1"),
                                      ("tmux", "tmux 3.6a", "3.6.0"),
                                      ("lazydocker", "Version: 0.25.2\nGit commit: abc", "0.25.2")):
            decide("editor_tool_version", app, output, expected=expected)
        for output in ("NVIM v0.12.0-dev-abc", "NVIM v0.12.0-rc1", "unknown", "$(exit 97)"):
            decide("editor_tool_version", "nvim", output, ok=False)
        for package, expected in (("0.11.6-1", "0.11.6"), ("1:0.12.5-2ubuntu1", "0.12.5"),
                                  ("3.6a-2ubuntu0.1", "3.6.0"), ("0.26.1+ds-1", "0.26.1")):
            decide("editor_package_version", package, expected=expected)
        for package in ("(none)", "0.12.0~rc1-1", "0.12.0-dev-1", "garbage"):
            decide("editor_package_version", package, ok=False)
        url = "https://github.com/neovim/neovim-releases/releases/download/v0.12.5/nvim-linux-x86_64.tar.gz"
        release = {"tag_name": "v0.12.5", "prerelease": False, "draft": False,
                   "assets": [{"name": "nvim-linux-x86_64.tar.gz", "browser_download_url": url,
                               "digest": "sha256:" + "a" * 64}]}
        decide("editor_release_asset", "nvim", json.dumps(release),
               expected="0.12.5 " + url + " " + "a" * 64)
        for field, value in (("prerelease", True), ("draft", True),
                             ("tag_name", "nightly"), ("tag_name", "v0.11.6")):
            bad = dict(release, **{field: value})
            decide("editor_release_asset", "nvim", json.dumps(bad), ok=False)
        for field, value in (("digest", None), ("digest", "sha256:bad"),
                             ("browser_download_url", "https://example.com/asset"),
                             ("name", "nvim-linux-arm64.tar.gz")):
            bad = dict(release, assets=[dict(release["assets"][0], **{field: value})])
            decide("editor_release_asset", "nvim", json.dumps(bad), ok=False)
        root = Path(temp) / ".local/share/dotfiles-arch/editor-tools/nvim"
        launcher = Path(temp) / ".local/bin/nvim"
        decide("editor_upstream_layout_allowed", "nvim", str(root), str(launcher))
        root.mkdir(parents=True)
        decide("editor_upstream_layout_allowed", "nvim", str(root), str(launcher), ok=False)
        (root / ".dfa-source").write_text("neovim/neovim-releases\n")
        (root / "0.12.5/bin").mkdir(parents=True)
        binary = root / "0.12.5/bin/nvim"
        binary.write_text("supplied binary fact")
        (root / "current").symlink_to("0.12.5")
        launcher.parent.mkdir(parents=True)
        launcher.symlink_to(root / "current/bin/nvim")
        decide("editor_upstream_layout_allowed", "nvim", str(root), str(launcher))
        launcher.unlink()
        launcher.write_text("user command")
        decide("editor_upstream_layout_allowed", "nvim", str(root), str(launcher), ok=False)
        launcher.unlink()
        (root / "current").unlink()
        (root / "current").symlink_to("../unrelated")
        decide("editor_upstream_layout_allowed", "nvim", str(root), str(launcher), ok=False)
        config = Path(temp) / "repo-config"
        config.mkdir()
        (config / "init.lua").write_text("repo config")
        target = Path(temp) / "user-config"
        target.mkdir()
        (target / "user.lua").write_text("keep user addition")
        decide("editor_config_allowed", str(config), str(target))
        (target / "init.lua").symlink_to(config / "init.lua")
        decide("editor_config_allowed", str(config), str(target))
        (target / "init.lua").unlink()
        (target / "init.lua").write_text("repo config")
        decide("editor_config_allowed", str(config), str(target))
        (target / "init.lua").write_text("user customization")
        before = (target / "init.lua").read_bytes()
        decide("editor_config_allowed", str(config), str(target), ok=False)
        assert (target / "init.lua").read_bytes() == before
    print("Editor decisions passed (no setup/update/launch workflows executed)")


if __name__ == "__main__":
    main()
