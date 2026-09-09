package software

import (
	"errors"
	"reflect"
	"strings"
	"testing"

	tea "github.com/charmbracelet/bubbletea"

	"github.com/mikedelafuente/dotfiles-arch/dfa/internal/catalog"
	"github.com/mikedelafuente/dotfiles-arch/dfa/internal/system"
)

var errBoom = errors.New("boom")

type scriptCall struct {
	script string
	args   []string
}

// fakeRunner records every RunScript call instead of touching a real
// machine, per the parent spec's testing decision for TUI-flow tests.
type fakeRunner struct {
	calls []scriptCall
	err   error
}

func (f *fakeRunner) RunScript(scriptPath string, args ...string) (system.Result, error) {
	f.calls = append(f.calls, scriptCall{script: scriptPath, args: append([]string(nil), args...)})
	if f.err != nil {
		return system.Result{}, f.err
	}
	return system.Result{ExitCode: 0}, nil
}

func fixtureManifest(t *testing.T) catalog.Manifest {
	t.Helper()
	m, err := catalog.NewManifest([]catalog.Item{
		{
			ID: "git", Name: "git", Description: "Version control",
			Categories: []string{"essentials"}, Tier: catalog.TierCore,
			SetupScript: "setup-essentials.sh",
			Packages:    catalog.Packages{Pacman: []string{"git"}},
		},
		{
			ID: "git-delta", Name: "git-delta", Description: "Better git diffs",
			Categories: []string{"essentials"}, Tier: catalog.TierOptional,
			Dependencies: []string{"git"}, SetupScript: "setup-essentials.sh",
			Packages: catalog.Packages{Pacman: []string{"git-delta"}},
		},
		{
			ID: "starship", Name: "starship", Description: "Shell prompt",
			Categories: []string{"essentials"}, Tier: catalog.TierOptional,
			SetupScript: "setup-essentials.sh",
			Packages:    catalog.Packages{Pacman: []string{"starship"}},
		},
		{
			ID: "nvidia", Name: "nvidia", Description: "NVIDIA driver",
			Categories: []string{"hardware"}, Tier: catalog.TierOptional,
			Capabilities: []string{"nvidia-gpu"}, SetupScript: "setup-nvidia.sh",
			Packages: catalog.Packages{Pacman: []string{"nvidia-open-dkms"}},
		},
		{
			ID: "docker", Name: "docker", Description: "Container engine",
			Categories: []string{"development"}, Tier: catalog.TierOptional,
			SetupScript: "setup-docker.sh",
			Packages:    catalog.Packages{Pacman: []string{"docker"}},
		},
		{
			ID: "minikube", Name: "minikube", Description: "Local Kubernetes cluster",
			Categories: []string{"development"}, Tier: catalog.TierOptional,
			Dependencies: []string{"docker"}, SetupScript: "setup-minikube.sh",
			Packages: catalog.Packages{Pacman: []string{"minikube"}},
		},
	})
	if err != nil {
		t.Fatalf("NewManifest() error = %v", err)
	}
	return m
}

func keyMsg(s string) tea.KeyMsg {
	switch s {
	case " ":
		return tea.KeyMsg{Type: tea.KeySpace}
	case "up":
		return tea.KeyMsg{Type: tea.KeyUp}
	case "down":
		return tea.KeyMsg{Type: tea.KeyDown}
	default:
		return tea.KeyMsg{Type: tea.KeyRunes, Runes: []rune(s)}
	}
}

func TestNew_StartsWithNoSelectionByDefault(t *testing.T) {
	m := New(fixtureManifest(t), "essentials", catalog.Selection{}, &fakeRunner{}, nil)
	if len(m.items) != 3 {
		t.Fatalf("len(items) = %d, want 3", len(m.items))
	}
	for id := range m.selection {
		t.Errorf("selection[%q] unexpectedly present in empty starting selection", id)
	}
}

func TestUpdate_SpaceSelectsItemAndRunsInstall(t *testing.T) {
	runner := &fakeRunner{}
	m := New(fixtureManifest(t), "essentials", catalog.Selection{}, runner, nil)
	m.cursor = 1 // git-delta

	updated, _ := m.Update(keyMsg(" "))
	m = updated.(Model)

	if !m.selection["git-delta"] || !m.selection["git"] {
		t.Errorf("selection = %v, want git-delta and its dependency git selected", m.selection)
	}

	want := []scriptCall{
		{script: "setup-essentials.sh", args: []string{"--install", "git"}},
		{script: "setup-essentials.sh", args: []string{"--install", "git-delta"}},
	}
	if !reflect.DeepEqual(runner.calls, want) {
		t.Errorf("calls = %+v, want %+v", runner.calls, want)
	}
}

