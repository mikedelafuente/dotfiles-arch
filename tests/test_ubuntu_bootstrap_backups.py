"""Exercise bootstrap backup decisions using temporary homes, without setup."""
from pathlib import Path
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
HELPER = (ROOT / "scripts/fn-lib.sh").read_text().split(
    "backup_ubuntu_bootstrap_dotfiles() {", 1)[1].split("\n}", 1)[0]
FUNCTION = "backup_ubuntu_bootstrap_dotfiles() {" + HELPER + "\n}\n"


class BootstrapBackups(unittest.TestCase):
    def run_backup(self, home, distro="ubuntu", fail_move=False):
        code = FUNCTION + "\nprint_info_message() { :; }\n"
        if fail_move:
            code += "mv() { return 1; }\n"
        code += 'USER_HOME_DIR="$1"; WORKSTATION_DISTRO="$2"; backup_ubuntu_bootstrap_dotfiles'
        return subprocess.run(["bash", "-eu", "-c", code, "backup-test", str(home), distro],
                              capture_output=True, text=True)

    def test_preserves_bytes_permissions_and_foreign_paths_on_retry(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            (home / ".bashrc").write_bytes(b"personal settings\n")
            (home / ".bashrc").chmod(0o640)
            (home / ".profile").write_text("profile\n")
            (home / ".inputrc").symlink_to("missing-foreign-target")
            (home / ".tmux.conf").mkdir()
            (home / ".gitconfig").write_text("identity")
            self.assertEqual(self.run_backup(home).returncode, 0)
            backup, = home.glob(".dfa-bootstrap-backup.*")
            self.assertEqual(backup.stat().st_mode & 0o777, 0o700)
            self.assertEqual((backup / ".bashrc").read_bytes(), b"personal settings\n")
            self.assertEqual((backup / ".bashrc").stat().st_mode & 0o777, 0o640)
            self.assertEqual((backup / ".profile").read_text(), "profile\n")
            self.assertTrue((home / ".inputrc").is_symlink())
            self.assertTrue((home / ".tmux.conf").is_dir())
            self.assertEqual((home / ".gitconfig").read_text(), "identity")
            self.assertEqual(self.run_backup(home).returncode, 0)
            self.assertEqual(len(list(home.glob(".dfa-bootstrap-backup.*"))), 1)

    def test_arch_and_existing_or_broken_deployments_are_untouched(self):
        for state in ("arch", "installed", "broken"):
            with self.subTest(state=state), tempfile.TemporaryDirectory() as tmp:
                home = Path(tmp)
                (home / ".bashrc").write_text("keep")
                if state != "arch":
                    config = home / ".local/share/workstation/config"
                    config.parent.mkdir(parents=True)
                    if state == "installed":
                        config.mkdir()
                    else:
                        config.symlink_to("missing")
                self.assertEqual(self.run_backup(home, "arch" if state == "arch" else "ubuntu").returncode, 0)
                self.assertEqual((home / ".bashrc").read_text(), "keep")
                self.assertFalse(list(home.glob(".dfa-bootstrap-backup.*")))

    def test_move_failure_reaches_caller(self):
        with tempfile.TemporaryDirectory() as tmp:
            home = Path(tmp)
            (home / ".profile").write_text("keep")
            self.assertNotEqual(self.run_backup(home, fail_move=True).returncode, 0)
            self.assertEqual((home / ".profile").read_text(), "keep")


if __name__ == "__main__":
    unittest.main()
