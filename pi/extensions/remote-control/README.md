# Remote Agent Control

## Commands

| Command | Effect |
|---------|--------|
| `/rc` or `/rc start` | Start the remote bridge inside this Pi process and expose this conversation |
| `/rc stop` | Stop accepting Telegram messages; Pi sessions are untouched |
| `/rc status` | Show login and bridge state, and the session topics being routed |
| `/rc new <name>` | Adopt this branch or worktree as agent session `<name>`, or start one in a new worktree |
| `/rc sessions` | List agent sessions by repository, with their status |
| `/rc attach <session>` | Reconnect a disconnected agent session, or an earlier conversation by Pi session id |
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
session switches), so nothing outlives the Pi process. After `/new` or `/reload`,
typed locally or sent from the session topic, it starts again on its own (see
[Reconnecting after /new and /reload](#reconnecting-after-new-and-reload)).
`session_shutdown` also stops the agent processes `/rc new` and `/rc attach`
started; `/rc stop` leaves them running and `/rc start` routes their topics again. `/rc start` re-validates
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

Owner `/rc` commands in the control topic (or the General topic) manage agent
sessions (see [Agent sessions](#agent-sessions)); other owner messages there are
shown as local notifications, and a session-topic command picked from the `/`
menu gets a reply pointing at the session topics. Messages in a topic with no
running session get one "not connected" reply. `/rc start` also sets the group's
Telegram `/` menu (see [Command discovery](#command-discovery)).

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
  conversation, and the topic is renamed if the name or branch changed. The
  conversation it replaced is kept as an earlier conversation of that session,
  attachable by its Pi session id, as long as its Pi history exists. A topic
  deleted in Telegram is replaced with a new one.

Outside a Git repository the bridge still starts, but no session is exposed.

In the session topic:

| Message | Effect |
|---------|--------|
| Plain text while Pi is idle | A new prompt |
| Plain text while Pi is working | Steering for the current run |
| `/rc followup <message>` | A follow-up queued after the current run (a prompt if idle) |
| `/rc commands` (or `/rc`, `/rc help`) | Everything this topic accepts (see [Command discovery](#command-discovery)) |
| `/rc stop-agent` | Aborts the current run once you confirm (see [Approvals](#approvals)) |
| `/rc compact [instructions]`, `/rc thinking <level>`, `/rc model [provider/model]`, `/rc name <name>`, `/rc session` | Runs that Pi built-in (see [Command discovery](#command-discovery)) |
| `/rc new`, `/rc reload` | Replies that remote control will reconnect, then runs `/new` or `/reload` in the local Pi (see [Reconnecting after /new and /reload](#reconnecting-after-new-and-reload)) |
| `/rc <template or skill> [args]` | That prompt template or skill, as if typed as `/<name>` |
| `/rc <extension command> [args]` | Runs it once you approve (see [Approvals](#approvals)); never `/rc` itself |
| Any other `/rc …` | An "unknown command" reply; nothing reaches Pi |

Every command above also works as `/<name>`, by its own name or its menu name
(`/skill_tdd` for `/rc skill:tdd`), with or without `@bot`. A menu command this
topic's conversation does not have gets an "unknown command" reply; other `/` text,
such as a path, is passed to Pi as typed. Messages that arrive while a prompt is starting or Pi is compacting
are held and delivered in order once Pi can accept them (`pi-delivery.ts`), so a
burst of messages is never lost to Pi rejecting a concurrent prompt. Replies in the
General topic count as General, not as the topic of the message they reply to.

Every run of this conversation is mirrored into its topic, including prompts
typed locally:

- One progress message per run, edited in place at most every five seconds:
  the prompt, elapsed time, and the last eight tool calls as `name: main argument`.
  It ends as `Done in …` or `Failed after …` with a tool-call count. Rate-limited
  (429) updates are retried after Telegram's `retry_after`.
- The final assistant response is sent as a separate message. Responses longer
  than 3500 characters keep their opening and conclusion, cut at paragraph, line,
  or word boundaries, with a note that the full response is in the Pi session.
  Nothing is attached.
- A failed run is reported only once Pi settles, because extensions see the
  failure before Pi decides to auto-retry it.
- Tool output is never sent; it stays in the Pi session history.
- `/rc stop` posts `Disconnected` in the topic. Delivery failures appear as local
  warnings and do not stop the bridge.
- When rebinding, only a topic Telegram reports as deleted is replaced; any other
  failure makes `/rc` fail instead.

### Reconnecting after /new and /reload

`/new` and `/reload` replace Pi's extension runtime, which stops remote control
with it. When remote control was running, the next runtime starts it again, as `/rc`
would (`reconnect.ts`):

- the workspace keeps its session topic, rebound to the new conversation and renamed
  if the name or branch changed;
- after `/new`, the replaced conversation is kept as an earlier conversation,
  attachable by its Pi session id, as long as its Pi history exists.

This holds whether `/new` or `/reload` was typed in Pi or sent from the session topic.
From the topic, `/rc new` (or `/new`, or the menu entry) first replies that a new
conversation is starting and remote control will reconnect, then the local Pi runs
`/new` through this extension's unlisted `/rc replace-runtime` subcommand, since only
a command gets `newSession()` and `reload()`. `/rc reload` works the same way.

The reconnect is a stop followed by a start, so the topic gets the usual
`Disconnected` and `Connected` messages, Telegram messages sent in between are
discarded, open approvals are withdrawn, and the agent processes `/rc new` and
`/rc attach` started are closed. A failed restart (the credentials were removed, say)
is reported in Pi like a failed `/rc`, and remote control stays off; nothing retries.
Quitting Pi, `/resume`, `/fork`, and a `/new` or `/reload` while remote control is
stopped never start it. Pi re-imports the extension for every runtime, so whether to
reconnect is kept on `globalThis`, and consumed by the next `session_start`.

### Agent sessions

An agent session is one Pi conversation with its own repository, workspace, branch,
and session topic. Two sessions never share a workspace.

| Command | Where | Effect |
|---------|-------|--------|
| `/rc new <name>` | Local Pi | On a feature branch or in a linked worktree: the current conversation becomes agent session `<name>` in its topic (renamed to match). On the main line or a detached HEAD in the main checkout: a new session, as below |
| `/rc new <repository> <name>` | Control topic | A new session in an approved repository, named by its registry name or path. With only `<name>`, pick the repository from buttons |
| `/rc sessions` | Both | Sessions grouped by repository, with their status |
| `/rc attach <session>` | Both | Reconnects a disconnected session by name or id, or an earlier conversation by Pi session id. In the control topic without `<session>`, pick a disconnected session from buttons |
| `/rc stop-agent [session]` | Control topic | Aborts a connected session's current run once you confirm; without `[session]`, pick it from buttons |
| `/rc help` | Control topic | The control-topic commands |

A new session gets, together or not at all:

- a worktree at `<repository>.worktrees/rc-<name>` on a new branch `rc/<name>`,
  started from the main line: the remote's default branch, else `main`, else
  `master`. An existing branch of that name is refused rather than reused;
- a Pi conversation named `<name>`, running as a `pi --mode rpc` child of this Pi
  in that worktree, with the same extensions, skills, and session history as a
  local Pi;
- a session topic named `<repository> / <name> / rc/<name>`.

If any step fails, the ones already done are undone: the topic is deleted, Pi is
stopped, and the worktree and branch are removed. Remote requests can only use
repositories already in the registry; running `/rc` locally is the only way to add
one. A name that would give the same branch as another session in the repository
is refused, as is a workspace another session is assigned. If a rollback step
itself fails, the rest still run, and the error names what was left behind: the
topic, the Pi process, or the worktree and branch.

`/rc sessions` reports each session as:

| Status | Meaning |
|--------|---------|
| running | Its Pi is running; its topic is routed while remote control runs |
| disconnected | Not running, but its workspace exists and it can be resumed: `/rc attach` it |
| open in this Pi / another Pi (process N) | A Pi remote control is not routing has it open; close it there before attaching |
| stale | Its Pi history is gone |
| missing workspace | Its worktree was removed |

Earlier conversations are listed under their session with the same statuses and
the `/rc attach <Pi session id>` that reconnects them.

`/rc attach` resumes the stored Pi session file in its workspace, checks Pi really
resumed that conversation, then posts `Reconnected` in the session topic (renamed
if the name or branch changed, replaced if it was deleted). It refuses stale and
missing-workspace sessions, sessions whose repository was removed from the
registry, and conversations another Pi has open (see [Session leases](#session-leases)),
naming that Pi's process. A name that matches more than one session asks for the id.

A session `/rc new` created that never got a prompt has no Pi history yet,
because Pi writes the session file with its first response. It is attachable, not
stale: Pi restarts it under the same session id (`--session-id`). Once a run has
started, a missing history makes it stale, even if Pi died before answering, so
attach never quietly restarts a lost conversation empty.

Attaching an earlier conversation makes it the session's current one again, in the
same topic, and keeps the one it replaces as an earlier conversation. It is refused
while the session's current conversation is connected or open in another Pi, since
two conversations never share a workspace.

### Session leases

Pi does not lock session files: it only creates one exclusively when it first
writes it, and two Pi processes appending to one file corrupt it. So every Pi
running this extension, including ones that never run `/rc` and the agents `/rc
new` starts, records a lease for its current conversation on `session_start` and
removes it on `session_shutdown`:
`${XDG_STATE_HOME:-~/.local/state}/pi-remote-control/leases/<Pi session id>/<pid>`,
one file per process, so one Pi releasing its lease never hides another's. A lease
whose process is gone (or whose PID now belongs to a process that started later) is
stale: it is removed and ignored, so a crashed Pi never blocks attach.

Leases only cover Pi processes on this machine that load this extension. A Pi
without it, one started with extensions disabled, or one on another machine
sharing the session files leaves no lease, and attach cannot see it.

In an agent's topic, messages work as in [Current session](#current-session); the
agent receives them through Pi's RPC `prompt`. An extension command, as `/rc <name>`
or `/<name>`, reaches it only once you approve it. An
extension's confirmation or selection dialog is asked in the topic with buttons (see
[Approvals](#approvals)); a dialog that needs typed input is cancelled with a note.
Extension warnings and errors are posted in the topic. If the agent's Pi exits, the
topic says so and the session becomes disconnected.

### Command discovery

`/rc commands` in a session topic lists what that agent accepts, in one message:

- remote control's own commands: `commands`, `followup`, `stop-agent`;
- a maintained catalog of Pi built-ins that remote control runs itself, because
  Pi's command discovery leaves built-ins out and they do nothing sent as a prompt
  (`commands.ts`, in step with Pi's `BUILTIN_SLASH_COMMANDS` by hand):

  | Built-in | Effect |
  |----------|--------|
  | `/rc compact [instructions]` | Compacts the context |
  | `/rc thinking <level>` | Sets the thinking level |
  | `/rc model [provider/model]` | Sets the model; without one, lists the models Pi can use |
  | `/rc name <name>` | Renames the Pi conversation and its agent session, and retitles the topic `<repository> / <name> / <branch>` |
  | `/rc session` | The conversation's id, file, model, message counts, tokens, cost, and context use |
  | `/rc new` | Starts a new conversation in the workspace; the topic is rebound to it, and the replaced one stays attachable by Pi session id while its history exists. Its open approvals are withdrawn. An agent's conversation is named after the session |
  | `/rc reload` | Pi reloads its extensions, skills, prompts, and context files |

  An agent runs `/rc new` and `/rc reload` over RPC, and its topic stays routed
  throughout. RPC has no reload command, so an agent reloads through this
  extension's `/rc reload` in its own Pi, which calls `ctx.reload()`. The current
  conversation runs them in the local Pi, which replaces its extension runtime:
  remote control stops and reconnects on its own (see
  [Reconnecting after /new and /reload](#reconnecting-after-new-and-reload)).
  The other built-ins need Pi's terminal, local files or the clipboard, a provider
  login, or another session, and are left out;
- the prompt templates and skills Pi discovered, usable as `/rc <name>` or `/<name>`;
- the extension commands Pi discovered, which run once you approve them (see
  [Approvals](#approvals)). `/rc` itself is never run from Telegram.

Discovery is read from Pi on every request, so it follows a reload. An agent's Pi
reports its reload to the Pi that started it, which re-reads that agent's commands
before delivering its next message. A Pi that does not list its commands within ten
seconds gets a failure reply, and the topic's later messages go through.

The group's Telegram `/` menu lists `/rc`, remote control's topic commands, the
built-ins, and every command the connected conversations discovered, since Telegram
has one menu per group, not per topic. Telegram only accepts names of 1–32 of
`a-z`, `0-9`, and `_`, so names are mapped: lowercased, every other character run
becomes `_` (`skill:tdd` is `/skill_tdd`, `fix-tests` is `/fix_tests`). When two
names map to the same entry, the one listed first keeps it (topic commands, then
built-ins, then discovery order); the other still works as `/rc <name>`. The menu
is set when remote control starts and again, only if it changed, when a topic is
routed or unrouted, an agent reports a reload, `/rc reload` runs, or `/rc commands`
is asked. A menu that cannot be set is a local warning.

### Approvals

While a conversation is remote-controlled (its topic is routed by a running bridge,
or it is an agent `/rc new` or `/rc attach` started), these tool calls wait for the
owner's approval (`sensitive.ts`):

| Operation | Recognized as |
|-----------|---------------|
| Merge | `git merge`, `gh pr merge`, the `merge_this` tool |
| Branch deletion | `git branch -d/-D/--delete`, `git push --delete/--prune/--mirror`, `git push <remote> :<branch>`, `gh api -X DELETE …/git/refs/heads/…` |
| Deployment | `gh release create`, `npm`/`pnpm`/`yarn`/`bun`/`cargo publish`, `docker push`, `terraform apply`, `kubectl apply`, `helm upgrade`, a `deploy` subcommand, script, or task |
| Privileged | `sudo`, `doas`, `pkexec`, `run0`, `su` |

Recognition reads each command of a shell line, through wrappers such as `env`,
`nice`, `timeout`, and `xargs` and into `bash -c` scripts and `eval`; it prevents
mistakes, not an agent set on hiding a merge inside a script. `/rc stop-agent` asks
the same way before aborting a run, and its confirmation applies only to the run it
asked about: pressed after that run ended, it stops nothing.

The approval is a message in the session topic with Approve and Deny buttons. For
the current conversation it is also asked in the local Pi; the first answer wins and
withdraws the other. Every approval and every button selection is:

- single-use: a second press, or a press on another choice of the same message, is
  refused;
- bound to the owner (other users are told they are not authorized, and the
  approval stays open), to the topic and chat it was asked in, and to its agent
  session and operation: once that topic is rebound to another conversation, or
  the session disconnects, it no longer applies. Routing the same conversation to
  its own topic again (adopting it with `/rc new <name>`, renaming it with
  `/rc name`) keeps its approvals open;
- time-limited: after five minutes it expires, and a later press is refused.

`/rc <extension command>` asks the same way before the command runs, naming it
with its arguments: Pi runs extension commands outside the tool-call approvals, so
approving it approves everything that command does. The approval is bound to the
conversation it was asked for, and waiting for it does not hold back the topic's
other messages; anything but Approve runs nothing, and neither does a command the
conversation no longer has once you approve. Pi reports what the command does, and
how it fails, where it runs: in the agent's topic, or in the local Pi for the
current conversation. A command that itself starts a new session or reloads Pi
stops remote control there, which then reconnects as after `/new` and `/reload`; one
that forks or switches sessions leaves it stopped.

An approval that is denied or expires counts as a denial: the tool call is blocked
and Pi is told not to retry it. When Telegram decides nothing (the approval could not
be posted, or `/rc stop`, `/rc logout`, or Pi shutdown withdrew it), an agent's tool
call is blocked too, while the current conversation waits for its local answer.
Agents inherit remote control's marker (`PI_REMOTE_CONTROL_AGENT`), so any Pi an
agent starts in turn, having no one to ask, has its sensitive operations blocked.

### Tests

```bash
node --test pi/extensions/remote-control/*.test.ts
```

Sources use only erasable TypeScript and `.ts` import specifiers, so Node's
built-in type stripping runs them directly. `git-workspaces.test.ts` needs `git`;
`pi-rpc.test.ts` runs a scripted stand-in for `pi --mode rpc`, not Pi itself;
`leases.test.ts` uses real lease files and processes; `sensitive.test.ts` covers
which commands need approval; `reconnect.test.ts` covers when the next runtime
reconnects; `index.test.ts` loads the extension into a fake `ExtensionAPI` to cover
the reconnect around `session_shutdown` and `session_start`.

## Coordinator foundation

`coordinator.ts` is the high-level seam for remote control. It owns the approved
repository allowlist and the durable relationship between a repository, workspace,
branch, Pi session, and Telegram session topic. Telegram, Pi processes, Git
workspaces, session leases, credentials, and persistence are injected adapters;
coordinator tests use fakes and do not import vendor SDKs. `git-workspaces.ts`,
`pi-rpc.ts`, and `leases.ts` are the real workspace, Pi, and lease adapters.

`state.ts` contains optional machine-local JSON adapters. Keep their files under
`~/.config` or `~/.local/state` and never place them under the synced `pi/` tree:
credentials and remote-control state are intentionally machine-local. The JSON
credential adapter writes directories as `0700` and files as `0600`.

Session creation, adoption, and attach are serialized and check workspace ownership
both before and after workspace preparation. If Pi, Telegram, or persistence fails,
already-created resources are rolled back. Session status is computed when listed,
never stored.

The coordinator also owns the login handshake and bridge lifecycle, using an
injected `TelegramBotApi` (`telegram.ts` is the fetch-based implementation).

It also routes session-topic messages to an injected `LivePiSession` and turns
`recordActivity()` reports (`index.ts` maps Pi's agent and tool events to them) into
progress edits and responses. `messages.ts` holds the pure text formatting and parsing,
`commands.ts` the command catalog. Approvals and button selections go through
`owner-prompts.ts`, which issues and checks their single-use, bound, expiring buttons;
`index.ts` gates sensitive tool calls through `requestApproval()`.

Adapter-backed tests: `coordinator.test.ts` covers creating, adopting, listing, and
attaching agent sessions (including leased, unprompted, and earlier conversations),
rollback and its leftovers, repository approval, and duplicate workspace rejection;
`approvals.test.ts` covers approvals, selections, and `/rc stop-agent` (binding, expiry,
single use, withdrawal, re-routing); `commands.test.ts` covers command discovery and
routing, the built-ins (including the current conversation's `/new` and `/reload`
and the reconnect's rebinding), approved extension commands, and the Telegram menu;
`lifecycle.test.ts` covers login, owner allowlisting, group validation, start/stop,
and logout against a fake Bot API; `session-bridge.test.ts` covers exposing the
current conversation, topic rebinding, message routing, progress, response
condensing, retry-safe failure reporting, and rate limits; `pi-delivery.test.ts`
covers holding messages while a prompt starts or Pi compacts. Shared fakes live in
`test-support.ts`.


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

**Session lease**:
A machine-local record that a Pi process has a conversation open, kept by every Pi running this extension, so remote control never resumes a conversation another Pi is writing.
_Avoid_: lock

**Earlier conversation**:
A Pi conversation that ran in a workspace before a later one took over its session topic; it stays attachable by its Pi session id.
_Avoid_: old session, history

**Approval**:
The owner's answer, with a Telegram button, to a sensitive operation a remote-controlled conversation wants to perform: a merge, branch deletion, deployment, privileged command, or stopping an agent. It is single-use, expires, and is bound to the owner, the agent session, and the operation; anything but an explicit approval is a denial.
_Avoid_: permission, consent

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