func TestUpdate_SpaceTogglesBackToDeselectAndRunsUninstall(t *testing.T) {
	runner := &fakeRunner{}
	current := catalog.Selection{"git": true, "starship": true}
	m := New(fixtureManifest(t), "essentials", current, runner, nil)
	m.cursor = 2 // starship

	updated, _ := m.Update(keyMsg(" "))
	m = updated.(Model)

	if m.selection["starship"] {
		t.Errorf("selection[starship] = true, want false after toggling off")
	}
	want := []scriptCall{
		{script: "setup-essentials.sh", args: []string{"--uninstall", "starship"}},
	}
	if !reflect.DeepEqual(runner.calls, want) {
		t.Errorf("calls = %+v, want %+v", runner.calls, want)
	}
}

func TestUpdate_SpaceOnCoreItemRefusesAndShowsError(t *testing.T) {
	runner := &fakeRunner{}
	current := catalog.Selection{"git": true}
	m := New(fixtureManifest(t), "essentials", current, runner, nil)
	m.cursor = 0 // git (core)

	updated, _ := m.Update(keyMsg(" "))
	m = updated.(Model)

	if !m.selection["git"] {
		t.Errorf("selection[git] = false, want still true (core item locked)")
	}
	if m.statusMsg == "" {
		t.Errorf("expected a status message explaining the refusal, got empty string")
	}
	if len(runner.calls) != 0 {
		t.Errorf("calls = %+v, want no script invocations", runner.calls)
	}
}

func TestUpdate_SelectAllInCategory(t *testing.T) {
	runner := &fakeRunner{}
	m := New(fixtureManifest(t), "essentials", catalog.Selection{}, runner, nil)

	updated, _ := m.Update(keyMsg("a"))
	m = updated.(Model)

	for _, id := range []string{"git", "git-delta", "starship"} {
		if !m.selection[id] {
			t.Errorf("selection[%q] = false, want true after select-all", id)
		}
	}
	if len(runner.calls) != 3 {
		t.Errorf("len(calls) = %d, want 3 (one install per item)", len(runner.calls))
	}
}

func TestUpdate_DeselectAllInCategoryLeavesCoreItems(t *testing.T) {
	runner := &fakeRunner{}
	current := catalog.Selection{"git": true, "git-delta": true, "starship": true}
	m := New(fixtureManifest(t), "essentials", current, runner, nil)

	updated, _ := m.Update(keyMsg("u"))
	m = updated.(Model)

	if !m.selection["git"] {
		t.Errorf("selection[git] = false, want true (core item left selected)")
	}
	if m.selection["git-delta"] || m.selection["starship"] {
		t.Errorf("selection = %v, want git-delta and starship deselected", m.selection)
	}
	want := []scriptCall{
		{script: "setup-essentials.sh", args: []string{"--uninstall", "git-delta"}},
		{script: "setup-essentials.sh", args: []string{"--uninstall", "starship"}},
	}
	if !reflect.DeepEqual(runner.calls, want) {
		t.Errorf("calls = %+v, want %+v", runner.calls, want)
	}
}

func TestUpdate_FailedInstallDoesNotMarkItemSelected(t *testing.T) {
	runner := &fakeRunner{err: errBoom}
	m := New(fixtureManifest(t), "essentials", catalog.Selection{"git": true}, runner, nil)
	m.cursor = 2 // starship

	updated, _ := m.Update(keyMsg(" "))
	m = updated.(Model)

	if m.selection["starship"] {
		t.Errorf("selection[starship] = true, want false (install script failed)")
	}
	if m.statusMsg == "" {
		t.Errorf("expected a failure status message, got empty string")
	}
}

func TestUpdate_FailedUninstallLeavesItemSelected(t *testing.T) {
	runner := &fakeRunner{err: errBoom}
	current := catalog.Selection{"git": true, "starship": true}
	m := New(fixtureManifest(t), "essentials", current, runner, nil)
	m.cursor = 2 // starship

	updated, _ := m.Update(keyMsg(" "))
	m = updated.(Model)

	if !m.selection["starship"] {
		t.Errorf("selection[starship] = false, want true (uninstall script failed, so it's still there)")
	}
}

