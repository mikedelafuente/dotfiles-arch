package system

import (
	"bytes"
	"errors"
	"fmt"
	"os"
	"os/exec"
	"path/filepath"
)

// Result captures the outcome of running an external command: its captured
// stdout/stderr and its process exit code.
type Result struct {
	Stdout   string
	Stderr   string
	ExitCode int
}

// Run executes an external command with the given arguments and captures its
// stdout, stderr, and exit status.
//
// A non-zero exit code from a command that ran successfully (e.g. "false")
// is reported via Result.ExitCode, not as a Go error — err is reserved for
// failures to even start/run the command (e.g. the binary isn't found).
// This mirrors exec.Cmd's own *exec.ExitError distinction and keeps the
// common "command ran, check its exit code" path free of error-unwrapping.
func Run(name string, args ...string) (Result, error) {
	cmd := exec.Command(name, args...)

	var stdout, stderr bytes.Buffer
	cmd.Stdout = &stdout
	cmd.Stderr = &stderr

	err := cmd.Run()
	result := Result{
		Stdout: stdout.String(),
		Stderr: stderr.String(),
	}

	if err != nil {
		var exitErr *exec.ExitError
		if errors.As(err, &exitErr) {
			result.ExitCode = exitErr.ExitCode()
			return result, nil
		}
		return result, fmt.Errorf("running %q: %w", name, err)
	}

	result.ExitCode = 0
	return result, nil
}

// RunScript runs a dotfiles-arch setup-*.sh script (via bash) with the given
// arguments, capturing its output the same way Run does.
func RunScript(scriptPath string, args ...string) (Result, error) {
	return Run("bash", append([]string{scriptPath}, args...)...)
}

// QueryPackagesInstalled reports whether every named pacman package is
// currently installed on this machine. An empty package list is trivially
// "installed" (there's nothing to check).
func QueryPackagesInstalled(pkgs []string) (bool, error) {
	if len(pkgs) == 0 {
		return true, nil
	}
	result, err := Run("pacman", append([]string{"-Q"}, pkgs...)...)
	if err != nil {
		return false, err
	}
	return result.ExitCode == 0, nil
}

// FindRepoRoot walks up from startDir looking for the dotfiles-arch repo
// root, identified the same way dotfiles-arch-lib.sh's resolve_dotfiles_arch
// identifies it from installed ~/.local/bin helpers: the presence of
// scripts/sync.sh.
func FindRepoRoot(startDir string) (string, error) {
	dir := startDir
	for {
		if isRepoRoot(dir) {
			return dir, nil
		}
		parent := filepath.Dir(dir)
		if parent == dir {
			return "", fmt.Errorf("system: could not find dotfiles-arch repo root above %s", startDir)
		}
		dir = parent
	}
}

// isRepoRoot reports whether dir looks like a dotfiles-arch checkout (the
// same marker FindRepoRoot walks up looking for).
func isRepoRoot(dir string) bool {
	fi, err := os.Stat(filepath.Join(dir, "scripts", "sync.sh"))
	return err == nil && !fi.IsDir()
}

// ResolveRepoRoot finds the dotfiles-arch checkout dfa is running against,
// mirroring dotfiles-arch-lib.sh's resolve_dotfiles_arch: walk up from
// startDir (the running binary's own location — when the binary lives
// inside a checkout, e.g. `go run`/`go test`, or a dev symlink), then
// $DOTFILES_ARCH, then a fixed list of common clone paths. This is what
// lets an installed ~/.local/bin/dfa binary — which no longer lives inside
// the repo — find it.
func ResolveRepoRoot(startDir string) (string, error) {
	if root, err := FindRepoRoot(startDir); err == nil {
		return root, nil
	}

	if env := os.Getenv("DOTFILES_ARCH"); env != "" && isRepoRoot(env) {
		return env, nil
	}

	home, herr := os.UserHomeDir()
	if herr == nil {
		for _, candidate := range []string{
			filepath.Join(home, "repos", "dotfiles-arch"),
			filepath.Join(home, "repos", "mikedelafuente", "dotfiles-arch"),
			filepath.Join(home, "dotfiles-arch"),
			filepath.Join(home, "src", "dotfiles-arch"),
		} {
			if isRepoRoot(candidate) {
				return candidate, nil
			}
		}
	}

	return "", fmt.Errorf("system: could not locate the dotfiles-arch repo (checked %s, $DOTFILES_ARCH, and common clone paths)", startDir)
}
