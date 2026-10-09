## Problem Statement

The maintainer uses Arch Linux personally but must use Ubuntu 26.04 LTS at work. The repository currently assumes pacman and the AUR throughout installation, updates, package checks, cleanup, and some system configuration. Maintaining a second repository would duplicate the shared stack, setup profiles, dotfiles, and maintenance workflows.

The maintainer needs app parity across both GNOME workstations: the same selected applications, commands, configuration, and workflows, while allowing compatible application versions to differ. Installing an application once is insufficient if its selected app source has no update owner.

## Solution

Support rolling Arch Linux and Ubuntu 26.04 LTS in one repository. Retain shared setup profiles, application configuration, and familiar bootstrap, sync, daily, and weekly commands. Detect the distribution automatically and use small native package backends plus explicit per-app acquisition/update recipes wherever distro packages are insufficient.

Ubuntu support starts from an installed GNOME desktop with sudo and permission to add software sources. Prefer compatible distro packages, then official vendor APT repositories. Other formats or verified upstream releases are documented exceptions with a defined update owner. Preserve work-managed drivers, security agents, and Ubuntu automatic security updates.

Automated validation must not change the operating system. Validate read-only decisions and static script correctness; report installation, update, hardware, and GNOME runtime behavior as unverified unless separate authorized usage supplies evidence.

## User Stories

1. As a workstation user, I want one repository for Arch and Ubuntu, so that I maintain my setup once.
2. As a workstation user, I want the distribution detected automatically, so that I do not select the wrong package manager.
3. As a workstation user, I want unsupported distributions and releases rejected clearly before changes, so that an incompatible setup cannot partially alter my machine.
4. As a workstation user, I want the same shared stack on both distributions, so that my daily workflows transfer between machines.
5. As a workstation user, I want compatible application versions rather than identical versions, so that each distribution can use suitable packages.
6. As a workstation user, I want work, personal, and devcontainer setup profiles on both distributions, so that machine purpose remains independent of distribution.
7. As a workstation user, I want setup profiles to remain additive, so that one machine can serve several purposes.
8. As a workstation user, I want existing saved identity and setup preferences preserved, so that adding Ubuntu support does not make me repeat setup decisions.
9. As a workstation user, I want shared dotfiles and configuration linking preserved, so that I edit configuration in one place.
10. As a workstation user, I want setup to handle different usernames and clone locations, so that the repository remains portable.
11. As an Ubuntu user, I want setup to start from my installed GNOME desktop, so that I can configure the workstation without replacing its operating system.
12. As an Arch user, I want existing installation and maintenance behavior preserved, so that Ubuntu support does not regress my personal workstation.
13. As a workstation user, I want familiar bootstrap and sync entrypoints, so that distro support does not introduce a second orchestration workflow.
14. As a workstation user, I want individual app setup commands to remain usable, so that I can repair one tool without running full setup.
15. As a workstation user, I want repeatable setup without duplicate repositories, packages, links, or settings, so that sync remains safe to rerun.
16. As a workstation user, I want missing required applications reported as failures, so that a partial setup is not presented as app parity.
17. As a workstation user, I want package names separated from application and command names, so that differing distro names do not break my configuration.
18. As a developer, I want commands such as fd and bat available to subprocesses as well as my shell, so that editor integrations work on Ubuntu.
19. As a developer, I want the installed Neovim and Treesitter versions to satisfy the shared plugin requirements, so that an apparently successful installation does not break my editor.
20. As a Zed user, I want my selected installation preserved and its launcher resolved correctly, so that an Arch-specific cleanup rule cannot delete my Ubuntu editor.
21. As a developer, I want Docker Engine, Compose, and Buildx treated as a coherent installation, so that finding the docker executable does not incorrectly imply a complete development environment.
22. As a developer, I want devcontainer DNS, certificates, VPN prerequisites, and file-watcher settings handled appropriately for my distro, so that the same development workflows remain available.
23. As a workstation user, I want compatible GNOME shortcuts, panel configuration, clipboard history, and tiling, so that my desktop workflows remain familiar.
24. As a workstation user, I want incompatible GNOME extensions reported instead of force-loaded, so that setup does not knowingly destabilize the shell.
25. As a workstation user, I want explicitly accepted feature gaps distinguished from failures, so that I understand what my workstation supports.
26. As a workstation user, I want the fonts required by my shared configuration installed through suitable sources, so that editor and terminal appearance remains usable.
27. As a workstation user, I want every selected application to have a documented app source and update owner, so that applications remain maintainable after initial installation.
28. As an Ubuntu user, I want compatible native packages preferred over extra sources, so that maintenance stays simple.
29. As an Ubuntu user, I want official vendor APT repositories used where appropriate, so that vendor software can participate in normal package updates.
30. As a workstation user, I want release downloads and self-updating apps handled explicitly, so that standalone DEBs or archives are not falsely assumed to update through APT.
31. As a workstation user, I want source conflicts reported without silent fallback or duplicate installations, so that update ownership remains understandable.
32. As an Arch user, I want AUR packages and dependencies scanned before installation or upgrade, so that existing supply-chain protections remain effective.
33. As a workstation user, I want source verification and repository-scoped signing keys where applicable, so that adding a vendor source does not broaden trust unnecessarily.
34. As a workstation user, I want user-level language and agent tooling to remain user-owned, so that distro support does not introduce root-owned npm installations.
35. As a workstation user, I want dfa-daily and dfa-weekly to remain my common maintenance commands, so that I do not memorize distro-specific update routines.
36. As a workstation user, I want each installed application's chosen update owner used, so that alternate Ubuntu acquisition methods do not leave apps stale.
37. As a workstation user, I want cooldown and force-update behavior preserved, so that routine maintenance remains predictable.
38. As a workstation user, I want update failures to return nonzero and avoid success stamps, so that failed upgrades are retried and accurately reported.
39. As a workstation user, I want aggregate setup and maintenance failures retained, so that a final success message cannot hide failed steps.
40. As a work user, I want automatic security updates, managed drivers, and security agents preserved, so that workstation setup respects existing management.
41. As a workstation user, I want daily unattended updates to exclude package removals and release upgrades, so that routine maintenance cannot silently cross those boundaries.
42. As a workstation user, I want distro-appropriate cleanup with explicit removal authorization, so that Arch orphan lists are not incorrectly applied to Ubuntu.
43. As a GPU user, I want optional GPU applications gated by working capabilities and existing drivers preserved, so that package installation does not imply hardware readiness.
44. As a work user, I want NinjaOne's existing standalone lifecycle preserved with native Ubuntu packaging where applicable, so that security-agent setup is not silently added to full bootstrap.
45. As a maintainer, I want validation that cannot change the operating system, so that checking this feature cannot install, remove, or reconfigure system software.
46. As a maintainer, I want tested, inspected, and unverified behavior distinguished in reports, so that static checks are not misrepresented as workstation validation.
47. As a workstation user, I want package purposes, commands, source exceptions, and update responsibilities documented together, so that I can understand and maintain both machines.