func TestUpdate_DeselectAllReportsCoreItemsLeftAlone(t *testing.T) {
	runner := &fakeRunner{}
	current := catalog.Selection{"git": true, "starship": true}
	m := New(fixtureManifest(t), "essentials", current, runner, nil)

	updated, _ := m.Update(keyMsg("u"))
	m = updated.(Model)

	if !strings.Contains(m.statusMsg, "git") {
		t.Errorf("statusMsg = %q, want it to mention the core item left alone", m.statusMsg)
	}
}

func TestUpdate_CursorMovesWithinBounds(t *testing.T) {
	m := New(fixtureManifest(t), "essentials", catalog.Selection{}, &fakeRunner{}, nil)

	updated, _ := m.Update(keyMsg("up"))
	m = updated.(Model)
	if m.cursor != 0 {
		t.Errorf("cursor = %d, want 0 (clamped at top)", m.cursor)
	}

	for i := 0; i < 5; i++ {
		updated, _ = m.Update(keyMsg("down"))
		m = updated.(Model)
	}
	if m.cursor != 2 {
		t.Errorf("cursor = %d, want 2 (clamped at bottom)", m.cursor)
	}
}

func TestUpdate_SpaceOnCapabilityBlockedItemRefusesAndShowsReason(t *testing.T) {
	runner := &fakeRunner{}
	caps := catalog.Capabilities{"nvidia-gpu": {Met: false, Reason: "No NVIDIA GPU detected on this machine"}}
	m := New(fixtureManifest(t), "hardware", catalog.Selection{}, runner, caps)

	updated, _ := m.Update(keyMsg(" "))
	m = updated.(Model)

	if m.selection["nvidia"] {
		t.Errorf("selection[nvidia] = true, want false (capability not met)")
	}
	if !strings.Contains(m.statusMsg, "No NVIDIA GPU detected on this machine") {
		t.Errorf("statusMsg = %q, want it to include the capability's reason", m.statusMsg)
	}
	if len(runner.calls) != 0 {
		t.Errorf("calls = %+v, want no script invocations", runner.calls)
	}
}

func TestUpdate_SpaceOnCapabilityMetItemInstalls(t *testing.T) {
	runner := &fakeRunner{}
	caps := catalog.Capabilities{"nvidia-gpu": {Met: true}}
	m := New(fixtureManifest(t), "hardware", catalog.Selection{}, runner, caps)

	updated, _ := m.Update(keyMsg(" "))
	m = updated.(Model)

	if !m.selection["nvidia"] {
		t.Errorf("selection[nvidia] = false, want true (capability met)")
	}
	want := []scriptCall{{script: "setup-nvidia.sh", args: []string{"--install", "nvidia-open-dkms"}}}
	if !reflect.DeepEqual(runner.calls, want) {
		t.Errorf("calls = %+v, want %+v", runner.calls, want)
	}
}

func TestView_ShowsDisabledCapabilityGatedItemWithReason(t *testing.T) {
	caps := catalog.Capabilities{"nvidia-gpu": {Met: false, Reason: "No NVIDIA GPU detected on this machine"}}
	m := New(fixtureManifest(t), "hardware", catalog.Selection{}, &fakeRunner{}, caps)

	view := m.View()
	if !strings.Contains(view, "unavailable") || !strings.Contains(view, "No NVIDIA GPU detected on this machine") {
		t.Errorf("View() = %q, want it to show the item disabled with its unmet-capability reason", view)
	}
}

func TestUpdate_DeselectDependencyWithSelectedDependentAsksConfirmationFirst(t *testing.T) {
	runner := &fakeRunner{}
	current := catalog.Selection{"docker": true, "minikube": true}
	m := New(fixtureManifest(t), "development", current, runner, nil)
	m.cursor = 0 // docker

	updated, _ := m.Update(keyMsg(" "))
	m = updated.(Model)

	if !m.selection["docker"] || !m.selection["minikube"] {
		t.Errorf("selection = %v, want unchanged until the cascade is confirmed", m.selection)
	}
	if len(runner.calls) != 0 {
		t.Errorf("calls = %+v, want none until confirmed", runner.calls)
	}
	if !strings.Contains(m.statusMsg, "minikube") {
		t.Errorf("statusMsg = %q, want it to name the cascaded dependent", m.statusMsg)
	}
}

