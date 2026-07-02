---
name: unity-worktree
description: >-
  Set up and manage a small pool of PERSISTENT, reusable git worktree folders
  (e.g. DevA, DevB) for a Unity project, so Unity's Library/Temp/obj cache stays warm
  instead of rebuilding every time you switch branches. Use this whenever the user
  wants to work on multiple Unity branches in parallel; complains that creating new
  worktrees or switching branches is slow because Unity re-imports assets; wants
  long-lived/reusable worktrees instead of fresh ones each time; starts new or
  existing work inside a named worktree folder; finishes work and returns a folder to
  idle on a disposable placeholder/temp branch (including deleting the finished branch
  locally and/or on the remote); or checks which worktree folders are busy vs idle.
  Trigger even when the words "worktree", "finish", or "placeholder" aren't explicit —
  e.g. "keep a couple of worktrees around for this project", "DevA에서 새 브랜치로 작업
  시작하자", "작업 끝났어 원격 브랜치도 지워줘", "다시 놀게 만들어줘", "재사용할 작업 공간
  만들어줘". Also covers "/unity-worktree" and its init/start/finish/status subcommands.
  Do NOT use for non-Unity repos, generic explanations of how git worktree works,
  plain git stash/cleanup, or ordinary Unity scripting/asset tasks unrelated to
  worktree folders.
---

# unity-worktree

Manage a fixed pool of reusable git worktrees for a Unity project.

## Why this exists

A fresh `git worktree` forces Unity to regenerate everything git does not track —
`Library/`, `Temp/`, `obj/`, the artifact database — which can take many minutes on
the first editor open. Creating and deleting worktrees per task pays that cost every
time.

The strategy here is the opposite: create a **small, fixed set of worktree folders
once** (e.g. `DevA`, `DevB`), keep their warm `Library/` caches, and **never delete
the folders**. To switch tasks we only swap which branch is checked out inside a
folder — the expensive caches survive.

An idle folder sits on a disposable **placeholder branch** (e.g. `temp/a`). The
placeholder is local-only (never pushed) and always cut fresh from the default branch,
so it can never drift out of date. It exists only while the folder is idle.

## Lifecycle at a glance

```
init    → create folder .claude/worktrees/DevA on placeholder temp/a  (once, per machine)
start   → switch folder to a real work branch, then DELETE the placeholder,
          then move THIS SESSION into the folder via EnterWorktree
          (folder is now "busy"; no stale placeholder lingering)
finish  → move the session back out via ExitWorktree (action: "keep"),
          re-cut a fresh placeholder from origin/<default>, switch to it,
          then keep or delete the work branch   (folder is "idle" again)
status  → show which folders are idle vs busy and on what branch
```

The folder is **never removed** by any command. Branch deletion happens only when the
user explicitly asks for it during `finish`.

## The helper script

All git plumbing lives in `scripts/wt.sh`. It is a bash script (bash ships with git
everywhere — Git Bash on Windows, native on macOS/Linux), it echoes every git command
before running it, and it supports `--dry-run` to preview without executing.

Run it from anywhere inside the repository. Common invocation:

```bash
bash "<skill-dir>/scripts/wt.sh" <subcommand> [args]
```

Always run `detect` first when you are unsure of the repo's default branch or remote —
never hardcode `main`/`origin`:

```bash
bash scripts/wt.sh detect      # prints main_worktree, remote, default_branch, registry
```

The script tracks a registry (`.claude/worktrees/registry.tsv`, git-ignored) mapping
each worktree name to its folder path and placeholder branch, so `finish` knows which
placeholder to restore.

## How to run each command

Show the user the commands you intend to run and, for anything destructive, confirm
first. Gather the human inputs (names, branch names, delete choices) conversationally,
then hand them to the script as flags.

### init — one-time setup

Ask the user for: how many worktrees, a name for each (default `DevA`, `DevB`, …), and
a placeholder branch for each (default `temp/a`, `temp/b`, …). Then:

1. Add the ignore rule and commit it **on the main worktree** (shared config must live
   on the default branch so every future work branch inherits it):
   ```bash
   bash scripts/wt.sh ensure-gitignore
   ```
2. Create each worktree (idempotent — existing folders/branches are reused, not
   clobbered):
   ```bash
   bash scripts/wt.sh init --name DevA --placeholder temp/a
   bash scripts/wt.sh init --name DevB --placeholder temp/b
   ```

`init` cuts each placeholder fresh from `origin/<default>` (override with `--base`).