## Implementation Decisions

- **Accepted scope:** support rolling Arch and Ubuntu 26.04 LTS with GNOME, all existing additive setup profiles, and app parity as defined above. Ubuntu OS installation is not part of this feature.
- **Shared architecture:** retain a single profile runner and shared application configuration. Add a small distro boundary for detection, package status, native installation/removal, source preparation, system upgrades, and orphan handling. Keep AUR-specific behavior isolated to Arch. Do not build a generic installer plugin framework or duplicate distro setup trees.
- **Detection:** derive distro and release from operating-system metadata; do not persist a user-selectable distro that can contradict the host. Reject unsupported systems before privileged operations. Standalone setup and maintenance entrypoints must use the same detection and backend selection.
- **Package and application identity:** maintain explicit distro package mappings and per-app recipes. Do not translate arbitrary AUR names to APT names or assume executable presence proves package ownership or required capabilities. Normalize commands and desktop launchers without overwriting unrelated user files.
- **Source selection:** use compatible official distro packages first, official vendor APT repositories second, and documented per-app exceptions otherwise. Each recipe must identify installation, version/capability checks, configuration expectations, and its update owner. Local DEBs and archives without an update repository need explicit refresh handling; preserve genuine app self-updaters where selected.
- **Source trust:** retain existing AUR package/dependency scans and fail-closed behavior. Avoid pipe-to-shell installers. Stage verified upstream artifacts before replacing working installations. Scope APT signing keys to their repositories and register sources idempotently. Do not silently choose another source after acquisition fails.
- **Shared configuration:** retain saved profile, identity, NVIDIA preference, machine-type, and default-harness behavior through existing configuration accessors. Preserve current user-home handling, symlink ownership, real user files, clone-path resolution, and schema-migration conventions. Do not rename the repository or its installed command/config namespace as part of this feature.
- **Consumer migration:** replace direct Arch package-manager assumptions throughout setup, bootstrap, sync, post-link checks, update wrappers, obsolete-package cleanup, hardware/package detection, and maintenance help text. Changing the central library alone is insufficient.
- **Version contracts:** validate the actual installed application and its dependencies against shared configuration requirements. Current editor configuration needs Neovim 0.12+ and tree-sitter CLI 0.26.1+, exceeding Ubuntu 26.04's native versions. Application/version presence alone must not mark the editor compatible.
- **Desktop configuration:** acquire extension versions compatible with the installed GNOME shell, check extension schemas before applying their settings, and handle conflicts with Ubuntu's defaults. Preserve shortcuts and intended workflows. Do not carry the global extension-version-validation bypass into Ubuntu support; missing required features fail unless explicitly excepted.
- **App-specific compatibility:** confine legacy Zed cleanup to the Arch package transition; preserve official Ubuntu user installations. Normalize Zed and Stably Orca launcher differences. Cover PHP configuration locations, required fonts/themes, Python/build prerequisites, GPU runtimes, and complete Docker/Compose/Buildx availability through distro-appropriate recipes.
- **Hardware and managed software:** retain capability gating for GPU apps and machine-type policies. Preserve installed driver flavor and work-managed security agents; never use bootstrap to replace them silently. Keep NinjaOne opt-in and standalone, share credential protection/health behavior, and use the vendor's native Ubuntu package lifecycle where installation is requested.
- **Update contract:** retain the existing daily cooldown, force override, bootstrap cooldown, always-update sync behavior, and daily/weekly sequencing. Dispatch installed apps through their selected update owners. Preserve Ubuntu's automatic security updates and avoid overriding package holds or management policies. Release upgrades are never part of ordinary update commands.
- **Failure contract:** explicitly propagate failed package-manager and update-owner operations. A successful-update stamp means every requested update step completed successfully; failed steps cannot advance it. Distinguish policy-deferred operations and accepted skips from completed updates. Aggregate failures must survive bootstrap, sync, and daily/weekly summaries even when later independent steps continue.
- **State migration:** preserve existing Arch cooldown state when introducing distro-neutral or backend-aware stamps. Follow existing schema-migration practices if installed command links or recorded state require migration. Do not silently rewrite machine-local preferences.
- **Removal contract:** retain distro-specific orphan semantics, keep removals out of unattended daily maintenance, and report packages to be removed before any separately authorized cleanup. Do not reuse Arch obsolete-package names as an Ubuntu removal list.
- **Documentation:** update the package-purpose catalog with the full selected-app matrix, source exceptions, minimum requirements, and update owners. Update command help, welcome/alias descriptions, and workstation instructions so they describe both distros consistently. Keep installable support separate from verified runtime claims.
- **Defaults for unanswered interview choices:** the final interview round was not answered. For this spec, use x86_64/amd64 as the initial target; retain compatible existing installations with a known update owner and report conflicts; prefer verified compatible stable upstream editor tools over downgrading shared plugins; require explicit removal confirmation, with --yes alone insufficient. These are conservative synthesis defaults, not previously confirmed user answers. Do not silently substitute broader architecture support, source migration, plugin downgrades, or unattended removals.

