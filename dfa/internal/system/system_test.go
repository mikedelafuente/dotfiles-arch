// Package system provides the System Adapter primitive: a thin wrapper for
// running external commands/scripts and capturing their output and exit
// status. Later work builds the catalog/install engine on top of this seam.
package system

import (
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestRun_TableDriven(t *testing.T) {
	tests := []struct {
		name       string
		cmd        string
		args       []string
		wantStdout string
		wantStderr string
		wantExit   int
		wantErr    bool
	}{
		{
			name:       "echo captures stdout",
			cmd:        "echo",
			args:       []string{"hello dfa"},
			wantStdout: "hello dfa\n",
			wantExit:   0,
		},
		{
			name:     "true exits zero",
			cmd:      "true",
			wantExit: 0,
		},
		{
			name:     "false exits non-zero without a Go error",
			cmd:      "false",
			wantExit: 1,
		},
		{
			name:       "stderr is captured separately from stdout",
			cmd:        "sh",
			args:       []string{"-c", "echo out; echo err 1>&2"},
			wantStdout: "out\n",
			wantStderr: "err\n",
			wantExit:   0,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result, err := Run(tt.cmd, tt.args...)
			if tt.wantErr {
				if err == nil {
					t.Fatalf("Run(%q, %v) expected error, got nil", tt.cmd, tt.args)
				}
				return
			}
			if err != nil {
				t.Fatalf("Run(%q, %v) unexpected error: %v", tt.cmd, tt.args, err)
			}
			if result.Stdout != tt.wantStdout {
				t.Errorf("Stdout = %q, want %q", result.Stdout, tt.wantStdout)
			}
			if result.Stderr != tt.wantStderr {
				t.Errorf("Stderr = %q, want %q", result.Stderr, tt.wantStderr)
			}
			if result.ExitCode != tt.wantExit {
				t.Errorf("ExitCode = %d, want %d", result.ExitCode, tt.wantExit)
			}
		})
	}
}

func TestRun_NonexistentCommand(t *testing.T) {
	result, err := Run("dfa-this-command-does-not-exist-anywhere")
	if err == nil {
		t.Fatalf("Run(nonexistent command) expected error, got nil (result: %+v)", result)
	}
	if !strings.Contains(err.Error(), "dfa-this-command-does-not-exist-anywhere") {
		t.Errorf("error %q should mention the command name", err.Error())
	}
}

func TestFindRepoRoot_FindsRootFromNestedDir(t *testing.T) {
	root := t.TempDir()
	scriptsDir := filepath.Join(root, "scripts")
	if err := os.MkdirAll(scriptsDir, 0o755); err != nil {
		t.Fatalf("MkdirAll: %v", err)
	}
	if err := os.WriteFile(filepath.Join(scriptsDir, "sync.sh"), []byte("#!/bin/bash\n"), 0o644); err != nil {
		t.Fatalf("WriteFile: %v", err)
	}
	nested := filepath.Join(root, "dfa", "internal", "system")
	if err := os.MkdirAll(nested, 0o755); err != nil {
		t.Fatalf("MkdirAll: %v", err)
	}

	got, err := FindRepoRoot(nested)
	if err != nil {
		t.Fatalf("FindRepoRoot() error = %v", err)
	}
	if got != root {
		t.Errorf("FindRepoRoot() = %q, want %q", got, root)
	}
}

func TestFindRepoRoot_ErrorsWhenNotFound(t *testing.T) {
	if _, err := FindRepoRoot(t.TempDir()); err == nil {
		t.Fatal("expected error when no repo root exists above startDir, got nil")
	}
}

func TestResolveRepoRoot_FallsBackToDOTFILES_ARCHEnvVar(t *testing.T) {
	root := t.TempDir()
	scriptsDir := filepath.Join(root, "scripts")
	if err := os.MkdirAll(scriptsDir, 0o755); err != nil {
		t.Fatalf("MkdirAll: %v", err)
	}
	if err := os.WriteFile(filepath.Join(scriptsDir, "sync.sh"), []byte("#!/bin/bash\n"), 0o644); err != nil {
		t.Fatalf("WriteFile: %v", err)
	}
	t.Setenv("DOTFILES_ARCH", root)

	got, err := ResolveRepoRoot(t.TempDir())
	if err != nil {
		t.Fatalf("ResolveRepoRoot() error = %v", err)
	}
	if got != root {
		t.Errorf("ResolveRepoRoot() = %q, want %q", got, root)
	}
}

func TestResolveRepoRoot_ErrorsWhenNothingMatches(t *testing.T) {
	t.Setenv("DOTFILES_ARCH", "")
	t.Setenv("HOME", t.TempDir())

	if _, err := ResolveRepoRoot(t.TempDir()); err == nil {
		t.Fatal("expected error when nothing matches, got nil")
	}
}
