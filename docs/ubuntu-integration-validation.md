# Shared workstation integration: validation boundary

Selected support: rolling Arch Linux and installed Ubuntu 26.04 LTS GNOME on
x86_64/amd64. Both use one additive `work`/`personal`/`devcontainer` setup list,
shared settings/config namespaces, and the existing daily/weekly order. App
sources, minimums, update owners and conflicts are recorded in
[PACKAGES.md](../PACKAGES.md) and the [source/update audit](ubuntu-source-update-audit.md).
Selected support does not establish install, upgrade, desktop or hardware runtime parity.

The integration changes were inspected statically. Direct Bash syntax,
ShellCheck and Python parsing checks are reported with the implementing commit.
No setup/update/test scripts, package/source transactions, services, desktop
settings, drivers, devices, model downloads or VMs were executed for validation.
Regression decision checks were updated and left unrun under the user's execution restriction.

| Boundary | Static contract | Unverified runtime |
|---|---|---|
| Host/entrypoint | Common header rejects unsupported releases/architectures before writes; full Ubuntu consumers require installed GNOME; Arch disk/AUR utilities remain guarded | Actual Ubuntu metadata/native-package reporting and workstation invocation |
| Profiles/settings | One additive runner, existing order, saved identity/NVIDIA/machine/default-harness accessors; parent process loads validated NVM after Node setup | First-run installation, CLI visibility, selected default harness, saved config persistence |
| Native/source preparation | Arch multilib/yay only; Ubuntu preparation stays within explicit app recipes | Privileged repository/key/component registration and source conflict resolution |
| Update/stamp | Required preparation/native/app owner failures remain nonzero; only completed requested updates may write a success stamp; legacy Arch stamps remain readable | Native transactions, held/deferred package behavior, release acquisition/verification, self-updater policy |
| Required failures | Missing selected setup scripts, absent Ubuntu GNOME, child setup failures, linker conflicts, font/migration/source-sync/rebind failures reach final status; independent children continue | Partial setup recovery, repeated invocation, final workstation state |
| Linking/migrations | Absent or owned targets only; real files/foreign links are retained; old fixed-backup overwrite removed; machine-local Git/Pi state retained; explicit known migrations enabled | Filesystem permissions, existing layouts, source moves, atomic writes and link lifetime |
| Cleanup | `--cleanup` previews; Arch obsolete names never reach Ubuntu; `--remove-obsolete` needs a terminal + typed `remove`; native orphan removal is separately requested; npm/config directories are retained | Full recursive native plans, dependencies, native final prompts, management/security-agent review |
| GNOME/appearance | Ubuntu GNOME 50 target; reviewed Pop pin supports 51; accepted Pop-only gap above 51 preserves native moves; other required extension/config failures still fail | Acquisition/schema compatibility, extensions, tray/panel/clipboard/fonts/themes, login reload, Wayland shortcuts |
| Development stack | Explicit CLI/editor/language/container/harness recipes, minimums/capabilities and owners retained | Neovim/plugins/Treesitter, IDE GPU runtime, toolchains/gems/Composer, Docker/Compose/Buildx, mkcert trust, VPN/split DNS/watch limits |
| Hardware/managed software | Preserve driver flavor, holds/pins, automatic security updates and IT-managed agents; GPU apps remain capability-gated; NinjaOne stays opt-in | Driver activation/MOK/CUDA/Vulkan, power/lid/audio/KVM, ZSA keyboard permissions, vendor agent/timer health |
| Routine maintenance | Required repository commands absent from PATH fail; custom missing steps may skip; daily resync/restart and weekly force/native-preview ordering retained | Repo pulls, first-run links, interrupted maintenance, user self-updaters and security-policy deferrals |

Read-only regression seam: `tests/test_maintenance_decisions.py` accepts supplied
host/desktop/entrypoint facts and temporary stamp state. Its command guards prevent
package/network/service operations. Existing CLI ownership checks cover absent,
owned, foreign, dangling and directory-link conflicts. These checks are runnable
after execution is separately authorized; they were not executed for this change.

Remaining direct Arch calls are purpose-bound: AUR package/dependency scanning,
Arch native status/install/update/removal, firmware/multilib, driver/source
ownership checks, Arch-only disk provisioning, legacy Zed transition and NinjaOne
repackaging. These consumers remain needed and must not be removed merely because
an Ubuntu backend exists.