## Testing Decisions

- **User constraint:** do not run tests that can change the operating system. Exclude installer, upgrade, cleanup, driver, source-registration, service, and desktop-setting workflows from execution-based tests. This applies to the proposed disposable-VM workflow as well as the current workstation; VM provisioning and live OS validation are not authorized by this spec.
- **Primary seam:** test read-only planning/selection behavior at the shared distro/package boundary: supported-host detection, profile-to-application selection, package/command mapping, minimum-version compatibility, selected app source/update owner, and whether an action requires removal approval. Prefer existing pure decisions; expose only the smallest read-only seam needed where a decision is currently entangled with mutation.
- **Good tests:** assert external decisions and diagnostics from representative host/profile/application inputs. Cover supported and unsupported hosts, compatible and incompatible versions, conflicting sources, accepted exceptions, and removal classification. Do not mirror shell implementation details, function names, or a full duplicate package catalog.
- **Isolation:** all fixtures and writes stay in temporary directories. Tests must perform no network access and launch no privileged commands, package managers, service managers, drivers, live GNOME commands, or mutating public setup/update entrypoints. Host metadata, installed-package facts, and capability/version facts are supplied as data rather than gathered by changing the machine.
- **Prior art:** existing cloud-configuration and skill-sync checks use Python's standard library, temporary directories, subprocess capture, and guard commands to prevent forbidden side effects. Reuse their isolation approach for pure checks; do not copy their script execution pattern into OS-changing workflows.
- **Static gate:** retain Bash syntax and ShellCheck checks across all shipped shell entrypoints. Review direct package-manager calls, privileged writes, explicit error propagation, cooldown stamping, source ownership, and conditional failure paths without executing mutating operations.
- **Regression evidence:** add the smallest runnable pure check for nontrivial selection/version/removal logic. Inspect that every failed update branch propagates an error and bypasses success stamps. Do not claim package-manager failure propagation was runtime-tested if proving it would require executing an OS-changing workflow.
- **Completion evidence:** deliver the source/update matrix, read-only checks, static-check results, and a clear inventory of unverified install/update/desktop/hardware paths. Candidate vendor support and compatible package metadata are evidence of feasibility, not proof of successful installation or runtime app parity. Do not make full-workstation verification a hidden requirement that causes prohibited tests to run.

