# Scout — per-run worktree isolation for the local `/scout` flow

**Date:** 2026-06-11
**Status:** Design (awaiting review)
**Scope:** the local interactive `/scout` flow only (`scout.md`, `local-setup.sh`, `publish.sh`). CI scripts are explicitly out of scope.

## Problem

The local `/scout` flow clones Atlas into a **single fixed path** and wipes it on every run:

```sh
# local-setup.sh
rm -rf atlas-checkout
git clone --depth=1 --filter=blob:none "$ATLAS_REPO" atlas-checkout
```

`publish.sh` hardcodes the same path (`ATLAS_DIR="atlas-checkout"`). Two consequences:

1. **Parallel runs clobber each other.** A second `/scout` run's `rm -rf atlas-checkout` deletes the first run's in-progress work. This actually happened: a concurrent run wiped 4 of 7 child research folders mid-flight, forcing a manual recovery into an isolated clone.
2. **Atlas location is guessed.** `ATLAS_REPO` resolves from an env var or `docker/.env`, and the flow re-clones from scratch each run rather than reusing a known local checkout. Because `/scout` can be launched from **any** working directory, anything relative (e.g. `../atlas`) is unreliable.

The user's hard constraints: **no `rm -rf` of a shared directory**, and **multiple runs must coexist side-by-side without clobbering**.

## Goals

- Each run operates in its own isolated working tree; concurrent runs never touch each other's files.
- Eliminate the destructive `rm -rf` of a shared directory.
- Resolve the Atlas checkout **once**, persist it, and reuse it — never guess, never depend on cwd.
- Cheap per run (no full re-clone): reuse a shared object store.
- Auto-clean a run's workspace on success; keep it on failure for inspection.

## Non-goals

- CI / automated scripts (`run.sh`, `run-decompose.sh`, `*-from-issue.sh`, `views-dispatch.sh`) are unchanged. Each CI job runs in its own container, so the fixed-path clone is harmless there. The self-hosted-runner efficiency win (fetch + worktree instead of re-clone) can reuse this same primitive later — noted as a follow-up, not built here.
- No change to research content, synthesis, covers, views, validation, or the provenance-issue flow.

## Design

### Mechanism: git worktree per run

One **registered** local Atlas checkout is the long-lived source of truth. Each run adds a **git worktree** off it, on its own branch, based on freshly-fetched `origin/main`:

```sh
git -C "$ATLAS_DIR" fetch origin main
git -C "$ATLAS_DIR" worktree add -b "scout/$DATE-$SLUG" \
    "$WT_HOME/$DATE-$SLUG"  origin/main
```

- Worktrees **share `$ATLAS_DIR/.git`** → no re-download, cheap setup.
- Each run has its **own working tree** and **own branch** → parallel runs cannot collide.
- Basing on fresh `origin/main` sidesteps any local uncommitted/ahead state in the user's checkout.
- The registered checkout's **`origin` remote is the publish target** — this retires the `ATLAS_REPO` "clone source vs push target" ambiguity entirely, and avoids the local-checkout `denyCurrentBranch` problem because pushes go to the remote.

### 1. Discovery & first-run bootstrap

All persisted paths are **absolute** (resolved with `realpath` / `cd … && pwd`). The only anchor is `SCOUT_DIR`, itself resolved absolutely from `~/.scout/dir` or by walking up from the script's own `BASH_SOURCE` (never cwd).

Two machine-level pointer files under `~/.scout/`:

| File | Holds |
|---|---|
| `~/.scout/atlas` | absolute path to the local Atlas checkout |
| `~/.scout/worktrees-dir` | absolute path to the worktree home |

**Resolution at run start** (new step in `scout.md`, before setup):

1. **Atlas checkout** — if `~/.scout/atlas` exists and is valid (a git repo with an `origin` remote), use it. Otherwise **ask** via `AskUserQuestion`:
   - **Use detected checkout** at `realpath "$SCOUT_DIR/../atlas"` — offered only when that path resolves to a valid checkout; shown as a pre-filled suggestion, never silently trusted.
   - **Provide a path** to an existing Atlas checkout.
   - **Clone a fresh one** into `~/.scout/atlas` (prompts for the repo URL; default `git@github.com:Laoujin/Atlas`).

   Validate the choice (git repo + `origin` present), then save its **absolute** path to `~/.scout/atlas`.

2. **Worktree home** — if `~/.scout/worktrees-dir` exists, use it. Otherwise **ask** via `AskUserQuestion`:
   - **`~/.scout/atlas-worktrees/`**
   - **Custom** — user provides a path.
   - **`<ATLAS_DIR>/worktrees/`** (inside the checkout) — on this choice, append `worktrees/` to `$ATLAS_DIR/.git/info/exclude` (idempotent, local-only, never committed) so the nested worktrees don't show as untracked in the user's main checkout.

   Save the chosen **absolute** path to `~/.scout/worktrees-dir`.

Subsequent runs read both pointers and skip straight to setup — no prompts.

### 2. `local-setup.sh` — fetch + worktree (replaces rm/clone)

