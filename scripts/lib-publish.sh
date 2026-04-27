#!/usr/bin/env bash
# Helpers for scripts/publish.sh: push recovery primitives.
#
# Usage (source this file):
#   source scripts/lib-publish.sh

# is_non_ff <stderr-text>
# Returns 0 (true) if stderr looks like a non-fast-forward push rejection,
# 1 otherwise. Narrow match: both "rejected" and one of "non-fast-forward" /
# "fetch first" must appear. Any other error (auth, network, etc) returns 1
# so the caller fails loud instead of retrying.
is_non_ff() {
  local text="$1"
  [[ "$text" == *"rejected"* ]] || return 1
  [[ "$text" == *"non-fast-forward"* || "$text" == *"fetch first"* ]]
}

# try_push
# Pushes current HEAD to origin/main. Returns:
#   0 on success, 1 on non-fast-forward rejection, 2 on any other failure.
# Mirrors git's own stderr to stderr so CI logs are unchanged on real errors.
try_push() {
  local err rc=0
  err=$(git push origin main 2>&1) || rc=$?
  [ -n "$err" ] && printf '%s\n' "$err" >&2
  if [ "$rc" -eq 0 ]; then return 0; fi
  if is_non_ff "$err"; then return 1; fi
  return 2
}

# rebase_onto_remote
# Fetches origin/main and rebases current branch onto it. On conflict,
# aborts the rebase to leave a clean tree. Returns 0 on clean rebase, 1 on
# conflict or fetch failure.
rebase_onto_remote() {
  git fetch origin main >&2 || return 1
  if git rebase origin/main >&2; then
    return 0
  fi
  git rebase --abort >&2 2>/dev/null || true
  return 1
}

# compare_url <atlas-repo-url> <branch>
# Derives the GitHub compare URL from ATLAS_REPO (git@...:owner/repo.git
# or file path). Returns empty string if ATLAS_REPO doesn't look like a
# GitHub SSH URL (test/file-URL case).
compare_url() {
  local repo="$1" branch="$2"
  [[ "$repo" == *":"* ]] || { echo ""; return; }
  local slug="${repo#*:}"; slug="${slug%.git}"
  echo "https://github.com/${slug}/compare/main...${branch}?expand=1"
}

# pr_fallback <branch> <atlas-repo> [issue-comment-args...]
# Push HEAD to <branch> on origin. Print the compare URL. If GH_TOKEN,
# GH_REPO, and ISSUE_NUMBER are set in the environment, post a comment
# with the URL. Returns 0 on successful branch push (comment failure is
# surfaced via set -e in the caller).
pr_fallback() {
  local branch="$1" repo="$2"
  git push origin "HEAD:refs/heads/$branch" >&2
  local url; url=$(compare_url "$repo" "$branch")
  [ -z "$url" ] && url="(could not derive compare URL from ATLAS_REPO='$repo')"
  echo "Atlas main moved during this run. Branch pushed: $branch"
  echo "Open PR: $url"
  if [ -n "${GH_TOKEN:-}" ] && [ -n "${GH_REPO:-}" ] && [ -n "${ISSUE_NUMBER:-}" ]; then
    gh issue comment "$ISSUE_NUMBER" --repo "$GH_REPO" --body \
      "Atlas \`main\` moved during this run. Branch pushed: \`$branch\`. Open PR: $url"
  fi
}

# publish_path <commit-msg> <stage-target> <fallback-branch>
# Stages <stage-target> (a path or "."), commits, pushes to origin/main with
# rebase+retry; on rebase conflict or 3 exhausted retries, falls back to
# pushing to <fallback-branch> and prints a compare URL.
# Preconditions: cwd is the atlas-checkout git repo. ATLAS_REPO env may be set
# (used in PR-fallback compare URL). GIT_AUTHOR_{NAME,EMAIL} envs control the
# commit identity (Scout fallback if unset).
# Returns: 0 on success (main or PR-fallback branch),
#          2 nothing staged (caller decides whether that's an error),
#          3 hard failure (auth/network/etc).
publish_path() {
  local msg="$1" target="$2" branch="$3"

  git add -- "$target"
  if git diff --cached --quiet; then
    return 2
  fi

  git -c user.name="${GIT_AUTHOR_NAME:-Scout}" \
      -c user.email="${GIT_AUTHOR_EMAIL:-scout@users.noreply.github.com}" \
    commit -m "$msg"

  local rc=0
  rc=0; try_push || rc=$?
  if [ "$rc" -eq 2 ]; then return 3; fi
  if [ "$rc" -eq 1 ]; then
    local i
    for i in 1 2 3; do
      if ! rebase_onto_remote; then
        pr_fallback "$branch" "${ATLAS_REPO:-}"
        return 0
      fi
      rc=0; try_push || rc=$?
      [ "$rc" -eq 0 ] && return 0
      [ "$rc" -eq 2 ] && return 3
      sleep $((2 ** (i - 1)))
    done
    pr_fallback "$branch" "${ATLAS_REPO:-}"
    return 0
  fi
  return 0
}
