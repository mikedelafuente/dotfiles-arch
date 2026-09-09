package system

import (
	"bytes"
	"errors"
	"fmt"
	"os/exec"
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
