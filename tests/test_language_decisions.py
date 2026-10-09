"""Supplied language facts only; never execute setup/update workflows."""
from pathlib import Path
import os
import shlex
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[1]


def main():
    with tempfile.TemporaryDirectory(prefix="language-decisions-") as temp:
        guard = Path(temp) / "bin"
        guard.mkdir()
        for name in ("sudo", "pacman", "yay", "apt", "apt-get", "apt-cache",
                     "dpkg", "dpkg-query", "curl", "wget", "git", "npm", "node",
                     "rustup", "rustc", "cargo", "go", "gopls", "php", "composer",
                     "ruby", "gem", "bundle", "rails", "systemctl", "gsettings"):
            script = guard / name
            script.write_text('#!/bin/sh\necho "Forbidden command" >&2\nexit 97\n')
            script.chmod(0o755)
        env = dict(os.environ, DF_SCRIPT_DIR=str(ROOT / "scripts"),
                   USER_HOME_DIR=temp, HOME=temp,
                   PATH=str(guard) + os.pathsep + os.environ["PATH"])

        def decide(*args, expected="", ok=True, diagnostic=""):
            result = subprocess.run(
                ["bash", "-eu", "-o", "pipefail", "-c",
                 'source "$DF_SCRIPT_DIR/fn-lib.sh"; ' + shlex.join(args)],
                env=env, capture_output=True, text=True,
            )
            assert "Forbidden command" not in result.stdout + result.stderr
            assert result.returncode == (0 if ok else 1), result.stdout + result.stderr
            if ok:
                assert result.stdout.strip() == expected, result.stdout
            if diagnostic:
                assert diagnostic in result.stdout + result.stderr

        decide("language_packages", "ubuntu", "python",
               expected="python3 python3-pip python3-venv python3-pynvim python3-dev")
        decide("language_packages", "arch", "python",
               expected="python python-pip python-pynvim")
        decide("language_packages", "ubuntu", "go", expected="golang-go gopls")
        decide("language_packages", "fedora", "python", ok=False)
        decide("language_packages", "ubuntu", "unknown", ok=False)
        decide("language_command_package", "ubuntu", "php", expected="php-cli")
        decide("composer_source_selection", "ubuntu", "false", "", "false", expected="self")
        decide("composer_source_selection", "arch", "false", "", "false", expected="native")
        decide("composer_source_selection", "ubuntu", "true", "/usr/bin/composer", "false", expected="native")
        decide("composer_source_selection", "ubuntu", "false", "self", "true", expected="self")
        decide("composer_source_selection", "ubuntu", "true", "self", "true", ok=False)
        for command, output, version in (
            ("python3", "Python 3.14.0", "3.14.0"),
            ("go", "go version go1.26 linux/amd64", "1.26.0"),
            ("gopls", "golang.org/x/tools/gopls v0.20.0", "0.20.0"),
            ("php", "PHP 8.5.4 (cli) (built: example)", "8.5.4"),
            ("ruby", "ruby 3.3.8 (2025-04-09 revision abc) [x86_64-linux]", "3.3.8"),
            ("rustc", "rustc 1.90.0 (abc 2025-09-14)", "1.90.0"),
            ("cargo", "cargo 1.90.0 (abc 2025-09-14)", "1.90.0"),
            ("rustc", "rustc 1.92.0-nightly (abc 2025-09-14)", "1.92.0"),
            ("composer", "Composer version 2.8.0 2025-01-01", "2.8.0"),
        ):
            decide("language_command_version", command, output, expected=version)
        for command, output in (("go", "go version devel go1.27-abc linux/amd64"),
                                ("ruby", "ruby 3.5.0preview1"),
                                ("rustc", "rustc 1.90.0-unknown"),
                                ("php", "PHP 8.6.0RC1"), ("python3", "Python 3.14.0rc1")):
            decide("language_command_version", command, output, ok=False)
        for distro in ("arch", "ubuntu"):
            decide("rust_manager_selection", distro, "none", expected="user-rustup" if distro == "ubuntu" else "native-rustup")
            decide("rust_manager_selection", distro, "native-rustup", expected="native-rustup")
            decide("rust_manager_selection", distro, "user-rustup", expected="user-rustup")
            decide("rust_toolchain_selection", distro, "none", "", "", "", expected="initialize")
            decide("rust_toolchain_selection", distro, "native-rustup", "", "", "", expected="initialize")
            decide("rust_toolchain_selection", distro, "user-rustup", "nightly", "1.90.0", "1.90.0",
                   expected="retain")
            decide("rust_toolchain_selection", distro, "native", "", "1.90.0", "1.90.0",
                   expected="retain")
            decide("rust_toolchain_selection", distro, "native", "", "1.60.0", "1.90.0",
                   expected="retain")
            decide("rust_toolchain_selection", distro, "native", "", "unknown", "1.90.0", ok=False)
            decide("rust_toolchain_selection", distro, "conflict", "", "1.90.0", "1.90.0", ok=False)
        decide("php_configuration_paths", "arch", "8.5.4",
               expected="/etc/php/php.ini /etc/php/conf.d")
        decide("php_configuration_paths", "ubuntu", "8.5.4",
               expected="/etc/php/8.5/cli/php.ini /etc/php/8.5/cli/conf.d")
        decide("php_configuration_paths", "ubuntu", "8.5.4/../../etc", ok=False)
        modules = "\n".join(("ctype", "curl", "dom", "fileinfo", "filter", "hash", "mbstring",
                             "openssl", "pcre", "PDO", "session", "tokenizer", "xml", "iconv",
                             "mysqli", "pdo_mysql", "pdo_sqlite", "sqlite3", "gd", "intl",
                             "pgsql", "pdo_pgsql"))
        decide("php_modules_allowed", modules)
        decide("php_modules_allowed", modules.replace("pdo_mysql\n", "pdo_mysql_extra\n"),
               ok=False, diagnostic="pdo_mysql")
        decide("language_user_path_allowed", temp, temp + "/.gem/ruby/3.3.0")
        decide("language_user_path_allowed", temp, "/var/lib/gems", ok=False)
        decide("language_user_path_allowed", temp, temp + "-other/bin", ok=False)
        decide("language_user_path_allowed", temp, temp + "/../system/bin", ok=False)
        linked = Path(temp) / "linked"
        linked.symlink_to(guard, target_is_directory=True)
        decide("language_user_path_allowed", temp, str(linked / "gems"), ok=False)
        gem_home = Path(temp) / ".gem/ruby/3.3.0"
        gem_home.mkdir(parents=True)
        (gem_home / "bin").symlink_to(guard, target_is_directory=True)
        decide("language_user_path_allowed", temp, str(gem_home / "bin"), ok=False)
        launcher = Path(temp) / "bundle"
        decide("language_user_launcher_allowed", str(launcher))
        launcher.write_text("user-owned executable fact")
        decide("language_user_launcher_allowed", str(launcher))
        launcher.unlink()
        launcher.symlink_to(guard / "bundle")
        decide("language_user_launcher_allowed", str(launcher), ok=False)
        decide("language_user_tool_selection", temp + "/.gem/bin/bundle", "", "false", expected="user")
        decide("language_user_tool_selection", temp + "/.gem/bin/bundle", temp + "/.gem/bin/bundle",
               "false", expected="user")
        decide("language_user_tool_selection", temp + "/.gem/bin/bundle", "/usr/bin/bundle", "true",
               expected="native")
        decide("language_user_tool_selection", temp + "/.gem/bin/bundle", "/snap/bin/bundle", "false", ok=False)
        for entrypoint in ("setup-python.sh", "setup-rust.sh", "setup-golang.sh",
                           "setup-php.sh", "setup-ruby.sh"):
            decide("require_workstation_entrypoint", "ubuntu", entrypoint)
    print("Language decisions passed (no setup/update workflows executed)")


if __name__ == "__main__":
    main()
