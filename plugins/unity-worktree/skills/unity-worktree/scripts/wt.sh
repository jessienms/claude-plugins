#!/usr/bin/env bash
# unity-worktree helper — deterministic git plumbing for persistent Unity worktrees.
#
# Design notes for whoever reads this:
# - Unity regenerates Library/ Temp/ obj/ from scratch per worktree, which is slow.
#   So we keep a small fixed set of worktrees under .claude/worktrees/ and NEVER
#   delete the folders. We only swap the branch checked out inside each folder.
# - A worktree that is idle sits on a "placeholder" branch (e.g. temp/a). The
#   placeholder is local-only, disposable, and always cut fresh from the default
#   branch so it can never go stale.
# - Lifecycle: init creates folder + placeholder. start switches to a work branch
#   and DELETES the placeholder (so an idle placeholder never lingers during work).
#   finish re-creates a fresh placeholder from origin/<default>, switches to it,
#   then deletes/keeps the work branch. status reports which folders are idle vs busy.
# - This script prints every git command before running it (unless --quiet) so the
#   human can follow along. Destructive branch deletion only happens when explicitly
#   requested via --branch-action. Worktree folders are never removed here.

set -euo pipefail

QUIET=0
DRY_RUN=0

log()  { [ "$QUIET" -eq 1 ] || printf '%s\n' "$*" >&2; }
die()  { printf 'error: %s\n' "$*" >&2; exit 1; }

# Run a git (or shell) command, echoing it first. Honors --dry-run.
run() {
  [ "$QUIET" -eq 1 ] || printf '  $ %s\n' "$*" >&2
  if [ "$DRY_RUN" -eq 1 ]; then return 0; fi
  "$@"
}

# --- repo topology ----------------------------------------------------------

# Path of the MAIN working tree (first entry of `git worktree list --porcelain`).
# Shared config edits (.gitignore) must happen here, not inside a linked worktree.
main_worktree() {
  git worktree list --porcelain | awk '/^worktree /{print substr($0,10); exit}'
}

# Detect the remote name (prefer "origin", else first remote).
detect_remote() {
  if git remote | grep -qx origin; then echo origin; return; fi
  git remote | head -1
}

# Detect the default branch of <remote> with graceful fallbacks, cheapest first:
#   1) refs/remotes/<remote>/HEAD symbolic ref (offline, exact)
#   2) main, then master, if such a remote-tracking branch exists (offline, common)
#   3) `git remote show` "HEAD branch" (authoritative but needs network)
detect_default_branch() {
  local remote="$1" b
  if b=$(git symbolic-ref --short "refs/remotes/$remote/HEAD" 2>/dev/null); then
    echo "${b#"$remote"/}"; return
  fi
  for b in main master; do
    if git show-ref --verify --quiet "refs/remotes/$remote/$b"; then echo "$b"; return; fi
  done
  if b=$(git remote show "$remote" 2>/dev/null | sed -n 's/.*HEAD branch: //p' | head -1) && [ -n "$b" ] && [ "$b" != "(unknown)" ]; then
    echo "$b"; return
  fi
  die "could not detect default branch for remote '$remote'; pass --base <ref> explicitly"
}

# --- registry (name <TAB> path <TAB> placeholder) ---------------------------
# Stored under the main worktree at .claude/worktrees/registry.tsv. It is inside
# the git-ignored .claude/worktrees/ tree, so it stays local per machine — which
# is correct, because the worktrees themselves are per-machine.

registry_path() { echo "$(main_worktree)/.claude/worktrees/registry.tsv"; }

registry_lookup() { # <name> -> prints "path<TAB>placeholder" or nothing
  local name="$1" reg; reg=$(registry_path)
  [ -f "$reg" ] || return 0
  awk -F'\t' -v n="$name" '$1==n{print $2"\t"$3; exit}' "$reg"
}

registry_upsert() { # <name> <path> <placeholder>
  local name="$1" path="$2" ph="$3" reg tmp; reg=$(registry_path)
  mkdir -p "$(dirname "$reg")"; touch "$reg"
  tmp="$reg.tmp"
  awk -F'\t' -v n="$name" '$1!=n' "$reg" > "$tmp" || true
  printf '%s\t%s\t%s\n' "$name" "$path" "$ph" >> "$tmp"
  mv "$tmp" "$reg"
}

# Resolve a worktree name to its path + placeholder from the registry.
resolve() { # <name>; sets globals WT_PATH, WT_PH
  local row; row=$(registry_lookup "$1")
  [ -n "$row" ] || die "worktree '$1' not found in registry; run 'init' first or check 'status'"
  WT_PATH=$(printf '%s' "$row" | cut -f1)
  WT_PH=$(printf '%s' "$row" | cut -f2)
}

