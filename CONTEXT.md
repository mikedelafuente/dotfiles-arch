# dotfiles-arch

Arch Linux workstation bootstrap/sync automation, moving from a fixed-profile
install model toward an interactively-selectable software catalog driven by
a `dfa` TUI.

## Language

**Software Item**:
A single piece of installable software (an app, driver, or tool) that appears
in the `dfa` picker, backed by one `setup-*.sh` script and its packages.
_Avoid_: package, app, tool (when referring to a catalog entry specifically)

**Category**:
A grouping used to browse and bulk-select Software Items (e.g. Development,
Productivity). Purely organizational — a Software Item can belong to more
than one Category.

**Capability**:
A fact about the machine that `dfa` cannot install and mostly auto-detects
(GPU vendor, Vulkan support, battery presence). Gates whether a Software Item
is selectable; does not itself get installed.
_Avoid_: prerequisite, requirement (reserve those for plain English use)

**Preset**:
A named, editable starting selection of Software Items (e.g. "Work starter
set"), created and saved by the user — the repo ships with none by default.
Purely additive/advisory — picking a Preset pre-checks items but never
restricts which other items can also be picked.
_Avoid_: Profile, bundle

**Dependency**:
A relationship from one Software Item to another Software Item that must
also be installed for it to work (e.g. devcontainer extras depend on Docker).
Distinct from Capability: a Dependency is something `dfa` *can* install for
you (and auto-selects when you pick the dependent item); a Capability is a
machine fact `dfa` cannot install.

**Tier** (Core / Optional):
Whether a Software Item is part of the always-installed baseline (Core —
shown selected and locked in the picker, for consistency across machines) or
picked at the user's discretion (Optional). Cuts across Category — a Category
can contain both Core and Optional items.

**Profile** (retired):
The old work/personal/devcontainer gating mechanism being replaced by
Category + Capability + Preset. No longer used going forward; `SETUP_PROFILES`
in the bootstrap config is legacy.
