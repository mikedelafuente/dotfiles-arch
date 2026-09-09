// Package dashboard implements the top-level dfa dashboard: a Bubble Tea
// list of every planned dfa screen. This ticket (#38) only wires up the
// shell — most entries are placeholders that later tickets (#39, #40,
// #49-#53) will turn into real screens.
package dashboard

import (
	"fmt"
	"strings"

	"github.com/charmbracelet/bubbles/list"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"
)

// screenItem is one row in the dashboard list: a planned dfa screen.
type screenItem struct {
	title       string
	description string
}

func (i screenItem) Title() string       { return i.title }
func (i screenItem) Description() string { return i.description }
func (i screenItem) FilterValue() string { return i.title }

// Screens is the full set of planned dfa dashboard screens, per the #35
// epic. Every entry is a placeholder for this ticket (#38) — later tickets
// implement the real behavior behind each one.
func Screens() []screenItem {
	return []screenItem{
		{
			title:       "Install/Uninstall Software",
			description: "Browse the software catalog and select what's installed (not yet implemented)",
		},
		{
			title:       "Repos",
			description: "List and manage locally cloned git repos (not yet implemented)",
		},
		{
			title:       "Sync",
			description: "Sync dotfiles, skills, rules, and sources (not yet implemented)",
		},
		{
			title:       "Update System",
			description: "Guarded pacman + yay system update (not yet implemented)",
		},
		{
			title:       "Morning Routine",
			description: "Run the day's usual maintenance in one pass (not yet implemented)",
		},
		{
			title:       "Drift Check",
			description: "Compare selected software against what's actually installed (not yet implemented)",
		},
		{
			title:       "Settings",
			description: "Edit git identity, machine type, and default agent (not yet implemented)",
		},
	}
}

const placeholderNotice = "This screen isn't implemented yet — coming in a later ticket."

var (
	titleStyle = lipgloss.NewStyle().
			Bold(true).
			Padding(0, 1)

	helpStyle = lipgloss.NewStyle().
			Faint(true).
			Padding(1, 1, 0, 1)

	placeholderStyle = lipgloss.NewStyle().
				Padding(1, 2).
				Italic(true)
)

// Model is the Bubble Tea model for the dfa dashboard shell.
type Model struct {
	list     list.Model
	selected *screenItem
	quitting bool
	width    int
	height   int
}

// New builds a dashboard Model listing every planned dfa screen.
func New() Model {
	screens := Screens()
	items := make([]list.Item, len(screens))
	for i, s := range screens {
		items[i] = s
	}

	delegate := list.NewDefaultDelegate()
	l := list.New(items, delegate, 0, 0)
	l.Title = "dfa — dotfiles-arch"
	l.SetShowStatusBar(false)
	l.SetFilteringEnabled(false)
	l.Styles.Title = titleStyle

	return Model{list: l}
}

// Init satisfies tea.Model.
func (m Model) Init() tea.Cmd {
	return nil
}

// Update satisfies tea.Model.
func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.width, m.height = msg.Width, msg.Height
		m.list.SetSize(msg.Width, msg.Height-4)
		return m, nil

	case tea.KeyMsg:
		switch msg.String() {
		case "ctrl+c", "q":
			m.quitting = true
			return m, tea.Quit
		case "esc":
			if m.selected != nil {
				m.selected = nil
				return m, nil
			}
		case "enter":
			if item, ok := m.list.SelectedItem().(screenItem); ok {
				m.selected = &item
			}
			return m, nil
		}
	}

	var cmd tea.Cmd
	m.list, cmd = m.list.Update(msg)
	return m, cmd
}

// View satisfies tea.Model.
func (m Model) View() string {
	if m.quitting {
		return ""
	}

	if m.selected != nil {
		var b strings.Builder
		b.WriteString(titleStyle.Render(m.selected.title))
		b.WriteString("\n")
		b.WriteString(placeholderStyle.Render(placeholderNotice))
		b.WriteString("\n")
		b.WriteString(helpStyle.Render("esc: back to dashboard  •  q: quit"))
		return b.String()
	}

	var b strings.Builder
	b.WriteString(m.list.View())
	b.WriteString(helpStyle.Render(fmt.Sprintf("%d screens  •  enter: open  •  q: quit", len(m.list.Items()))))
	return b.String()
}

// Run starts the dashboard Bubble Tea program and blocks until it quits.
func Run() error {
	p := tea.NewProgram(New(), tea.WithAltScreen())
	_, err := p.Run()
	return err
}