func TestUpdate_ConfirmingCascadeAppliesBothUninstalls(t *testing.T) {
	runner := &fakeRunner{}
	current := catalog.Selection{"docker": true, "minikube": true}
	m := New(fixtureManifest(t), "development", current, runner, nil)
	m.cursor = 0 // docker

	updated, _ := m.Update(keyMsg(" "))
	m = updated.(Model)
	updated, _ = m.Update(keyMsg("y"))
	m = updated.(Model)

	if m.selection["docker"] || m.selection["minikube"] {
		t.Errorf("selection = %v, want both deselected after confirming", m.selection)
	}
	want := []scriptCall{
		{script: "setup-docker.sh", args: []string{"--uninstall", "docker"}},
		{script: "setup-minikube.sh", args: []string{"--uninstall", "minikube"}},
	}
	if !reflect.DeepEqual(runner.calls, want) {
		t.Errorf("calls = %+v, want %+v", runner.calls, want)
	}
}

func TestUpdate_CancellingCascadeLeavesSelectionAndSkipsScripts(t *testing.T) {
	runner := &fakeRunner{}
	current := catalog.Selection{"docker": true, "minikube": true}
	m := New(fixtureManifest(t), "development", current, runner, nil)
	m.cursor = 0 // docker

	updated, _ := m.Update(keyMsg(" "))
	m = updated.(Model)
	updated, _ = m.Update(keyMsg("n"))
	m = updated.(Model)

	if !m.selection["docker"] || !m.selection["minikube"] {
		t.Errorf("selection = %v, want unchanged after cancelling", m.selection)
	}
	if len(runner.calls) != 0 {
		t.Errorf("calls = %+v, want none after cancelling", runner.calls)
	}
	if m.pendingPlan != nil {
		t.Errorf("pendingPlan = %+v, want nil after cancelling", m.pendingPlan)
	}
}

func TestUpdate_SelectDependentAutoSelectsDependencyWithoutConfirmation(t *testing.T) {
	runner := &fakeRunner{}
	m := New(fixtureManifest(t), "development", catalog.Selection{}, runner, nil)
	m.cursor = 1 // minikube

	updated, _ := m.Update(keyMsg(" "))
	m = updated.(Model)

	if !m.selection["docker"] || !m.selection["minikube"] {
		t.Errorf("selection = %v, want both docker and minikube selected", m.selection)
	}
	want := []scriptCall{
		{script: "setup-docker.sh", args: []string{"--install", "docker"}},
		{script: "setup-minikube.sh", args: []string{"--install", "minikube"}},
	}
	if !reflect.DeepEqual(runner.calls, want) {
		t.Errorf("calls = %+v, want %+v", runner.calls, want)
	}
}

func TestUpdate_DeselectAllCascadeAsksConfirmationFirst(t *testing.T) {
	runner := &fakeRunner{}
	current := catalog.Selection{"docker": true, "minikube": true}
	m := New(fixtureManifest(t), "development", current, runner, nil)

	updated, _ := m.Update(keyMsg("u"))
	m = updated.(Model)

	if !m.selection["docker"] || !m.selection["minikube"] {
		t.Errorf("selection = %v, want unchanged until confirmed", m.selection)
	}
	if len(runner.calls) != 0 {
		t.Errorf("calls = %+v, want none until confirmed", runner.calls)
	}

	updated, _ = m.Update(keyMsg("y"))
	m = updated.(Model)

	if m.selection["docker"] || m.selection["minikube"] {
		t.Errorf("selection = %v, want both deselected after confirming", m.selection)
	}
	if len(runner.calls) != 2 {
		t.Errorf("len(calls) = %d, want 2 after confirming", len(runner.calls))
	}
}

func TestView_ShowsCascadeConfirmationHelp(t *testing.T) {
	current := catalog.Selection{"docker": true, "minikube": true}
	m := New(fixtureManifest(t), "development", current, &fakeRunner{}, nil)
	m.cursor = 0 // docker

	updated, _ := m.Update(keyMsg(" "))
	m = updated.(Model)

	view := m.View()
	if !strings.Contains(view, "confirm removal") {
		t.Errorf("View() = %q, want it to show the confirm/cancel help", view)
	}
}

func TestUpdate_EscRequestsBack(t *testing.T) {
	m := New(fixtureManifest(t), "essentials", catalog.Selection{}, &fakeRunner{}, nil)

	_, cmd := m.Update(tea.KeyMsg{Type: tea.KeyEsc})
	if cmd == nil {
		t.Fatal("expected a Cmd for esc, got nil")
	}
	if msg := cmd(); msg != (BackMsg{}) {
		t.Errorf("cmd() = %#v, want BackMsg{}", msg)
	}
}