Inputs (env/args): `ATLAS_DIR`, `WT_HOME`, `TITLE`, `SUB_TOPICS_TSV`. No more `ATLAS_REPO`.

1. `git -C "$ATLAS_DIR" worktree prune` (clear stale registrations).
2. `git -C "$ATLAS_DIR" fetch origin main`.
3. Compute a unique `SLUG` against **`origin/main`** (check `git -C "$ATLAS_DIR" cat-file -e origin/main:research/$DATE-$SLUG` and existing `scout/$DATE-$SLUG` branches; suffix `-2`, `-3`, … on collision).
4. `WT="$WT_HOME/$DATE-$SLUG"`; `BRANCH="scout/$DATE-$SLUG"`.
5. `git -C "$ATLAS_DIR" worktree add -b "$BRANCH" "$WT" origin/main`.
6. `PARENT_DIR="$WT/research/$DATE-$SLUG"`; `mkdir -p` it and each child dir.
7. Print KEY=VALUE lines: `ATLAS_DIR`, `WORKTREE`, `BRANCH`, `DATE`, `SLUG`, `PARENT_DIR`, `START_TS`, and `CHILD=<slug>\t<dir>` lines. (Drop `ATLAS_REPO`.)

### 3. `publish.sh` — push from the worktree, then clean up

Inputs (env): `WORKTREE`, `BRANCH`, `ATLAS_DIR`, plus existing `TOPIC`/`SLUG`/`DATE`.

1. `cd "$WORKTREE"`; reuse `publish_path` (stage → commit → push to `main` with rebase-retry). Because the worktree's HEAD is `scout/$DATE-$SLUG` (not `main`), `try_push` must push **`HEAD:main`**, not `main`. The rebase-retry now handles the **genuine** concurrent-publish race (two runs pushing to `main`) correctly. Pushing `HEAD:main` does not move the shared checkout's local `main` ref — only `origin/main` advances; the user's main checkout picks it up on its next `git pull`.
2. Derive the Pages URL from `git -C "$WORKTREE" remote get-url origin` (parse `owner/repo` for both SSH `git@…:owner/repo.git` and HTTPS `https://github.com/owner/repo` forms) → `https://<owner>.github.io/<repo>/research/<DATE>-<SLUG>/`.
3. **On success:** `git -C "$ATLAS_DIR" worktree remove "$WORKTREE"` and `git -C "$ATLAS_DIR" branch -D "$BRANCH"`. **On failure:** leave the worktree in place and print its path for inspection.

### 4. `scout.md` — thread the new values

- Add the bootstrap/resolution step (the two `AskUserQuestion`s) before Step 3.
- Step 3 calls the refactored `local-setup.sh` with `ATLAS_DIR`/`WT_HOME`; parse `WORKTREE`/`BRANCH` from its output.
- Replace `$SCOUT_DIR/atlas-checkout/...` references with `$WORKTREE/...` (e.g. series.yml at `$WORKTREE/_data/series.yml`).
- Step 6 passes `WORKTREE`/`BRANCH`/`ATLAS_DIR` to `publish.sh`; update the "pushes atlas-checkout/" wording.

## Edge cases

- **Leftover branch/worktree from a failed run.** `worktree prune` + unique-slug suffixing avoid `-b` collisions; a failed run's kept worktree has a distinct dated slug so it never blocks a new run.
- **Stale pointer.** If `~/.scout/atlas` points to a missing/invalid path, treat as unset and re-bootstrap.
- **`worktree remove` refuses** (dirty tree) — only happens on success after a clean commit, so the tree is clean; use plain `remove` (no `--force`) and surface any error non-fatally (publish already succeeded).

## Files touched

- `scripts/local-setup.sh` — fetch + worktree instead of rm/clone; new output keys.
- `scripts/publish.sh` — operate on `WORKTREE`; URL from `origin`; worktree-remove + branch-delete on success.
- `.claude/commands/scout.md` — bootstrap step; thread `WORKTREE`/`BRANCH`; fix `atlas-checkout` references.
- `scripts/lib-publish.sh` — `try_push` pushes `HEAD:main` instead of `main` (backward-compatible: CI works on `main`, where `HEAD:main` is identical). `pr_fallback` already pushes `HEAD:refs/heads/$branch` — unchanged.

## Test plan

- [ ] Fresh machine (no `~/.scout/atlas`): bootstrap prompts for Atlas path + worktree home, validates, persists both as absolute paths; second run prompts for neither.
- [ ] "Clone fresh" bootstrap option clones into `~/.scout/atlas` and registers it.
- [ ] Inside-Atlas worktree-home choice appends `worktrees/` to `.git/info/exclude` and the user's main checkout stays clean (`git status` shows nothing untracked).
- [ ] **Two runs in parallel**: two worktrees + two branches, neither touches the other's files; both publish; `main` ends with both commits (rebase-retry resolves the race).
- [ ] Launch `/scout` from an unrelated cwd: resolution is unaffected (absolute paths only).
- [ ] Slug collision (same place, same day): second run gets `-2` suffix.
- [ ] Success removes the run's worktree + branch; an induced publish failure leaves the worktree and prints its path.
