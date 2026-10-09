# Workstation setup

Shared language for the development workstations configured by this repository.

## Language

**Workstation**:
A development machine with the selected applications and a GNOME desktop.

**Shared stack**:
The applications and user configuration common to work and personal workstations.

**Setup profile**:
An additive selection of applications and workstation requirements for work, personal use, or devcontainer development. A workstation can have several setup profiles.
_Avoid_: Distro profile, mutually exclusive profile

**App parity**:
The same applications, commands, and configured workflows across supported workstations. Application versions can differ when they support those workflows.
_Avoid_: Identical versions, identical package names

**App source**:
The selected distribution channel for an application on a workstation. An application can have different sources on different distributions.

**Update owner**:
The selected mechanism responsible for keeping an installed application current, including its launcher or runtime when those need separate updates.
_Avoid_: Installed once, automatically updatable without an identified owner
