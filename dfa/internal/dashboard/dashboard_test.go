package dashboard

import (
	"testing"

	tea "github.com/charmbracelet/bubbletea"
)

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

	screens := Screens()
	if len(screens) != len(want) {
		t.Fatalf("Screens() returned %d entries, want %d", len(screens), len(want))
	}
	for i, s := range screens {
		if s.title != want[i] {
			t.Errorf("Screens()[%d].title = %q, want %q", i, s.title, want[i])
		}
		if s.description == "" {
			t.Errorf("Screens()[%d] (%s) has an empty description", i, s.title)
		}
	}
}

func TestUpdate_QuitsOnQ(t *testing.T) {
	m := New()

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
	m := New()

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
	m := New()

	updated, _ := m.Update(tea.KeyMsg{Type: tea.KeyEnter})
	dm := updated.(Model)
	if dm.selected == nil {
		t.Fatalf("selected == nil after enter, want a selected screen")
	}
	firstTitle := Screens()[0].title
	if dm.selected.title != firstTitle {
		t.Errorf("selected.title = %q, want %q", dm.selected.title, firstTitle)
	}

	updated, _ = dm.Update(tea.KeyMsg{Type: tea.KeyEsc})
	dm = updated.(Model)
	if dm.selected != nil {
		t.Errorf("selected = %+v after esc, want nil", dm.selected)
	}
}

func TestView_DoesNotPanicBeforeOrAfterSelection(t *testing.T) {
	m := New()
	if m.View() == "" {
		t.Errorf("View() on a fresh model should render something")
	}

	updated, _ := m.Update(tea.KeyMsg{Type: tea.KeyEnter})
	dm := updated.(Model)
	if dm.View() == "" {
		t.Errorf("View() with a selected placeholder screen should render something")
	}
}
