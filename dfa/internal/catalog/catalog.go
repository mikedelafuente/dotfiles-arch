// Package catalog is the pure Catalog Engine: given a Manifest (plain Go
// data, no filesystem/exec/network) and a Selection, it computes dependency
// resolution, cascade-deselection, Core-item uninstall refusal, and
// install/uninstall plans. Loading manifests from disk lives in a separate
// package (dfa/internal/catalogfs) so this one stays testable with in-memory
// fixtures alone.
package catalog

import (
	"errors"
	"fmt"
	"sort"
)

// Tier distinguishes baseline Software Items (always selected, locked
// against uninstall) from Optional ones the user freely toggles.
type Tier string

const (
	TierCore     Tier = "core"
	TierOptional Tier = "optional"
)

// Packages lists the backing packages a Software Item installs, split by
// the package manager that provides them.
type Packages struct {
	Pacman []string
	AUR    []string
}

// Item is one Software Item: a single declarative manifest entry.
type Item struct {
	ID           string
	Name         string
	Description  string
	Categories   []string
	Tier         Tier
	Capabilities []string
	Dependencies []string
	Packages     Packages
	SetupScript  string
}

// Manifest is the full, validated set of Software Items.
type Manifest struct {
	items   []Item
	byID    map[string]Item
	byOrder []string // ids in declaration order, for stable output
}

// NewManifest validates items (unique ids, dependencies/tiers referencing
// real items and valid values) and returns a Manifest ready for use with
// the rest of this package.
func NewManifest(items []Item) (Manifest, error) {
	byID := make(map[string]Item, len(items))
	order := make([]string, 0, len(items))

	for _, it := range items {
		if it.ID == "" {
			return Manifest{}, errors.New("catalog: item has empty id")
		}
		if _, exists := byID[it.ID]; exists {
			return Manifest{}, fmt.Errorf("catalog: duplicate item id %q", it.ID)
		}
		if it.Tier != TierCore && it.Tier != TierOptional {
			return Manifest{}, fmt.Errorf("catalog: item %q has invalid tier %q", it.ID, it.Tier)
		}
		byID[it.ID] = it
		order = append(order, it.ID)
	}

	for _, it := range items {
		for _, dep := range it.Dependencies {
			if _, ok := byID[dep]; !ok {
				return Manifest{}, fmt.Errorf("catalog: item %q depends on unknown item %q", it.ID, dep)
			}
		}
	}

	return Manifest{items: items, byID: byID, byOrder: order}, nil
}

// Item looks up a Software Item by id.
func (m Manifest) Item(id string) (Item, bool) {
	it, ok := m.byID[id]
	return it, ok
}

// ItemsByCategory returns every item (in manifest declaration order) that
// lists the given category.
func (m Manifest) ItemsByCategory(category string) []Item {
	var out []Item
	for _, id := range m.byOrder {
		it := m.byID[id]
		for _, c := range it.Categories {
			if c == category {
				out = append(out, it)
				break
			}
		}
	}
	return out
}

// dependents returns the ids of every item that directly depends on id.
func (m Manifest) dependents(id string) []string {
	var out []string
	for _, oid := range m.byOrder {
		it := m.byID[oid]
		for _, dep := range it.Dependencies {
			if dep == id {
				out = append(out, oid)
				break
			}
		}
	}
	return out
}

// CapabilityStatus is a detected machine fact about one named Capability
// (e.g. "nvidia-gpu"): whether it's currently met, and — when it isn't — the
// plain-language reason to show the user in place of the gated item's
// controls.
type CapabilityStatus struct {
	Met    bool
	Reason string
}

// Capabilities maps a Capability name (as referenced by Item.Capabilities)
// to its currently detected status on this machine. It is plain data — the
// System Adapter does the actual detection (lspci/sysfs probes, cached
// user-declared answers) and builds this map; the Catalog Engine only
// evaluates against it.
type Capabilities map[string]CapabilityStatus

// CapabilityGap names one capability a Software Item requires that isn't
// currently met, plus the plain-language reason to show the user.
type CapabilityGap struct {
	Name   string
	Reason string
}

const unmetCapabilityDefaultReason = "not available on this machine"

