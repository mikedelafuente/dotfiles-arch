# Remote Agent Control

## Commands

| Command | Effect |
|---------|--------|
| `/rc` or `/rc start` | Start the remote bridge inside this Pi process and expose this conversation |
| `/rc stop` | Stop accepting Telegram messages; Pi sessions are untouched |
| `/rc status` | Show login and bridge state, and the session topics being routed |
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
- Messages posted with "Remain anonymous" cannot be tied to the owner and get
  one reply asking to turn it off (login rejects an anonymous code the same way).
- Network failures are retried with backoff; the status line returns to
  `rc: on` once polling recovers.
- A revoked token (401) or another poller on the same bot (409: a second Pi
  running `/rc`, or a webhook) stops the bridge with an error instead of retrying.

`/rc stop`, `/rc logout`, and Pi shutdown also cancel a login that is still
waiting for its code.

Owner messages in the control topic (or the General topic) are shown as local
notifications; repository and session management there is not implemented yet.
Messages in a topic with no running session get one "not connected" reply.

### Current session

Run inside a Git repository, `/rc` exposes the running Pi conversation as an
agent session before it starts polling:

- The repository is added to the repository registry if it is not already there.
  For a linked worktree, that is the main checkout; the workspace is the worktree.
- The session topic is named `<repository> / <session> / <branch>`. The session
  name is the Pi session name (`/name`), else the name the topic already had, else
  `agent`. The branch is read once, at `/rc` time.
- A workspace keeps one session topic. A later Pi conversation in the same
  workspace takes that topic over: the stored agent session is rebound to the new
  conversation, and the topic is renamed if the name or branch changed. A topic
  deleted in Telegram is replaced with a new one.

Outside a Git repository the bridge still starts, but no session is exposed.

In the session topic:

| Message | Effect |
|---------|--------|
| Plain text while Pi is idle | A new prompt |
| Plain text while Pi is working | Steering for the current run |
| `/rc followup <message>` | A follow-up queued after the current run (a prompt if idle) |
| Any other `/rc …` | A usage reply; nothing reaches Pi |

Other `/` text is passed to Pi verbatim; prompt templates and skills are not
expanded yet.

Every run of this conversation is mirrored into its topic, including prompts
typed locally:

- One progress message per run, edited in place at most every three seconds:
  the prompt, elapsed time, and the last eight tool calls as `name: main argument`.
  It ends as `Done in …` or `Failed after …` with a tool-call count.
- The final assistant response is sent as a separate message. Responses longer
  than 3500 characters are cut at a paragraph, line, or word boundary, with a
  note that the full response is in the Pi session. Nothing is attached.
- Tool output is never sent; it stays in the Pi session history.
- `/rc stop` posts `Disconnected` in the topic. Delivery failures appear as local
  warnings and do not stop the bridge.

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

It also routes session-topic messages to an injected `LivePiSession` and turns
`recordActivity()` reports (`index.ts` maps Pi's agent and tool events to them) into
progress edits and responses. `messages.ts` holds the pure text formatting.

Adapter-backed tests: `coordinator.test.ts` covers repository approval, durable
relationships, grouping/attach, and duplicate workspace rejection;
`lifecycle.test.ts` covers login, owner allowlisting, group validation, start/stop,
and logout against a fake Bot API; `session-bridge.test.ts` covers exposing the
current conversation, topic rebinding, message routing, progress, and response
condensing. Shared fakes live in `test-support.ts`.


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
