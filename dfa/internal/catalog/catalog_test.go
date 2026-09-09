package catalog

import (
	"errors"
	"reflect"
	"testing"
)

func fixtureManifest(t *testing.T) Manifest {
	t.Helper()
	m, err := NewManifest([]Item{
		{ID: "git", Name: "git", Description: "Version control", Categories: []string{"essentials"}, Tier: TierCore},
		{ID: "git-delta", Name: "git-delta", Description: "Better git diffs", Categories: []string{"essentials"}, Tier: TierOptional, Dependencies: []string{"git"}},
		{ID: "lazygit", Name: "lazygit", Description: "Git TUI built on git-delta", Categories: []string{"essentials"}, Tier: TierOptional, Dependencies: []string{"git-delta"}},
		{ID: "starship", Name: "starship", Description: "Shell prompt", Categories: []string{"essentials"}, Tier: TierOptional},
		{ID: "nvidia", Name: "nvidia", Description: "NVIDIA driver", Categories: []string{"hardware"}, Tier: TierOptional, Capabilities: []string{"nvidia-gpu"}},
	})
	if err != nil {
		t.Fatalf("NewManifest() error = %v", err)
	}
	return m
}

func TestNewManifest_RejectsDuplicateID(t *testing.T) {
	_, err := NewManifest([]Item{
		{ID: "git", Tier: TierCore},
		{ID: "git", Tier: TierCore},
	})
	if err == nil {
		t.Fatal("expected error for duplicate id, got nil")
	}
}

func TestNewManifest_RejectsUnknownDependency(t *testing.T) {
	_, err := NewManifest([]Item{
		{ID: "git-delta", Tier: TierOptional, Dependencies: []string{"git"}},
	})
	if err == nil {
		t.Fatal("expected error for unknown dependency, got nil")
	}
}

func TestNewManifest_RejectsInvalidTier(t *testing.T) {
	_, err := NewManifest([]Item{
		{ID: "git", Tier: "bogus"},
	})
	if err == nil {
		t.Fatal("expected error for invalid tier, got nil")
	}
}

func TestSelect_AutoSelectsDependency(t *testing.T) {
	m := fixtureManifest(t)
	current := Selection{"git": true}

	plan, err := Select(m, current, "git-delta")
	if err != nil {
		t.Fatalf("Select() error = %v", err)
	}

	if !plan.Selection["git-delta"] || !plan.Selection["git"] {
		t.Errorf("Selection = %v, want git-delta and git selected", plan.Selection)
	}
	if want := []string{"git-delta"}; !reflect.DeepEqual(plan.ToInstall, want) {
		t.Errorf("ToInstall = %v, want %v", plan.ToInstall, want)
	}
	if plan.AutoSelected != nil {
		t.Errorf("AutoSelected = %v, want nil (git was already selected)", plan.AutoSelected)
	}
}

func TestSelect_AutoSelectsMissingDependencyAndReportsIt(t *testing.T) {
	m := fixtureManifest(t)
	current := Selection{}

	plan, err := Select(m, current, "git-delta")
	if err != nil {
		t.Fatalf("Select() error = %v", err)
	}

	if !plan.Selection["git"] {
		t.Errorf("Selection = %v, want git auto-selected", plan.Selection)
	}
	if want := []string{"git"}; !reflect.DeepEqual(plan.AutoSelected, want) {
		t.Errorf("AutoSelected = %v, want %v", plan.AutoSelected, want)
	}
	wantInstall := []string{"git", "git-delta"}
	if !reflect.DeepEqual(plan.ToInstall, wantInstall) {
		t.Errorf("ToInstall = %v, want %v", plan.ToInstall, wantInstall)
	}
}

func TestSelect_UnknownItem(t *testing.T) {
	m := fixtureManifest(t)
	_, err := Select(m, Selection{}, "does-not-exist")
	if !errors.Is(err, ErrUnknownItem) {
		t.Errorf("err = %v, want ErrUnknownItem", err)
	}
}

