// Package software implements the dfa "Install/Uninstall Software" screen:
// a Bubble Tea list of one Category's Software Items that drives the
// Catalog Engine (dfa/internal/catalog) and, on each resulting plan,
// triggers real installs/uninstalls through a ScriptRunner (the System
// Adapter in production; a fake in tests).
package software

import (
	"fmt"
	"strings"

	tea "github.com/charmbracelet/bubbletea"
	"github.com/charmbracelet/lipgloss"

	"github.com/mikedelafuente/dotfiles-arch/dfa/internal/catalog"
	"github.com/mikedelafuente/dotfiles-arch/dfa/internal/system"
)

// ScriptRunner is the seam this screen uses to actually install/uninstall
// software. The production implementation shells out to the item's
// setup_script via system.RunScript; tests use a fake that just records
// calls, per the parent spec's testing decision.
type ScriptRunner interface {
	RunScript(scriptPath string, args ...string) (system.Result, error)
}

// BackMsg is emitted when the user asks to leave this screen.
type BackMsg struct{}

// ScriptsDirRunner is the production ScriptRunner: it resolves each item's
// setup_script against a scripts directory (the repo's scripts/) and shells
// out to it via system.RunScript.
type ScriptsDirRunner struct {
	ScriptsDir string
}

// RunScript satisfies ScriptRunner.
func (r ScriptsDirRunner) RunScript(scriptName string, args ...string) (system.Result, error) {
	return system.RunScript(r.ScriptsDir+"/"+scriptName, args...)
}

var (
	titleStyle = lipgloss.NewStyle().Bold(true).Padding(0, 1)
	helpStyle  = lipgloss.NewStyle().Faint(true).Padding(1, 1, 0, 1)
	lockStyle  = lipgloss.NewStyle().Faint(true)
	errStyle   = lipgloss.NewStyle().Padding(0, 1)
	cursorSign = "> "
	noCursor   = "  "
)

// Model is the Bubble Tea model for one category's Install/Uninstall
// Software screen.
type Model struct {
	manifest  catalog.Manifest
	category  string
	items     []catalog.Item
	selection catalog.Selection
	runner    ScriptRunner
	cursor    int
	statusMsg string
}

// New builds a software Model scoped to one category, starting from the
// given selection (e.g. derived from querying what's currently installed).
func New(manifest catalog.Manifest, category string, selection catalog.Selection, runner ScriptRunner) Model {
	return Model{
		manifest:  manifest,
		category:  category,
		items:     manifest.ItemsByCategory(category),
		selection: selection.Clone(),
		runner:    runner,
	}
}

// Init satisfies tea.Model.
func (m Model) Init() tea.Cmd { return nil }

// Update satisfies tea.Model.
func (m Model) Update(msg tea.Msg) (tea.Model, tea.Cmd) {
	keyMsg, ok := msg.(tea.KeyMsg)
	if !ok {
		return m, nil
	}

	switch keyMsg.String() {
	case "up", "k":
		if m.cursor > 0 {
			m.cursor--
		}
		return m, nil

	case "down", "j":
		if m.cursor < len(m.items)-1 {
			m.cursor++
		}
		return m, nil

	case "esc":
		return m, func() tea.Msg { return BackMsg{} }

	case " ", "enter":
		m.toggleCurrent()
		return m, nil

	case "a":
		m.selectAll()
		return m, nil

	case "u":
		m.deselectAll()
		return m, nil
	}

	return m, nil
}

func (m *Model) toggleCurrent() {
	if len(m.items) == 0 {
		return
	}
	item := m.items[m.cursor]

	var plan catalog.Plan
	var err error
	if m.selection[item.ID] {
		plan, err = catalog.Deselect(m.manifest, m.selection, item.ID)
	} else {
		plan, err = catalog.Select(m.manifest, m.selection, item.ID)
	}
	m.applyPlanOrError(plan, err)
}

func (m *Model) selectAll() {
	plan, err := catalog.SelectCategory(m.manifest, m.selection, m.category)
	m.applyPlanOrError(plan, err)
}

func (m *Model) deselectAll() {
	plan, err := catalog.DeselectCategory(m.manifest, m.selection, m.category)
	m.applyPlanOrError(plan, err)
}

func (m *Model) applyPlanOrError(plan catalog.Plan, err error) {
	if err != nil {
		m.statusMsg = err.Error()
		return
	}
	m.runPlan(plan)
}

// runPlan executes every install/uninstall in plan and commits the
// resulting selection. A script failure reverts just that item's selection
// state (a failed install is not marked selected; a failed uninstall is not
// marked deselected) so the checkbox never claims success the machine
// didn't actually deliver.
func (m *Model) runPlan(plan catalog.Plan) {
	selection := plan.Selection.Clone()
	var failures []string

	for _, id := range plan.ToInstall {
		item, ok := m.manifest.Item(id)
		if !ok {
			continue
		}
		args := append([]string{"--install"}, item.Packages.Pacman...)
		if _, err := m.runner.RunScript(item.SetupScript, args...); err != nil {
			failures = append(failures, fmt.Sprintf("installing %s failed: %v", id, err))
			selection[id] = false
		}
	}
	for _, id := range plan.ToUninstall {
		item, ok := m.manifest.Item(id)
		if !ok {
			continue
		}
		args := append([]string{"--uninstall"}, item.Packages.Pacman...)
		if _, err := m.runner.RunScript(item.SetupScript, args...); err != nil {
			failures = append(failures, fmt.Sprintf("uninstalling %s failed: %v", id, err))
			selection[id] = true
		}
	}

	m.selection = selection
	if len(failures) > 0 {
		m.statusMsg = strings.Join(failures, " • ")
		return
	}
	m.statusMsg = summarizePlan(plan)
	if len(plan.CoreItemsSkipped) > 0 {
		skipped := "left alone (core, locked): " + strings.Join(plan.CoreItemsSkipped, ", ")
		if m.statusMsg == "" {
			m.statusMsg = skipped
		} else {
			m.statusMsg += " • " + skipped
		}
	}
}

func summarizePlan(plan catalog.Plan) string {
	if len(plan.ToInstall) == 0 && len(plan.ToUninstall) == 0 {
		return ""
	}
	var parts []string
	if len(plan.ToInstall) > 0 {
		parts = append(parts, "installed: "+strings.Join(plan.ToInstall, ", "))
	}
	if len(plan.ToUninstall) > 0 {
		parts = append(parts, "removed: "+strings.Join(plan.ToUninstall, ", "))
	}
	return strings.Join(parts, " • ")
}

// View satisfies tea.Model.
func (m Model) View() string {
	var b strings.Builder
	b.WriteString(titleStyle.Render(fmt.Sprintf("dfa — %s", m.category)))
	b.WriteString("\n\n")

	for i, item := range m.items {
		cursor := noCursor
		if i == m.cursor {
			cursor = cursorSign
		}
		checkbox := "[ ]"
		if m.selection[item.ID] {
			checkbox = "[x]"
		}
		line := fmt.Sprintf("%s%s %s — %s", cursor, checkbox, item.Name, item.Description)
		if item.Tier == catalog.TierCore {
			line = lockStyle.Render(line + " (core, locked)")
		}
		b.WriteString(line)
		b.WriteString("\n")
	}

	if m.statusMsg != "" {
		b.WriteString("\n")
		b.WriteString(errStyle.Render(m.statusMsg))
		b.WriteString("\n")
	}

	b.WriteString(helpStyle.Render("space: toggle  •  a: select all  •  u: deselect all  •  esc: back"))
	return b.String()
}
