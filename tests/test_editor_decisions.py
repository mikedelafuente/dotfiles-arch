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

        for distro in ("arch", "ubuntu"):
            for app in ("zed", "orca"):
                decide("desktop_ide_selection", distro, app, "unknown", "1.23.2", ok=False)
                decide("desktop_ide_selection", distro, app, "conflict", "1.23.2", ok=False)
            decide("desktop_ide_selection", distro, "zed", "native", "1.18.0", expected="native")
            decide("desktop_ide_selection", distro, "zed", "native", "0.180.0", ok=False)
        decide("desktop_ide_selection", "ubuntu", "zed", "user", "1.23.2", expected="self")
        decide("desktop_ide_selection", "arch", "zed", "none", "", expected="native")
        decide("desktop_ide_selection", "ubuntu", "zed", "none", "", expected="self")
        decide("desktop_ide_selection", "arch", "orca", "none", "", expected="aur")
        decide("desktop_ide_selection", "ubuntu", "orca", "none", "", expected="self")
        decide("desktop_ide_selection", "ubuntu", "orca", "native", "1.4.223", expected="release-deb")
        decide("desktop_ide_selection", "ubuntu", "orca", "appimage", "1.4.223", expected="self")
        decide("desktop_ide_mime_allowed", "text/plain", "", "dev.zed.Zed.desktop")
        decide("desktop_ide_mime_allowed", "text/plain", "user.desktop", "dev.zed.Zed.desktop", ok=False)
        decide("desktop_ide_mime_allowed", "inode/directory", "", "dev.zed.Zed.desktop", ok=False)
        decide("desktop_ide_mime_allowed", "text/html", "", "dev.zed.Zed.desktop", ok=False)
        decide("desktop_ide_zed_version", "Zed 1.23.2 abc /tmp/zed", expected="1.23.2")
        for output in ("Zed 1.23.2-rc1", "Zed 0.180.0-dev", "unknown"):
            decide("desktop_ide_zed_version", output, ok=False)
        decide("desktop_ide_selection", "fedora", "zed", "none", "", ok=False)
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
        for app, version, repo, asset in (
            ("tree-sitter", "0.27.1", "tree-sitter/tree-sitter", "tree-sitter-linux-x64.gz"),
            ("lazydocker", "0.25.2", "jesseduffield/lazydocker", "lazydocker_0.25.2_Linux_x86_64.tar.gz"),
        ):
            official_url = f"https://github.com/{repo}/releases/download/v{version}/{asset}"
            official = {"tag_name": "v" + version, "prerelease": False, "draft": False,
                        "assets": [{"name": asset, "browser_download_url": official_url,
                                    "digest": "sha256:" + "b" * 64}]}
            decide("editor_release_asset", app, json.dumps(official),
                   expected=version + " " + official_url + " " + "b" * 64)
        for field, value in (("prerelease", True), ("draft", True),
                             ("tag_name", "nightly"), ("tag_name", "v0.11.6")):
            bad = dict(release, **{field: value})
            decide("editor_release_asset", "nvim", json.dumps(bad), ok=False)
        for field, value in (("digest", None), ("digest", "sha256:bad"),
                             ("browser_download_url", "https://example.com/asset"),
                             ("name", "nvim-linux-arm64.tar.gz")):
            bad = dict(release, assets=[dict(release["assets"][0], **{field: value})])
            decide("editor_release_asset", "nvim", json.dumps(bad), ok=False)
        for app, version, repo, asset in (
            ("zed", "1.23.2", "zed-industries/zed", "zed-linux-x86_64.tar.gz"),
            ("orca", "1.4.223", "stablyai/orca", "orca-linux.AppImage"),
            ("orca-deb", "1.4.223", "stablyai/orca", "orca-ide_1.4.223_amd64.deb"),
        ):
            url = f"https://github.com/{repo}/releases/download/v{version}/{asset}"
            release = {"tag_name": "v" + version, "prerelease": False, "draft": False,
                       "assets": [{"name": asset, "browser_download_url": url,
                                   "digest": "sha256:" + "c" * 64}]}
            decide("desktop_ide_release_asset", app, json.dumps(release),
                   expected=version + " " + url + " " + "c" * 64)
            for field, value in (("digest", None), ("digest", "sha256:bad"),
                                 ("browser_download_url", "https://example.com/asset"),
                                 ("name", "wrong-architecture")):
                bad = dict(release, assets=[dict(release["assets"][0], **{field: value})])
                decide("desktop_ide_release_asset", app, json.dumps(bad), ok=False)
            for field, value in (("prerelease", True), ("draft", True), ("tag_name", "nightly")):
                decide("desktop_ide_release_asset", app, json.dumps(dict(release, **{field: value})), ok=False)
        # Alias resolution reads only supplied executables and detects a split source.
        for name in ("zed", "zeditor"):
            (guard / name).symlink_to("../supplied-zed")
        (Path(temp) / "supplied-zed").write_text("supplied executable fact")
        (Path(temp) / "supplied-zed").chmod(0o755)
        decide("desktop_ide_command", "zed", expected=str(Path(temp) / "supplied-zed"))
        (guard / "zed").unlink()
        (guard / "zed").write_text("#!/bin/sh\nexit 97\n")
        (guard / "zed").chmod(0o755)
        decide("desktop_ide_command", "zed", ok=False)
        for name in ("zed", "zeditor"):
            (guard / name).unlink()
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
