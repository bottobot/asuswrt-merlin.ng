#!/usr/bin/env bash
# upstream-check.sh [upstream_branch] [base_commit]
#
# Reports RMerl upstream commits (since base) that touch files this fork changed
# relative to base. Read-only for the working tree and branches: it only adds the
# 'upstream' remote if missing and fetches one branch into refs/remotes/upstream/.
#
# Defaults: upstream_branch=3006.102-wifi6, base_commit=c73015d2b494aaa986417e06bc2cc726930a2f1a
#
# Output:
#   human-readable header and commit list, then
#   sha|subject|overlapping_files(comma)   one line per new upstream commit (oldest first)
#   OVERLAP_COUNT=<n>   commits touching at least one fork-changed file
#   NEW_COMMITS=<n>     upstream commits since base
# Exit status: 0 unless a git command (or argument validation) fails.
set -euo pipefail

UPSTREAM_URL="https://github.com/RMerl/asuswrt-merlin.ng.git"
UPSTREAM_REMOTE="upstream"
DEPTH=200
BRANCH="${1:-3006.102-wifi6}"
BASE="${2:-c73015d2b494aaa986417e06bc2cc726930a2f1a}"

trap 'echo "upstream-check: a git command failed (line $LINENO)" >&2' ERR
warn() { echo "WARN: $*" >&2; }
die() { echo "upstream-check: $*" >&2; exit 1; }

cd "$(dirname -- "${BASH_SOURCE[0]}")"
cd "$(git rev-parse --show-toplevel)"

# 1. Remote: add if missing, reuse if present.
if git remote get-url "$UPSTREAM_REMOTE" >/dev/null 2>&1; then
    existing="$(git remote get-url "$UPSTREAM_REMOTE")"
    if [[ "$existing" != "$UPSTREAM_URL" ]]; then
        warn "remote '$UPSTREAM_REMOTE' points to $existing (expected $UPSTREAM_URL); using it as-is"
    fi
else
    git remote add "$UPSTREAM_REMOTE" "$UPSTREAM_URL"
    echo "added remote '$UPSTREAM_REMOTE' -> $UPSTREAM_URL"
fi

# 2. Fetch the branch (shallow-safe).
fetch_args=(--no-tags)
if [[ "$(git rev-parse --is-shallow-repository)" == "true" ]]; then
    fetch_args+=(--depth "$DEPTH")
    echo "repo is shallow: fetching with --depth $DEPTH"
fi
UP_REF="refs/remotes/$UPSTREAM_REMOTE/$BRANCH"
echo "fetching $UPSTREAM_REMOTE/$BRANCH ..."
git fetch "${fetch_args[@]}" "$UPSTREAM_REMOTE" "+refs/heads/$BRANCH:$UP_REF"

BASE_SHA="$(git rev-parse --verify --quiet "$BASE^{commit}")" \
    || die "base commit '$BASE' not found in local history"
UP_SHA="$(git rev-parse --verify --quiet "$UP_REF^{commit}")" \
    || die "upstream ref $UP_REF not found after fetch"

echo "base:          $(git log -1 --format='%h %s' "$BASE_SHA")"
echo "upstream tip:  $(git log -1 --format='%h %s' "$UP_SHA") ($UPSTREAM_REMOTE/$BRANCH)"
if ! git merge-base --is-ancestor "$BASE_SHA" "$UP_SHA"; then
    warn "base is not an ancestor of $UPSTREAM_REMOTE/$BRANCH; counts may include unrelated history (shallow depth $DEPTH too small, or branch rewritten)"
fi

# 3. Files the fork changed relative to base, minus fork-only areas.
declare -A FORK_SET=()
fork_count=0
fork_changed="$(git diff --name-only "$BASE_SHA" HEAD)"
while IFS= read -r f; do
    [[ -z "$f" ]] && continue
    case "$f" in
        docs/*|tools/*|.github/*|PLAN.md|README*.md) continue ;;
    esac
    FORK_SET["$f"]=1
    fork_count=$((fork_count + 1))
done <<< "$fork_changed"
echo "fork-changed files vs base (excl. docs/ tools/ .github/ PLAN.md README*.md): $fork_count"

# 4. New upstream commits since base.
new_count="$(git rev-list --count "$BASE_SHA..$UP_SHA")"
echo "NEW upstream commits since base: $new_count"
if (( new_count > 0 )); then
    git log --oneline "$BASE_SHA..$UP_SHA"
fi

# 5. Version bump commits since base.
bump="$(git log --format='%h %s' "$BASE_SHA..$UP_SHA" | grep -E 'Bumped revision to 3006' || true)"
if [[ -n "$bump" ]]; then
    echo "VERSION_BUMP=yes"
    while IFS= read -r line; do
        echo "VERSION_BUMP_COMMIT: $line"
    done <<< "$bump"
else
    echo "VERSION_BUMP=no"
fi

# 6. Per-commit overlap with fork-changed files (machine-readable).
overlap_count=0
commits="$(git rev-list --reverse "$BASE_SHA..$UP_SHA")"
while IFS= read -r sha; do
    [[ -z "$sha" ]] && continue
    subject="$(git log -1 --format=%s "$sha")"
    subject="${subject//|//}"
    # -m --first-parent: merges are diffed against their mainline parent
    touched="$(git diff-tree --no-commit-id --name-only -r -m --first-parent --root "$sha" | sort -u)"
    hits=()
    while IFS= read -r f; do
        if [[ -n "$f" && -n "${FORK_SET[$f]:-}" ]]; then
            hits+=("$f")
        fi
    done <<< "$touched"
    overlap="$(IFS=,; echo "${hits[*]:-}")"
    if [[ -n "$overlap" ]]; then
        overlap_count=$((overlap_count + 1))
    fi
    printf '%s|%s|%s\n' "$sha" "$subject" "$overlap"
done <<< "$commits"

echo "OVERLAP_COUNT=$overlap_count"
echo "NEW_COMMITS=$new_count"