// Gaps returns the capabilities item requires that aren't met by caps, in
// the item's declared order — nil if the item has no requirements or every
// requirement is met.
func Gaps(item Item, caps Capabilities) []CapabilityGap {
	var out []CapabilityGap
	for _, name := range item.Capabilities {
		status, ok := caps[name]
		if ok && status.Met {
			continue
		}
		reason := unmetCapabilityDefaultReason
		if ok {
			reason = status.Reason
		}
		out = append(out, CapabilityGap{Name: name, Reason: reason})
	}
	return out
}

// Available reports whether every capability item requires is met.
func Available(item Item, caps Capabilities) bool {
	return len(Gaps(item, caps)) == 0
}

// Selection is the set of currently-selected item ids.
type Selection map[string]bool

// Clone returns an independent copy of the selection.
func (s Selection) Clone() Selection {
	out := make(Selection, len(s))
	for k, v := range s {
		out[k] = v
	}
	return out
}

// ErrUnknownItem is returned when an action names an id the manifest does
// not have.
var ErrUnknownItem = errors.New("catalog: unknown item id")

// ErrCoreItemUninstall is returned when a requested change would remove a
// Core item. The Catalog Engine refuses such plans outright.
var ErrCoreItemUninstall = errors.New("catalog: cannot uninstall a core item")

// ErrCapabilityNotMet is returned when a requested selection targets an item
// (or, via dependency resolution, pulls in an item) whose Capability
// requirements aren't met.
var ErrCapabilityNotMet = errors.New("catalog: capability requirement not met")

// Plan is the result of applying a selection change: the resulting
// selection, plus the concrete install/uninstall work and any side effects
// (auto-selected dependencies, cascade-deselected dependents) that
// produced it.
type Plan struct {
	Selection         Selection
	ToInstall         []string
	ToUninstall       []string
	AutoSelected      []string
	CascadeDeselected []string
	// CoreItemsSkipped lists Core items a DeselectCategory call left
	// selected rather than refusing the whole plan over, so callers can
	// surface why not everything in the category came out.
	CoreItemsSkipped []string
	// CapabilityBlocked lists items a SelectCategory call left unselected
	// because their Capability requirements aren't met, rather than
	// refusing the whole plan over them.
	CapabilityBlocked []string
}

func sortedKeys(m map[string]bool) []string {
	out := make([]string, 0, len(m))
	for k := range m {
		out = append(out, k)
	}
	sort.Strings(out)
	return out
}

// Diff computes the install/uninstall plan needed to move from current to
// desired, with no dependency resolution of its own — callers that already
// have a validated desired Selection (e.g. from Select/Deselect below) use
// this to get the concrete plan.
func Diff(current, desired Selection) Plan {
	toInstall := map[string]bool{}
	toUninstall := map[string]bool{}

	for id, selected := range desired {
		if selected && !current[id] {
			toInstall[id] = true
		}
	}
	for id, selected := range current {
		if selected && !desired[id] {
			toUninstall[id] = true
		}
	}

	return Plan{
		Selection:   desired.Clone(),
		ToInstall:   sortedKeys(toInstall),
		ToUninstall: sortedKeys(toUninstall),
	}
}

// Select adds itemID to the selection, transitively auto-selecting any
// declared dependencies that aren't already selected. It refuses (returning
// ErrCapabilityNotMet) if itemID — or any dependency the resolution would
// also select — has an unmet Capability requirement.
func Select(manifest Manifest, current Selection, itemID string, caps Capabilities) (Plan, error) {
	if _, ok := manifest.Item(itemID); !ok {
		return Plan{}, fmt.Errorf("%w: %s", ErrUnknownItem, itemID)
	}

	desired := current.Clone()
	var autoSelected []string

	var visit func(id string, isRoot bool) error
	visit = func(id string, isRoot bool) error {
		it := manifest.byID[id]
		if !Available(it, caps) {
			return fmt.Errorf("%w: %s", ErrCapabilityNotMet, id)
		}
		alreadySelected := desired[id]
		desired[id] = true
		if !alreadySelected && !isRoot {
			autoSelected = append(autoSelected, id)
		}
		for _, dep := range it.Dependencies {
			if err := visit(dep, false); err != nil {
				return err
			}
		}
		return nil
	}
	if err := visit(itemID, true); err != nil {
		return Plan{}, err
	}

	plan := Diff(current, desired)
	plan.AutoSelected = autoSelected
	return plan, nil
}