func TestDeselect_CascadesToDependents(t *testing.T) {
	m := fixtureManifest(t)
	current := Selection{"git": true, "git-delta": true, "lazygit": true}

	plan, err := Deselect(m, current, "git-delta")
	if err != nil {
		t.Fatalf("Deselect() error = %v", err)
	}

	if plan.Selection["git-delta"] || plan.Selection["lazygit"] {
		t.Errorf("Selection = %v, want both deselected", plan.Selection)
	}
	if !plan.Selection["git"] {
		t.Errorf("Selection[git] = false, want true (git wasn't targeted)")
	}
	wantCascade := []string{"lazygit"}
	if !reflect.DeepEqual(plan.CascadeDeselected, wantCascade) {
		t.Errorf("CascadeDeselected = %v, want %v", plan.CascadeDeselected, wantCascade)
	}
	wantUninstall := []string{"git-delta", "lazygit"}
	if !reflect.DeepEqual(plan.ToUninstall, wantUninstall) {
		t.Errorf("ToUninstall = %v, want %v", plan.ToUninstall, wantUninstall)
	}
}

func TestDeselect_RefusesCoreItem(t *testing.T) {
	m := fixtureManifest(t)
	current := Selection{"git": true}

	_, err := Deselect(m, current, "git")
	if !errors.Is(err, ErrCoreItemUninstall) {
		t.Errorf("err = %v, want ErrCoreItemUninstall", err)
	}
}

func TestDeselect_RefusesWhenCascadeWouldHitCoreItem(t *testing.T) {
	m, err := NewManifest([]Item{
		{ID: "base", Tier: TierOptional},
		{ID: "depends-on-base", Tier: TierCore, Dependencies: []string{"base"}},
	})
	if err != nil {
		t.Fatalf("NewManifest() error = %v", err)
	}
	current := Selection{"base": true, "depends-on-base": true}

	_, err = Deselect(m, current, "base")
	if !errors.Is(err, ErrCoreItemUninstall) {
		t.Errorf("err = %v, want ErrCoreItemUninstall", err)
	}
}

func TestSelectCategory_SelectsEveryItemAndDeps(t *testing.T) {
	m := fixtureManifest(t)

	plan, err := SelectCategory(m, Selection{}, "essentials")
	if err != nil {
		t.Fatalf("SelectCategory() error = %v", err)
	}

	for _, id := range []string{"git", "git-delta", "starship"} {
		if !plan.Selection[id] {
			t.Errorf("Selection[%q] = false, want true", id)
		}
	}
	if plan.Selection["nvidia"] {
		t.Errorf("Selection[nvidia] = true, want false (different category)")
	}
}

func TestSelectCategory_UnknownCategory(t *testing.T) {
	m := fixtureManifest(t)
	_, err := SelectCategory(m, Selection{}, "does-not-exist")
	if err == nil {
		t.Fatal("expected error for unknown category, got nil")
	}
}

func TestDeselectCategory_LeavesCoreItemsSelected(t *testing.T) {
	m := fixtureManifest(t)
	current := Selection{"git": true, "git-delta": true, "starship": true}

	plan, err := DeselectCategory(m, current, "essentials")
	if err != nil {
		t.Fatalf("DeselectCategory() error = %v", err)
	}

	if !plan.Selection["git"] {
		t.Errorf("Selection[git] = false, want true (core item left alone)")
	}
	if plan.Selection["git-delta"] || plan.Selection["starship"] {
		t.Errorf("Selection = %v, want git-delta and starship deselected", plan.Selection)
	}
}

func TestDiff_ComputesInstallAndUninstall(t *testing.T) {
	current := Selection{"a": true, "b": true}
	desired := Selection{"b": true, "c": true}

	plan := Diff(current, desired)

	if want := []string{"c"}; !reflect.DeepEqual(plan.ToInstall, want) {
		t.Errorf("ToInstall = %v, want %v", plan.ToInstall, want)
	}
	if want := []string{"a"}; !reflect.DeepEqual(plan.ToUninstall, want) {
		t.Errorf("ToUninstall = %v, want %v", plan.ToUninstall, want)
	}
}

func TestManifest_ItemsByCategoryPreservesDeclarationOrder(t *testing.T) {
	m := fixtureManifest(t)
	items := m.ItemsByCategory("essentials")
	var ids []string
	for _, it := range items {
		ids = append(ids, it.ID)
	}
	want := []string{"git", "git-delta", "lazygit", "starship"}
	if !reflect.DeepEqual(ids, want) {
		t.Errorf("ItemsByCategory ids = %v, want %v", ids, want)
	}
}
