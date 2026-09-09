package catalogfs

import (
	"os"
	"path/filepath"
	"testing"
)

func writeFile(t *testing.T, dir, name, content string) {
	t.Helper()
	if err := os.WriteFile(filepath.Join(dir, name), []byte(content), 0o644); err != nil {
		t.Fatalf("writing fixture %s: %v", name, err)
	}
}

func TestLoadDir_ParsesItemsInSortedFilenameOrder(t *testing.T) {
	dir := t.TempDir()
	writeFile(t, dir, "git-delta.toml", `
id = "git-delta"
name = "git-delta"
description = "Side-by-side syntax-highlighted git diffs."
categories = ["essentials"]
tier = "optional"
dependencies = ["git"]
setup_script = "setup-essentials.sh"

[packages]
pacman = ["git-delta"]
`)
	writeFile(t, dir, "git.toml", `
id = "git"
name = "git"
description = "Distributed version control."
categories = ["essentials"]
tier = "core"
setup_script = "setup-essentials.sh"

[packages]
pacman = ["git"]
`)

	m, err := LoadDir(dir)
	if err != nil {
		t.Fatalf("LoadDir() error = %v", err)
	}

	items := m.ItemsByCategory("essentials")
	if len(items) != 2 {
		t.Fatalf("len(items) = %d, want 2", len(items))
	}
	// git-delta.toml sorts before git.toml, so filename order puts
	// git-delta first even though git is its dependency.
	if items[0].ID != "git-delta" || items[1].ID != "git" {
		t.Errorf("items = [%s, %s], want [git-delta, git]", items[0].ID, items[1].ID)
	}

	delta, ok := m.Item("git-delta")
	if !ok {
		t.Fatal("git-delta not found")
	}
	if delta.Description != "Side-by-side syntax-highlighted git diffs." {
		t.Errorf("Description = %q", delta.Description)
	}
	if len(delta.Packages.Pacman) != 1 || delta.Packages.Pacman[0] != "git-delta" {
		t.Errorf("Packages.Pacman = %v", delta.Packages.Pacman)
	}
	if delta.SetupScript != "setup-essentials.sh" {
		t.Errorf("SetupScript = %q", delta.SetupScript)
	}
}

func TestLoadDir_RejectsMissingRequiredFields(t *testing.T) {
	dir := t.TempDir()
	writeFile(t, dir, "broken.toml", `
name = "broken"
description = "Missing an id."
setup_script = "setup-essentials.sh"
`)

	if _, err := LoadDir(dir); err == nil {
		t.Fatal("expected error for missing id, got nil")
	}
}

func TestLoadDir_PropagatesManifestValidationErrors(t *testing.T) {
	dir := t.TempDir()
	writeFile(t, dir, "orphan.toml", `
id = "orphan"
name = "orphan"
description = "Depends on something that doesn't exist."
tier = "optional"
dependencies = ["ghost"]
setup_script = "setup-essentials.sh"
`)

	if _, err := LoadDir(dir); err == nil {
		t.Fatal("expected error for unknown dependency, got nil")
	}
}

func TestLoadDir_MissingDirectory(t *testing.T) {
	if _, err := LoadDir(filepath.Join(t.TempDir(), "does-not-exist")); err == nil {
		t.Fatal("expected error for missing directory, got nil")
	}
}

// TestLoadDir_LoadsTheRealEssentialsManifest guards against a bad TOML file
// under dfa/catalog/items breaking every dfa build — it's the one directory
// this package ships needing runtime, not just fixture, validation.
func TestLoadDir_LoadsTheRealEssentialsManifest(t *testing.T) {
	m, err := LoadDir(filepath.Join("..", "..", "catalog", "items"))
	if err != nil {
		t.Fatalf("LoadDir(catalog/items) error = %v", err)
	}

	items := m.ItemsByCategory("essentials")
	if len(items) == 0 {
		t.Fatal("expected at least one essentials item, got none")
	}
	for _, it := range items {
		if it.Description == "" {
			t.Errorf("item %q has an empty description", it.ID)
		}
		if len(it.Packages.Pacman) == 0 && len(it.Packages.AUR) == 0 {
			t.Errorf("item %q declares no packages", it.ID)
		}
		if it.SetupScript != "setup-essentials.sh" {
			t.Errorf("item %q has setup_script %q, want setup-essentials.sh", it.ID, it.SetupScript)
		}
	}

	if _, ok := m.Item("git"); !ok {
		t.Error(`expected "git" item to exist`)
	}
}