# Is <branch> checked out in some OTHER worktree? Prints that worktree path if so.
branch_checked_out_elsewhere() { # <branch> <self-path>
  local br="$1" self="$2"
  git worktree list --porcelain | awk -v br="refs/heads/$br" -v self="$self" '
    /^worktree /{wt=substr($0,10)}
    /^branch /{ if ($2==br && wt!=self) {print wt; exit} }'
}

# --- subcommands ------------------------------------------------------------

cmd_detect() {
  local remote def main
  remote=$(detect_remote); def=$(detect_default_branch "$remote"); main=$(main_worktree)
  echo "main_worktree=$main"
  echo "remote=$remote"
  echo "default_branch=$def"
  echo "registry=$(registry_path)"
}

cmd_status() {
  local reg; reg=$(registry_path)
  echo "== git worktree list =="
  git worktree list
  echo
  echo "== unity-worktree registry =="
  if [ ! -f "$reg" ]; then echo "(no registry yet — run init)"; return; fi
  printf '%-16s %-10s %-24s %s\n' NAME STATE BRANCH PATH
  while IFS=$'\t' read -r name path ph; do
    [ -n "$name" ] || continue
    local cur state
    cur=$(git -C "$path" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
    if [ "$cur" = "$ph" ]; then state="idle"; else state="busy"; fi
    printf '%-16s %-10s %-24s %s\n' "$name" "$state" "$cur" "$path"
  done < "$reg"
}

cmd_ensure_gitignore() {
  local main ignore line="/.claude/worktrees/"
  main=$(main_worktree)
  ignore="$main/.gitignore"
  if [ -f "$ignore" ] && grep -qxF ".claude/worktrees/" "$ignore"; then
    log "gitignore already contains .claude/worktrees/ — nothing to do"
    return 0
  fi
  log "adding .claude/worktrees/ to $ignore (on the main worktree)"
  if [ "$DRY_RUN" -eq 0 ]; then
    { [ -s "$ignore" ] && [ -n "$(tail -c1 "$ignore")" ] && echo ""; \
      echo "# unity-worktree persistent worktrees (local, never committed)"; \
      echo ".claude/worktrees/"; } >> "$ignore"
  fi
  run git -C "$main" add .gitignore
  run git -C "$main" commit -m "chore: ignore .claude/worktrees/ (unity-worktree)"
}

cmd_init() { # --name <n> --placeholder <ph> [--base <ref>]
  local name="" ph="" base=""
  while [ $# -gt 0 ]; do case "$1" in
    --name) name="$2"; shift 2;;
    --placeholder) ph="$2"; shift 2;;
    --base) base="$2"; shift 2;;
    *) die "init: unknown arg $1";;
  esac; done
  [ -n "$name" ] || die "init: --name required"
  [ -n "$ph" ] || die "init: --placeholder required"

  local main remote def path
  main=$(main_worktree); remote=$(detect_remote)
  if [ -z "$base" ]; then def=$(detect_default_branch "$remote"); base="$remote/$def"; fi
  path="$main/.claude/worktrees/$name"

  if [ -d "$path" ]; then
    log "worktree folder already exists: $path (skipping create)"
    registry_upsert "$name" "$path" "$ph"
    return 0
  fi

  log "creating worktree '$name' at $path on placeholder '$ph' (base $base)"
  # If placeholder branch already exists, reuse it; else cut it fresh from base.
  if git show-ref --verify --quiet "refs/heads/$ph"; then
    run git worktree add "$path" "$ph"
  else
    run git fetch "$remote" || true
    # --no-track: the placeholder is a throwaway LOCAL branch. Without this it would
    # inherit origin/<default> as upstream, so a stray `git push` from an idle folder
    # could target the default branch under some push.default settings.
    run git worktree add --no-track -b "$ph" "$path" "$base"
  fi
  registry_upsert "$name" "$path" "$ph"
  log "registered $name -> $path (placeholder $ph)"
}

