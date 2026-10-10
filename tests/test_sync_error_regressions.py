"""Reproduce sync failures using supplied facts; never change the workstation."""
import io
import os
from pathlib import Path
import runpy
import subprocess
import tarfile
import tempfile

ROOT = Path(os.environ.get("DFA_TEST_ROOT", Path(__file__).resolve().parents[1]))


def main():
    failures = []
    with tempfile.TemporaryDirectory(prefix="sync-errors-") as temp:
        env = dict(os.environ, DF_SCRIPT_DIR=str(ROOT / "scripts"), USER_HOME_DIR=temp,
                   HOME=temp, WORKSTATION_DISTRO="arch", CARGO_HOME=temp + "/cargo",
                   RUSTUP_HOME=temp + "/rustup")
        env.pop("RUSTUP_TOOLCHAIN", None)

        def check(name, code, expected=0):
            result = subprocess.run(["bash", "-eu", "-o", "pipefail", "-c",
                                     'source "$DF_SCRIPT_DIR/fn-lib.sh";\n' + code],
                                    env=env, capture_output=True, text=True)
            if result.returncode != expected:
                failures.append(f"{name}: status={result.returncode}: {result.stdout + result.stderr}")

        check("official sh provider is not AUR", '''
pacman() {
  case "$*" in
    '-Si sh') return 1 ;;
    '-Sp --print-format %r -- sh') echo core ;;
    *) return 97 ;;
  esac
}
aur_fetch_pkgbuild() {
  [[ "$1" == chatgpt-desktop ]] || return 97
  printf '# clean package\\n' >"$2/PKGBUILD"
  printf 'depends = sh\\n' >"$2/.SRCINFO"
}
aur_scan_package_tree chatgpt-desktop
''')
        check("real AUR dependency still scanned", '''
pacman() { return 1; }
aur_fetch_pkgbuild() {
  printf '# clean package\\n' >"$2/PKGBUILD"
  if [[ "$1" == root ]]; then printf 'depends = unsafe\\n' >"$2/.SRCINFO"
  else printf ' eval bad\\n' >"$2/PKGBUILD"; : >"$2/.SRCINFO"; fi
}
aur_scan_package_tree root
''', 1)
        # Force the producer to write after grep finds its early match. A quiet
        # grep then causes SIGPIPE under pipefail, just as a large schema can.
        settings = r'''
gnome_extension_path() { echo "$USER_HOME_DIR/missing"; }
gsettings() {
  if [[ "$1" == list-keys ]]; then
    python3 -c 'import os, signal; signal.signal(signal.SIGPIPE, signal.SIG_DFL); os.write(1, b"intellihide-key-toggle\n"); [os.write(1, b"other-key\n" * 10000) for _ in range(20)]'
  elif [[ "$1" == set ]]; then printf '%s\n' "$*" >"$USER_HOME_DIR/settings-call"
  else return 97; fi
}
'''
        check("panel key exists despite large schema", settings + '''
gnome_extension_setting panel org.gnome.shell.extensions.dash-to-panel intellihide-key-toggle '[]'
[[ -f "$USER_HOME_DIR/settings-call" ]]
''')
        check("missing required setting still fails", settings + '''
gnome_extension_setting panel schema missing-key '[]'
''', 1)
        rust = (ROOT / "scripts/setup-rust.sh").read_text().split('print_tool_setup_start "Rust and Cargo"', 1)[1]
        stubs = '''
language_user_path_allowed() { return 0; }
language_rust_owner() { echo user-rustup; }
ensure_language_packages() { return 0; }
language_installed_version() { echo 1.90.0; }
rustup() {
  if [[ "$*" == default ]]; then
    printf '%s\\n' "$RUST_DEFAULT_FACT"
    [[ "$RUST_DEFAULT_FACT" != error:* ]]
  elif [[ "$*" == 'default stable' ]]; then
    echo initialized >"$USER_HOME_DIR/rust-call"
  else return 97; fi
}
'''
        for diagnostic in ("error: no default toolchain is configured", "error: no default toolchain configured"):
            check(diagnostic, stubs + f"RUST_DEFAULT_FACT='{diagnostic}'\n" + rust + '\n[[ -f "$USER_HOME_DIR/rust-call" ]]')
        (Path(temp) / "rust-call").unlink(missing_ok=True)
        check("nightly default retained", stubs + "RUST_DEFAULT_FACT='nightly-x86_64-unknown-linux-gnu (default)'\n" + rust + '\n[[ ! -e "$USER_HOME_DIR/rust-call" ]]')
        check("unrelated rustup error still fails", stubs + "RUST_DEFAULT_FACT='error: permission denied'\n" + rust, 1)

        rebind = '''
gnome-shell() { echo "GNOME Shell $SHELL_FACT"; }
gsettings() {
  case "$1" in
    list-keys) printf '%s\\n' tile-by-default pop-monitor-{left,right,up,down} tile-move-{left,right,up,down}-global ;;
    get) echo true ;;
    set) printf '%s\\n' "$*" >>"$USER_HOME_DIR/rebind-calls" ;;
    *) return 97 ;;
  esac
}
(source "$DF_SCRIPT_DIR/../home/.local/bin/rebind-window-push")
'''
        check("GNOME 51 keeps tiled window push", "SHELL_FACT=51.0\n" + rebind + '''
grep -F "tile-move-left-global ['<Primary><Super>Left']" "$USER_HOME_DIR/rebind-calls"
''')
        (Path(temp) / "rebind-calls").unlink(missing_ok=True)
        check("newer shell keeps native fallback", "SHELL_FACT=52.0\n" + rebind + '''
! grep -F 'extensions.pop-shell' "$USER_HOME_DIR/rebind-calls"
grep -F "toggle-tiled-left ['<Primary><Super>Left']" "$USER_HOME_DIR/rebind-calls"
''')
        (Path(temp) / "rebind-calls").unlink(missing_ok=True)
        check("Ubuntu keeps native moves without Pop, including autostart", "WORKSTATION_DISTRO=ubuntu\nSHELL_FACT=50.1\n" +
              rebind.replace('rebind-window-push")', 'rebind-window-push" --watch)') + '''
! grep -F 'extensions.pop-shell' "$USER_HOME_DIR/rebind-calls"
grep -F "toggle-tiled-left ['<Primary><Super>Left']" "$USER_HOME_DIR/rebind-calls"
grep -F "move-to-monitor-left ['<Primary><Super>Up']" "$USER_HOME_DIR/rebind-calls"
''')

        stage = runpy.run_path(str(ROOT / "scripts/gnome_desktop.py"))["stage_extension"]
        archive = Path(temp) / "pop.tar"
        with tarfile.open(archive, "w") as output:
            for name, data in (("pop/metadata.json", b'{}'), ("pop/src/config.ts", b'// shared config')):
                member = tarfile.TarInfo(name)
                member.size = len(data)
                output.addfile(member, io.BytesIO(data))
            member = tarfile.TarInfo("pop/src/floating_exceptions/src/config.ts")
            member.type = tarfile.SYMTYPE
            member.linkname = "../../config.ts"
            output.addfile(member)
        dest = Path(temp) / "stage"
        try:
            stage("tar", archive, dest)
            copied = dest / "src/floating_exceptions/src/config.ts"
            assert not copied.is_symlink() and copied.read_bytes() == b'// shared config'
        except ValueError as error:
            failures.append(f"Pop Shell internal source link: {error}")
        for link in ("../../../escape", "/absolute", "../../../../pop/src/config.ts"):
            with tarfile.open(archive, "w") as output:
                member = tarfile.TarInfo("pop/metadata.json")
                member.size = 2
                output.addfile(member, io.BytesIO(b'{}'))
                member = tarfile.TarInfo("pop/src/link")
                member.type = tarfile.SYMTYPE
                member.linkname = link
                output.addfile(member)
            try:
                stage("tar", archive, Path(temp) / ("bad-" + str(len(failures)) + str(len(link))))
            except ValueError:
                pass
            else:
                failures.append(f"Unsafe archive link accepted: {link}")
    assert not failures, "\n".join(failures)
    print("Sync error regressions passed (offline; unsafe inputs still rejected)")


if __name__ == "__main__":
    main()