## Out of Scope

- A second Ubuntu repository or duplicated per-distro profile/configuration trees.
- Ubuntu disk provisioning, unattended OS installation, partitioning, encryption setup, or release upgrades.
- Ubuntu releases other than 26.04 LTS, other Linux distributions, and ARM support in the initial implementation.
- Identical versions of every app across distros, unrelated application replacement, or a redesign of the shared desktop/editor workflows.
- A universal provisioning framework, speculative package-manager plugins, repository renaming, or migration of the existing installed command/config namespace.
- Disabling Ubuntu automatic security updates, overriding managed package holds, replacing existing work-managed drivers/security agents, or automatic NinjaOne enrollment.
- Silent source fallback, duplicate installations, forced loading of incompatible extensions, and package removals during unattended daily maintenance.
- Tests or validation runs that install/remove/upgrade packages, register system sources, write system configuration, change services/drivers/GNOME settings, or provision operating systems/VMs.
- Claiming real installation, update, desktop, VPN, suspend, audio, or GPU behavior has been verified when only read-only or static evidence exists.

## Further Notes

- This spec synthesizes the accepted cross-distro ADR and glossary, the repository analysis, and the maintainer's latest testing constraint. The earlier proposed live-workstation validation gate was not accepted and is replaced by the non-mutating testing policy above. Publishing this spec does not implement distro support or authorize package changes.
- Architecture coverage, existing-install handling, editor source strategy, and removal confirmation were unanswered during the interview. Their conservative defaults are stated explicitly under Implementation Decisions so an agent can proceed without treating them as historical user approvals.
- Detailed factual feasibility remains implementation work: complete the app catalog, verify artifact integrity/update endpoints, and resolve Voxtype's GNOME dictation dependency on dotool. If a selected app has no feasible source/update path, report the specific gap and request an explicit exception instead of quietly omitting it or substituting an application.
- Primary-source evidence includes [Ubuntu 26.04 Neovim](https://packages.ubuntu.com/resolute/amd64/neovim), [pinned Treesitter requirements](https://github.com/nvim-treesitter/nvim-treesitter/blob/8b98b4470eb326f1c7b50dae79f8c963568e5720/README.md), [Docker's Ubuntu support](https://docs.docker.com/engine/install/ubuntu/), [TablePlus's 26.04 repositories](https://tableplus.com/download/linux), [OpenVPN3 availability](https://community.openvpn.net/Pages/OpenVPN3Linux), [Zed Linux installation](https://zed.dev/docs/linux), [Stably Orca installation/update behavior](https://www.onorca.dev/docs/install), [Voxtype installation](https://voxtype.io/docs/), [Obsidian's update distinction](https://obsidian.md/help/updates), and [Ollama Linux updates](https://docs.ollama.com/linux). Recheck changing source/version facts during implementation.
- Stage the work as native backends and failure contracts, shared orchestration/CLI tooling, remaining app/desktop recipes, then non-mutating verification and documentation. A partial package backend is not completion of the selected-app support matrix; runtime verification remains separately disclosed.
