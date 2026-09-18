# Remote Agent Control

## Commands

| Command | Effect |
|---------|--------|
| `/rc` or `/rc start` | Start the remote bridge inside this Pi process |
| `/rc stop` | Stop accepting Telegram messages; Pi sessions are untouched |
| `/rc status` | Show login and bridge state |
| `/rc login` | Link a BotFather token, the owner, and a private forum group |
| `/rc logout` | Stop the bridge and delete local credentials |

### Login

`/rc login` runs only in the local Pi UI, so credentials never pass through an
unauthenticated remote channel.

1. Create a bot with @BotFather and paste its token when prompted. The token is
   checked with `getMe` before anything else happens.
2. Create a private Telegram group, enable Topics, and add the bot as an
   administrator with the Manage Topics right.
3. Send `/rc_login <code>` in that group, using the one-time code Pi shows. The
   code expires after five minutes.

The sender of the code becomes the only allowlisted user, and the group becomes
the approved forum group. Login rejects direct messages, groups without Topics,
public groups, senders who are not group administrators, and bots without
administrator/Manage Topics rights. It then creates a control topic (reused on
re-login to the same group) to prove the bot can create topics and post.

The token, owner, and group are written to
`${XDG_CONFIG_HOME:-~/.config}/pi-remote-control/credentials.json` (`0600`),
outside the synced `~/.pi/agent` tree. `/rc logout` deletes that file; revoke the
token in @BotFather to disable the bot itself.

### Bridge lifecycle

The bridge is a long-polling task inside the running Pi process, not a daemon.
It stops on `/rc stop`, `/rc logout`, or `session_shutdown` (quit, reload, and
session switches), so nothing outlives the Pi process. `/rc start` re-validates
the token and group permissions and discards updates that arrived while it was
stopped. While it runs:

- Messages from anyone but the owner get one "not authorized" reply per user.
- Owner messages outside the approved group get one rejection reply per chat.
- Telegram or network failures are retried with backoff; the bridge keeps running.

Owner messages in the group are currently shown as local notifications; routing
them into Pi sessions is not implemented yet.

### Tests

```bash
node --test pi/extensions/remote-control/*.test.ts
```

Sources use only erasable TypeScript and `.ts` import specifiers, so Node's
built-in type stripping runs them directly.

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

The coordinator also owns the login handshake and bridge lifecycle, using an
injected `TelegramBotApi` (`telegram.ts` is the fetch-based implementation).

Adapter-backed tests: `coordinator.test.ts` covers repository approval, durable
relationships, grouping/attach, and duplicate workspace rejection;
`lifecycle.test.ts` covers login, owner allowlisting, group validation, start/stop,
and logout against a fake Bot API.


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