// Deselect removes itemID from the selection, cascading to any currently
// selected items that transitively depend on it. It refuses (returning
// ErrCoreItemUninstall) if itemID — or any item the cascade would also
// remove — is a Core item.
func Deselect(manifest Manifest, current Selection, itemID string) (Plan, error) {
	it, ok := manifest.Item(itemID)
	if !ok {
		return Plan{}, fmt.Errorf("%w: %s", ErrUnknownItem, itemID)
	}
	if it.Tier == TierCore {
		return Plan{}, fmt.Errorf("%w: %s", ErrCoreItemUninstall, itemID)
	}

	desired := current.Clone()
	var cascade []string

	var visit func(id string, isRoot bool) error
	visit = func(id string, isRoot bool) error {
		if !desired[id] {
			return nil
		}
		cur := manifest.byID[id]
		if cur.Tier == TierCore {
			return fmt.Errorf("%w: %s", ErrCoreItemUninstall, id)
		}
		desired[id] = false
		if !isRoot {
			cascade = append(cascade, id)
		}
		for _, depID := range manifest.dependents(id) {
			if err := visit(depID, false); err != nil {
				return err
			}
		}
		return nil
	}
	if err := visit(itemID, true); err != nil {
		return Plan{}, err
	}

	plan := Diff(current, desired)
	plan.CascadeDeselected = cascade
	return plan, nil
}

// SelectCategory selects every item in the given category (plus their
// transitive dependencies). An item whose Capability requirements aren't met
// is left unselected rather than failing the whole call — it's reported via
// Plan.CapabilityBlocked instead.
func SelectCategory(manifest Manifest, current Selection, category string, caps Capabilities) (Plan, error) {
	desired := current.Clone()
	var autoSelected []string
	var capBlocked []string
	seen := map[string]bool{}
	seenBlocked := map[string]bool{}

	var visit func(id string, isRoot bool)
	visit = func(id string, isRoot bool) {
		it := manifest.byID[id]
		if !Available(it, caps) {
			if isRoot && !seenBlocked[id] {
				capBlocked = append(capBlocked, id)
				seenBlocked[id] = true
			}
			return
		}
		alreadySelected := desired[id]
		desired[id] = true
		if !alreadySelected && !isRoot && !seen[id] {
			autoSelected = append(autoSelected, id)
			seen[id] = true
		}
		for _, dep := range it.Dependencies {
			visit(dep, false)
		}
	}

	items := manifest.ItemsByCategory(category)
	if len(items) == 0 {
		return Plan{}, fmt.Errorf("catalog: unknown category %q", category)
	}
	for _, it := range items {
		visit(it.ID, true)
	}

	plan := Diff(current, desired)
	plan.AutoSelected = autoSelected
	plan.CapabilityBlocked = capBlocked
	return plan, nil
}

// DeselectCategory deselects every non-Core item in the given category
// (cascading to their dependents, same as Deselect), leaving any Core item
// in the category untouched rather than erroring.
func DeselectCategory(manifest Manifest, current Selection, category string) (Plan, error) {
	items := manifest.ItemsByCategory(category)
	if len(items) == 0 {
		return Plan{}, fmt.Errorf("catalog: unknown category %q", category)
	}

	desired := current.Clone()
	var cascade []string
	var coreSkipped []string
	seen := map[string]bool{}

	var visit func(id string, isRoot bool) error
	visit = func(id string, isRoot bool) error {
		if !desired[id] {
			return nil
		}
		cur := manifest.byID[id]
		if cur.Tier == TierCore {
			if isRoot {
				coreSkipped = append(coreSkipped, id)
				return nil // leave Core items alone rather than erroring
			}
			return fmt.Errorf("%w: %s", ErrCoreItemUninstall, id)
		}
		desired[id] = false
		if !isRoot && !seen[id] {
			cascade = append(cascade, id)
			seen[id] = true
		}
		for _, depID := range manifest.dependents(id) {
			if err := visit(depID, false); err != nil {
				return err
			}
		}
		return nil
	}

	for _, it := range items {
		if err := visit(it.ID, true); err != nil {
			return Plan{}, err
		}
	}

	plan := Diff(current, desired)
	plan.CascadeDeselected = cascade
	plan.CoreItemsSkipped = coreSkipped
	return plan, nil
}
