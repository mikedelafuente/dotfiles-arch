// Package catalogfs loads catalog.Manifest data from TOML files on disk —
// the filesystem I/O the pure catalog package deliberately excludes.
package catalogfs

import (
	"fmt"
	"os"
	"path/filepath"
	"sort"

	"github.com/BurntSushi/toml"

	"github.com/mikedelafuente/dotfiles-arch/dfa/internal/catalog"
)

// itemFile mirrors one manifest TOML file's shape.
type itemFile struct {
	ID           string   `toml:"id"`
	Name         string   `toml:"name"`
	Description  string   `toml:"description"`
	Categories   []string `toml:"categories"`
	Tier         string   `toml:"tier"`
	Capabilities []string `toml:"capabilities"`
	Dependencies []string `toml:"dependencies"`
	SetupScript  string   `toml:"setup_script"`
	Packages     struct {
		Pacman []string `toml:"pacman"`
		AUR    []string `toml:"aur"`
	} `toml:"packages"`
}

// LoadDir reads every *.toml file directly under dir (one Software Item per
// file, filenames not otherwise meaningful) and returns a validated
// catalog.Manifest. Files are read in sorted filename order for
// deterministic output.
func LoadDir(dir string) (catalog.Manifest, error) {
	entries, err := os.ReadDir(dir)
	if err != nil {
		return catalog.Manifest{}, fmt.Errorf("catalogfs: reading %s: %w", dir, err)
	}

	var names []string
	for _, e := range entries {
		if e.IsDir() || filepath.Ext(e.Name()) != ".toml" {
			continue
		}
		names = append(names, e.Name())
	}
	sort.Strings(names)

	items := make([]catalog.Item, 0, len(names))
	for _, name := range names {
		path := filepath.Join(dir, name)
		it, err := loadItemFile(path)
		if err != nil {
			return catalog.Manifest{}, err
		}
		items = append(items, it)
	}

	return catalog.NewManifest(items)
}

func loadItemFile(path string) (catalog.Item, error) {
	var f itemFile
	if _, err := toml.DecodeFile(path, &f); err != nil {
		return catalog.Item{}, fmt.Errorf("catalogfs: parsing %s: %w", path, err)
	}
	if f.ID == "" {
		return catalog.Item{}, fmt.Errorf("catalogfs: %s: missing required field %q", path, "id")
	}
	if f.Description == "" {
		return catalog.Item{}, fmt.Errorf("catalogfs: %s: missing required field %q", path, "description")
	}
	if f.SetupScript == "" {
		return catalog.Item{}, fmt.Errorf("catalogfs: %s: missing required field %q", path, "setup_script")
	}

	return catalog.Item{
		ID:           f.ID,
		Name:         f.Name,
		Description:  f.Description,
		Categories:   f.Categories,
		Tier:         catalog.Tier(f.Tier),
		Capabilities: f.Capabilities,
		Dependencies: f.Dependencies,
		Packages: catalog.Packages{
			Pacman: f.Packages.Pacman,
			AUR:    f.Packages.AUR,
		},
		SetupScript: f.SetupScript,
	}, nil
}