### start — begin work in an idle folder

Ask which worktree and the work branch name. Whether it is a brand-new branch or an
existing local/remote one, run:

```bash
bash scripts/wt.sh start --name DevA --branch feature/login
```

- New branch: it is created from `origin/<default>` (never from the placeholder, which
  could be stale). Override the base with `--base <ref>`.
- Continuing an existing branch: add `--reuse` (or just name an existing branch — the
  script detects it and checks it out).
- The script refuses if the folder is still busy on another branch, or if the target
  branch is already checked out in a different worktree (git allows a branch in only
  one worktree at a time).
- After switching, it deletes the now-unneeded placeholder.

**Then move the session into the folder.** Once the script succeeds, the branch is
checked out in the worktree folder but the Claude Code session is still sitting in the
main worktree — file edits and builds would land in the wrong checkout. Call the
`EnterWorktree` tool with `path` set to the folder's absolute path (from the script
output, the registry, or `wt.sh status`):

```
EnterWorktree { path: "<repo>/.claude/worktrees/DevA" }
```

Use `path`, never `name` — `name` would create a brand-new throwaway worktree, which
defeats the warm-cache pool. The path must already appear in `git worktree list`,
which it does right after `start`. From this point on, all work for the task happens
inside the folder.

### finish — return a folder to idle

**First move the session out of the folder.** If the session entered the worktree via
`EnterWorktree` (the normal case after `start`), call `ExitWorktree` before running the
script, so the session isn't sitting on a branch that is about to be swapped out or
deleted:

```
ExitWorktree { action: "keep" }
```

Always `"keep"`, never `"remove"` — the folder and its warm Unity cache must survive.
(Worktrees entered via `path` are protected from removal by the tool anyway, but be
explicit.) If no EnterWorktree session is active — e.g. the work started in an earlier
Claude Code session, or the user launched the session directly inside the folder —
`ExitWorktree` is a harmless no-op; just proceed and run the script from wherever you
are (it works from anywhere in the repo).

Ask how to handle the work branch: **keep** it (still shared with collaborators),
delete it **locally**, or delete it **locally and on the remote**. Then:

```bash
bash scripts/wt.sh finish --name DevA --branch-action keep
bash scripts/wt.sh finish --name DevA --branch-action delete-local
bash scripts/wt.sh finish --name DevA --branch-action delete-remote
```

This re-creates a fresh placeholder from `origin/<default>`, switches to it, and then
applies the chosen branch action. The folder stays on disk with its warm cache.

### status — see the pool

```bash
bash scripts/wt.sh status
```

Shows `git worktree list` plus a table marking each registered worktree as `idle`
(on its placeholder) or `busy` (on a work branch), with the current branch and path.

## Guardrails

- **Never delete a worktree folder.** That would throw away the warm Unity cache,
  which is the entire point. No command here removes folders; do not add one unless the
  user is explicit and understands the rebuild cost. This includes `ExitWorktree`: only
  ever call it with `action: "keep"` — `"remove"` deletes the folder and branch.
- **Enter with `path`, exit with `keep`.** Session movement uses `EnterWorktree { path }`
  into an existing pool folder (never `name`, which creates a fresh worktree and a cold
  cache) and `ExitWorktree { action: "keep" }` to leave.
- **Never delete a branch without an explicit request.** `finish` deletes the work
  branch only for `--branch-action delete-local`/`delete-remote`. Placeholder deletion
  in `start` is safe because it is a disposable local branch you just switched off of.
- **Edit shared config only on the main worktree.** `.gitignore` and similar must be
  committed on the default branch (via `ensure-gitignore`), or the rule won't be
  inherited by work branches.
- **Detect, don't hardcode.** Use `detect` for the default branch and remote name; they
  vary across repos (`main`/`master`, `origin`/other).
- Preview with `--dry-run` when the user wants to see the plan before it runs.

## Example session

**User:** "DevA, DevB 두 개로 셋업해줘."
→ `ensure-gitignore`, then `init --name DevA --placeholder temp/a` and
`init --name DevB --placeholder temp/b`.

**User:** "DevA에서 feature/inventory 작업 시작할게."
→ `start --name DevA --branch feature/inventory`, then
`EnterWorktree { path: "<repo>/.claude/worktrees/DevA" }` so the session works inside DevA.

**User:** "DevA 작업 끝났어, 브랜치는 원격까지 지워줘."
→ confirm, then `ExitWorktree { action: "keep" }`, then
`finish --name DevA --branch-action delete-remote`.
