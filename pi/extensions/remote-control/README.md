# Remote Agent Control

## Coordinator foundation

`coordinator.ts` is the high-level seam for remote control. It owns the approved
repository allowlist and the durable relationship between a repository, workspace,
branch, Pi session, and Telegram session topic. Telegram, Pi, Git workspaces,
credentials, and persistence are injected adapters; coordinator tests use fakes and
do not import vendor SDKs.

`state.ts` contains optional machine-local JSON adapters. Keep their files under
`~/.config` or `~/.local/state` and never place them under the synced `pi/` tree:
credentials and remote-control state are intentionally machine-local. The JSON
credential adapter writes directories as `0700` and files as `0600`.

Session creation is serialized and checks workspace ownership both before and after
workspace preparation. If Pi, Telegram, or persistence fails, already-created
resources are rolled back where their adapter supports removal.

The adapter-backed tests are in `coordinator.test.ts`. They cover repository
approval, durable relationships, grouping/attach, and duplicate workspace rejection.


This context defines the concepts used to control persistent Pi agent sessions remotely through Telegram while preserving repository and workspace safety.

## Language

**Remote control**:
An explicitly started Telegram connection to the currently running Pi process. It is inactive until `/rc` is started and ends when `/rc stop`, `/rc logout`, or Pi shutdown stops it.
_Avoid_: daemon, always-on service

**Agent session**:
A persistent Pi conversation associated with one repository, one Git worktree, one branch, and one Telegram forum topic.
_Avoid_: subagent, task

**Workspace**:
The Git worktree in which an agent session reads and modifies files. Concurrent agent sessions never share a workspace.
_Avoid_: checkout, folder

**Repository**:
An approved local project path that remote control may expose to agent sessions.
_Avoid_: arbitrary path

**Session topic**:
A private Telegram forum topic representing one agent session. It carries prompts, progress, approvals, and results for that session.
_Avoid_: channel, thread

**Control topic**:
The private Telegram forum topic used for repository and session management rather than agent work.
_Avoid_: admin chat

**Repository registry**:
The local allowlist of repositories that remote control may use. Starting `/rc` in a repository registers that repository for the current control session.
_Avoid_: workspace list

**Remote bridge**:
The temporary process inside Pi that translates Telegram messages and UI interactions into Pi session operations. It is started explicitly by `/rc` and is not an independent background service.
_Avoid_: bot server

**Cleanup**:
An explicit, independently confirmed operation that archives a Telegram topic, removes Pi session history, or removes a Git worktree and branch. Cleanup never happens implicitly because an agent becomes idle.
_Avoid_: delete, reset
