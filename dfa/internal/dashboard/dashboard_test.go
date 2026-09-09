package dashboard

import (
	"os"
	"path/filepath"
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"
)

// writeFixtureRepo builds a minimal repo skeleton (catalog manifest +
// scripts dir) so tests can exercise the real Install/Uninstall Software
// wiring without touching the actual dotfiles-arch checkout.
func writeFixtureRepo(t *testing.T) string {
	t.Helper()
	root := t.TempDir()

	itemsDir := filepath.Join(root, "dfa", "catalog", "items")
	if err := os.MkdirAll(itemsDir, 0o755); err != nil {
		t.Fatalf("MkdirAll(itemsDir): %v", err)
	}
	item := `
id = "dfa-test-fixture-item"
name = "Fixture Item"
description = "A fixture item used only by dashboard tests."
categories = ["essentials"]
tier = "optional"
setup_script = "setup-essentials.sh"

[packages]
pacman = ["dfa-test-fixture-package-does-not-exist"]
`
	if err := os.WriteFile(filepath.Join(itemsDir, "fixture.toml"), []byte(item), 0o644); err != nil {
		t.Fatalf("WriteFile(fixture.toml): %v", err)
	}

	scriptsDir := filepath.Join(root, "scripts")
	if err := os.MkdirAll(scriptsDir, 0o755); err != nil {
		t.Fatalf("MkdirAll(scriptsDir): %v", err)
	}

	return root
}

func TestScreens_ListsAllSevenPlannedScreens(t *testing.T) {
	want := []string{
		"Install/Uninstall Software",
		"Repos",
		"Sync",
		"Update System",
		"Morning Routine",
		"Drift Check",
		"Settings",
	}

	scr := screens()
	if len(scr) != len(want) {
		t.Fatalf("screens() returned %d entries, want %d", len(scr), len(want))
	}
	for i, s := range scr {
		if s.title != want[i] {
			t.Errorf("screens()[%d].title = %q, want %q", i, s.title, want[i])
		}
		if s.description == "" {
			t.Errorf("screens()[%d] (%s) has an empty description", i, s.title)
		}
	}
}

func TestUpdate_QuitsOnQ(t *testing.T) {
	m := New(t.TempDir())

	updated, cmd := m.Update(tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune("q")})
	dm := updated.(Model)

	if !dm.quitting {
		t.Errorf("quitting = false after 'q', want true")
	}
	if cmd == nil {
		t.Fatalf("expected a tea.Cmd after 'q', got nil")
	}
	if msg := cmd(); msg != tea.Quit() {
		t.Errorf("cmd() = %v, want tea.Quit()", msg)
	}
}

func TestUpdate_QuitsOnCtrlC(t *testing.T) {
	m := New(t.TempDir())

	updated, cmd := m.Update(tea.KeyMsg{Type: tea.KeyCtrlC})
	dm := updated.(Model)

	if !dm.quitting {
		t.Errorf("quitting = false after ctrl+c, want true")
	}
	if cmd == nil {
		t.Fatalf("expected a tea.Cmd after ctrl+c, got nil")
	}
}

func TestUpdate_EnterSelectsThenEscReturnsToList(t *testing.T) {
	m := New(t.TempDir())

	updated, _ := m.Update(tea.KeyMsg{Type: tea.KeyEnter})
	dm := updated.(Model)
	if dm.selected == nil {
		t.Fatalf("selected == nil after enter, want a selected screen")
	}
	firstTitle := screens()[0].title
	if dm.selected.title != firstTitle {
		t.Errorf("selected.title = %q, want %q", dm.selected.title, firstTitle)
	}

	updated, _ = dm.Update(tea.KeyMsg{Type: tea.KeyEsc})
	dm = updated.(Model)
	if dm.selected != nil {
		t.Errorf("selected = %+v after esc, want nil", dm.selected)
	}
}

func TestUpdate_EnterOnInstallSoftwareOpensRealSoftwareScreen(t *testing.T) {
	m := New(writeFixtureRepo(t))

	updated, _ := m.Update(tea.KeyMsg{Type: tea.KeyEnter})
	dm := updated.(Model)

	if dm.software == nil {
		t.Fatalf("software == nil after opening Install/Uninstall Software, want the real screen wired up (manifestErr: %v)", dm.manifestErr)
	}
	if !strings.Contains(dm.View(), "Fixture Item") {
		t.Errorf("View() = %q, want it to list the fixture item", dm.View())
	}

	// Esc from within the software screen returns a BackMsg via Cmd (real
	// bubbletea usage: the runtime calls cmd() and feeds the result back in).
	updated, cmd := dm.Update(tea.KeyMsg{Type: tea.KeyEsc})
	dm = updated.(Model)
	if cmd == nil {
		t.Fatalf("expected a Cmd carrying BackMsg after esc from the software screen, got nil")
	}
	updated, _ = dm.Update(cmd())
	dm = updated.(Model)

	if dm.software != nil {
		t.Errorf("software = %+v after esc, want nil", dm.software)
	}
	if dm.selected != nil {
		t.Errorf("selected = %+v after esc, want nil", dm.selected)
	}
}

func TestView_DoesNotPanicBeforeOrAfterSelection(t *testing.T) {
	m := New(t.TempDir())
	if m.View() == "" {
		t.Errorf("View() on a fresh model should render something")
	}

	updated, _ := m.Update(tea.KeyMsg{Type: tea.KeyEnter})
	dm := updated.(Model)
	if dm.View() == "" {
		t.Errorf("View() with a selected placeholder screen should render something")
	}
}
