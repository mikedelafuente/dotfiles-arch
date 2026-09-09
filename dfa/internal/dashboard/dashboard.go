// Package dashboard implements the top-level dfa dashboard: a Bubble Tea
// list of every planned dfa screen. "Install/Uninstall Software" is wired
// up to the real Catalog Engine + software screen; the rest remain
// placeholders that later work will turn into real screens.
package dashboard

import (
	"fmt"
	"path/filepath"
	"strings"

	"github.com/charmbracelet/bubbles/list"
	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

	"github.com/mikedelafuente/dotfiles-arch/dfa/internal/catalog"
	"github.com/mikedelafuente/dotfiles-arch/dfa/internal/catalogfs"
	"github.com/mikedelafuente/dotfiles-arch/dfa/internal/software"
	"github.com/mikedelafuente/dotfiles-arch/dfa/internal/system"
)

// installSoftwareTitle identifies the one screen entry that's wired up to
// the real Catalog Engine rather than being a placeholder.
const installSoftwareTitle = "Install/Uninstall Software"

// essentialsCategory is the only category the Install/Uninstall Software
// screen exposes so far — later tickets grow the rest of the taxonomy.
const essentialsCategory = "essentials"

// screenItem is one row in the dashboard list: a planned dfa screen.
type screenItem struct {
	title       string
	description string
}

func (i screenItem) Title() string       { return i.title }
func (i screenItem) Description() string { return i.description }
func (i screenItem) FilterValue() string { return i.title }

// screens is the full set of planned dfa dashboard screens. Every entry
// besides Install/Uninstall Software is a placeholder for now — later work
// implements the real behavior behind each one.
func screens() []screenItem {
	return []screenItem{
		{
			title:       installSoftwareTitle,
			description: "Browse the software catalog and select what's installed",
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
	software *software.Model
	quitting bool

	repoRoot    string
	manifest    catalog.Manifest
	manifestErr error
}

// New builds a dashboard Model listing every planned dfa screen. repoRoot is
// the dotfiles-arch checkout root (see system.FindRepoRoot) used to locate
// the catalog manifest and setup-*.sh scripts.
func New(repoRoot string) Model {
	scr := screens()
	items := make([]list.Item, len(scr))
	for i, s := range scr {
		items[i] = s
	}

	delegate := list.NewDefaultDelegate()
	l := list.New(items, delegate, 0, 0)
	l.Title = "dfa — dotfiles-arch"
	l.SetShowStatusBar(false)
	l.SetFilteringEnabled(false)
	l.Styles.Title = titleStyle

	manifest, err := catalogfs.LoadDir(filepath.Join(repoRoot, "dfa", "catalog", "items"))

	return Model{list: l, repoRoot: repoRoot, manifest: manifest, manifestErr: err}
}

// Init satisfies tea.Model.
func (m Model) Init() tea.Cmd {
	return nil
}

// Update satisfies tea.Model.
func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	switch msg := msg.(type) {
	case tea.WindowSizeMsg:
		m.list.SetSize(msg.Width, msg.Height-4)
		return m, nil

	case software.BackMsg:
		m.software = nil
		m.selected = nil
		return m, nil

	case tea.KeyMsg:
		switch msg.String() {
		case "ctrl+c", "q":
			m.quitting = true
			return m, tea.Quit
		}

		if m.software != nil {
			updated, cmd := m.software.Update(msg)
			sm := updated.(software.Model)
			m.software = &sm
			return m, cmd
		}

		switch msg.String() {
		case "esc":
			if m.selected != nil {
				m.selected = nil
				return m, nil
			}
		case "enter":
			if item, ok := m.list.SelectedItem().(screenItem); ok {
				m.selected = &item
				if item.title == installSoftwareTitle {
					m.enterSoftwareScreen()
				}
			}
			return m, nil
		}
	}

	var cmd tea.Cmd
	m.list, cmd = m.list.Update(msg)
	return m, cmd
}

// enterSoftwareScreen builds the real software.Model for the Essentials
// category, seeding its starting selection from what's actually installed
// on the machine. No-ops (leaving the placeholder in place) if the catalog
// manifest failed to load.
func (m *Model) enterSoftwareScreen() {
	if m.manifestErr != nil {
		return
	}

	selection := catalog.Selection{}
	for _, item := range m.manifest.ItemsByCategory(essentialsCategory) {
		if installed, err := system.QueryPackagesInstalled(item.Packages.Pacman); err == nil && installed {
			selection[item.ID] = true
		}
	}

	runner := software.ScriptsDirRunner{ScriptsDir: filepath.Join(m.repoRoot, "scripts")}
	sm := software.New(m.manifest, essentialsCategory, selection, runner)
	m.software = &sm
}

// View satisfies tea.Model.
func (m Model) View() string {
	if m.quitting {
		return ""
	}

	if m.software != nil {
		return m.software.View()
	}

	if m.selected != nil {
		var b strings.Builder
		b.WriteString(titleStyle.Render(m.selected.title))
		b.WriteString("\n")
		notice := placeholderNotice
		if m.selected.title == installSoftwareTitle && m.manifestErr != nil {
			notice = fmt.Sprintf("Could not load the software catalog: %v", m.manifestErr)
		}
		b.WriteString(placeholderStyle.Render(notice))
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
func Run(repoRoot string) error {
	p := tea.NewProgram(New(repoRoot), tea.WithAltScreen())
	_, err := p.Run()
	return err
}