cmd_start() { # --name <n> --branch <b> [--base <ref>] [--reuse]
  local name="" branch="" base="" reuse=0
  while [ $# -gt 0 ]; do case "$1" in
    --name) name="$2"; shift 2;;
    --branch) branch="$2"; shift 2;;
    --base) base="$2"; shift 2;;
    --reuse) reuse=1; shift;;
    *) die "start: unknown arg $1";;
  esac; done
  [ -n "$name" ] || die "start: --name required"
  [ -n "$branch" ] || die "start: --branch required"

  resolve "$name"
  local remote def elsewhere cur
  remote=$(detect_remote)

  cur=$(git -C "$WT_PATH" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")
  if [ "$cur" != "$WT_PH" ]; then
    die "worktree '$name' is busy on '$cur', not idle. Run 'finish $name' before starting new work."
  fi

  elsewhere=$(branch_checked_out_elsewhere "$branch" "$WT_PATH")
  [ -z "$elsewhere" ] || die "branch '$branch' is already checked out in $elsewhere; a branch can live in only one worktree"

  log "fetching $remote in $WT_PATH"
  run git -C "$WT_PATH" fetch "$remote"

  if [ "$reuse" -eq 1 ] || git -C "$WT_PATH" show-ref --verify --quiet "refs/heads/$branch"; then
    log "switching to existing branch '$branch'"
    run git -C "$WT_PATH" switch "$branch"
  else
    if [ -z "$base" ]; then def=$(detect_default_branch "$remote"); base="$remote/$def"; fi
    log "creating work branch '$branch' from '$base'"
    # --no-track: don't wire the work branch's upstream to origin/<default>, or a
    # later `git push` could aim at the default branch. Let the user set upstream
    # explicitly on first push (e.g. `git push -u origin <branch>`).
    run git -C "$WT_PATH" switch --no-track -c "$branch" "$base"
  fi

  # Drop the placeholder now that the folder is busy. We just left it, so -D is safe.
  if git -C "$WT_PATH" show-ref --verify --quiet "refs/heads/$WT_PH"; then
    log "deleting idle placeholder '$WT_PH'"
    run git -C "$WT_PATH" branch -D "$WT_PH"
  fi
  log "worktree '$name' is now working on '$branch'"
}

cmd_finish() { # --name <n> [--base <ref>] [--branch-action keep|delete-local|delete-remote]
  local name="" base="" action="keep"
  while [ $# -gt 0 ]; do case "$1" in
    --name) name="$2"; shift 2;;
    --base) base="$2"; shift 2;;
    --branch-action) action="$2"; shift 2;;
    *) die "finish: unknown arg $1";;
  esac; done
  [ -n "$name" ] || die "finish: --name required"
  case "$action" in keep|delete-local|delete-remote) ;; *) die "finish: --branch-action must be keep|delete-local|delete-remote";; esac

  resolve "$name"
  local remote def work
  remote=$(detect_remote)
  work=$(git -C "$WT_PATH" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "?")

  if [ "$work" = "$WT_PH" ]; then
    die "worktree '$name' is already idle on placeholder '$WT_PH'; nothing to finish"
  fi

  log "fetching $remote in $WT_PATH"
  run git -C "$WT_PATH" fetch "$remote"
  if [ -z "$base" ]; then def=$(detect_default_branch "$remote"); base="$remote/$def"; fi

  # Re-create a fresh placeholder from the default branch and switch to it, so the
  # folder returns to idle. -C resets the placeholder if a stale one somehow exists.
  log "restoring fresh placeholder '$WT_PH' from '$base'"
  # --no-track for the same reason as init: the placeholder must not carry
  # origin/<default> as upstream.
  run git -C "$WT_PATH" switch --no-track -C "$WT_PH" "$base"

  # Now the work branch is no longer checked out here; safe to delete if asked.
  case "$action" in
    keep)
      log "keeping work branch '$work' (e.g. shared with collaborators)";;
    delete-local)
      log "deleting local work branch '$work'"
      run git -C "$WT_PATH" branch -D "$work";;
    delete-remote)
      log "deleting work branch '$work' locally and on '$remote'"
      run git -C "$WT_PATH" branch -D "$work"
      run git -C "$WT_PATH" push "$remote" --delete "$work";;
  esac
  log "worktree '$name' is idle again on '$WT_PH' (folder kept)"
}

# --- dispatch ---------------------------------------------------------------

main() {
  # Global flags may appear before the subcommand.
  while [ $# -gt 0 ]; do case "$1" in
    --quiet) QUIET=1; shift;;
    --dry-run) DRY_RUN=1; shift;;
    *) break;;
  esac; done

  [ $# -gt 0 ] || die "usage: wt.sh [--dry-run] <detect|status|ensure-gitignore|init|start|finish> [args]"
  local sub="$1"; shift
  case "$sub" in
    detect)           cmd_detect "$@";;
    status)           cmd_status "$@";;
    ensure-gitignore) cmd_ensure_gitignore "$@";;
    init)             cmd_init "$@";;
    start)            cmd_start "$@";;
    finish)           cmd_finish "$@";;
    *) die "unknown subcommand: $sub";;
  esac
}

main "$@"
