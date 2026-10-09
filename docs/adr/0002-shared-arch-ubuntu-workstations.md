---
status: accepted
---

# Share workstation workflows across Arch and Ubuntu

Support rolling Arch Linux and Ubuntu 26.04 LTS in this repository, sharing profiles, application configuration, and maintenance commands. Keep one setup runner and add small distro-specific package backends and per-app acquisition recipes; duplicating setup trees would duplicate configuration and recreate the maintenance burden this change is intended to remove. App parity means the same applications, commands, and workflows, with compatible versions allowed to differ.

Ubuntu support starts from an installed GNOME workstation with sudo and permission to add software sources. All existing profiles remain available; disk provisioning stays Arch-only, and work-managed drivers and security agents are preserved. Prefer compatible distro packages, then official vendor APT repositories; other formats or verified upstream releases require a documented per-app exception and an update owner. Incompatible GNOME extensions require an explicit exception rather than forced loading. Keep the common daily/weekly commands, preserve Ubuntu automatic security updates, and keep release upgrades and package removals out of unattended daily maintenance; failed updates return failure and cannot write a success stamp.

## Consequences

Package names alone are insufficient: launchers, compatible versions, configuration paths, extension schemas, and update ownership must also be checked. The [implementation spec](../specs/arch-ubuntu-workstations.md) labels conservative defaults for unanswered architecture, existing-install, editor-source, and cleanup choices. The maintainer excludes OS-changing tests: use non-mutating verification and explicitly disclose unverified runtime behavior.
