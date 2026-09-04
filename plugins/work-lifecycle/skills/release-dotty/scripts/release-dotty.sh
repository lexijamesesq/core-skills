#!/usr/bin/env bash
# release-dotty.sh <dotty_checkout_path> [--dry-run]
#
# Operator-invoked local step for the pre-commit channel's release — one
# synchronous act: cut dotty's own CalVer tag if an exported hook changed
# since the last one, then open a bump PR in every consumer repo. Local,
# not CI: a hosted runner's token can't open PRs in other repos, and the
# estate's real credentials (gh auth, the SA SSH key) are local by
# design. See ../SKILL.md for the full design and the plugin channel's
# CI.md for why this half is local and that half is hosted.
#
# --dry-run prints every decision (tag to cut or skip, consumers found,
# whether each is due for a bump) without pushing a tag, cutting a
# Release, or touching any consumer repo.
set -euo pipefail

if [[ $# -lt 1 ]]; then
  echo "usage: release-dotty.sh <dotty_checkout_path> [--dry-run]" >&2
  exit 2
fi
DOTTY="$1"
shift

DRY_RUN=0
for arg in "$@"; do
  case "$arg" in
    --dry-run) DRY_RUN=1 ;;
    *) echo "unknown arg: $arg" >&2; exit 2 ;;
  esac
done

CONSUMER_ROOTS=("$HOME/bin" "$HOME/Agents" "$HOME/Repos")
BUMP_BRANCH="dotty-bump"

say() { echo "$@"; }
refuse() { echo "REFUSE: $*" >&2; exit 1; }

# ---- Preconditions ----
[[ -d "$DOTTY/.git" ]] || refuse "$DOTTY is not a git checkout"
cd "$DOTTY"

[[ -z "$(git status --porcelain)" ]] || refuse "dotty checkout is not clean"

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[[ "$CURRENT_BRANCH" == "main" ]] || refuse "dotty checkout is on $CURRENT_BRANCH, not main"

git fetch origin main --quiet
LOCAL_SHA="$(git rev-parse HEAD)"
REMOTE_SHA="$(git rev-parse origin/main)"
[[ "$LOCAL_SHA" == "$REMOTE_SHA" ]] || refuse "local main ($LOCAL_SHA) is not origin/main ($REMOTE_SHA)"

# ---- Re-entry: does HEAD already carry a CalVer tag? ----
HEAD_TAG="$(git tag -l 'v20*' --points-at HEAD | sort -V | tail -1)"

TAG_JUST_CUT=""
if [[ -n "$HEAD_TAG" ]]; then
  say "RE-ENTRY: HEAD already tagged $HEAD_TAG — skipping the tag phase, bumping only the consumers still lagging it."
  TAG_JUST_CUT="$HEAD_TAG"
else
  LAST_TAG="$(git tag -l 'v20*' --sort=-v:refname | head -1)"

  if [[ -n "$LAST_TAG" ]] && git diff --quiet "$LAST_TAG" HEAD -- .pre-commit-hooks.yaml git-hooks/; then
    say "No export changed since $LAST_TAG — nothing to release."
    exit 0
  fi

  TODAY="$(TZ=UTC date +%Y.%m.%d)"
  BASE_TAG="v${TODAY}"
  EXISTING_TODAY="$(git tag -l "${BASE_TAG}*" --sort=-v:refname)"

  if [[ -z "$EXISTING_TODAY" ]]; then
    NEW_TAG="$BASE_TAG"
  else
    MAX_N=1
    while IFS= read -r t; do
      [[ -z "$t" ]] && continue
      if [[ "$t" == "$BASE_TAG" ]]; then
        continue # bare tag counts as N=1, already the floor
      elif [[ "$t" =~ ^${BASE_TAG}-([0-9]+)$ ]]; then
        n="${BASH_REMATCH[1]}"
        (( n > MAX_N )) && MAX_N=$n
      else
        refuse "existing tag $t for today doesn't fit the scheme ($BASE_TAG or $BASE_TAG-N) — never inventing a form"
      fi
    done <<< "$EXISTING_TODAY"
    NEW_TAG="${BASE_TAG}-$((MAX_N + 1))"
  fi

  git ls-remote --exit-code --tags origin "refs/tags/$NEW_TAG" >/dev/null 2>&1 && \
    refuse "computed tag $NEW_TAG already exists on origin (race, or a hand-cut tag not yet fetched)"

  if [[ "$DRY_RUN" == "1" ]]; then
    say "DRY-RUN: would cut $NEW_TAG"
  else
    say "Cutting $NEW_TAG"
    git tag -a "$NEW_TAG" -m "$NEW_TAG"
    git push origin "refs/tags/$NEW_TAG"
  fi
  TAG_JUST_CUT="$NEW_TAG"
fi

# Tag and Release are checked/created independently, in both the
# fresh-cut and re-entry paths — a failure between pushing the tag and
# cutting the Release must not leave the Release permanently uncut on
# the next run (the same class of gap caught in the CI-side release job;
# re-entry here only skips the *tag*, never silently skips the Release).
if [[ "$DRY_RUN" != "1" ]]; then
  if gh release view "$TAG_JUST_CUT" --repo lexijamesesq/dotty >/dev/null 2>&1; then
    say "Release $TAG_JUST_CUT already exists"
  else
    say "Cutting Release $TAG_JUST_CUT"
    gh release create "$TAG_JUST_CUT" --repo lexijamesesq/dotty --generate-notes
  fi
fi

# ---- Consumer discovery: enumerate at run time, dedup by remote URL ----
# Newline-accumulated string, not an associative array — this repo's own
# machines run macOS's stock bash 3.2 (confirmed: `env bash --version` on
# the Mini resolves to 3.2.57, no Homebrew bash installed), which has no
# `declare -A`.
SEEN_REMOTES=$'\n'
CONSUMERS=()
while IFS= read -r -d '' cfg; do
  git_root="$(git -C "$(dirname "$cfg")" rev-parse --show-toplevel 2>/dev/null)" || continue
  grep -q '^\s*-\s*repo:\s*https://github.com/lexijamesesq/dotty\s*$' "$cfg" || continue
  remote_url="$(git -C "$git_root" remote get-url origin 2>/dev/null)" || continue
  norm="${remote_url%.git}"
  case "$SEEN_REMOTES" in
    *$'\n'"$norm"$'\n'*) continue ;;
  esac
  SEEN_REMOTES="${SEEN_REMOTES}${norm}"$'\n'

  # hazel's deploy/ is excluded — it follows dev by the operator's own
  # deploy, never a bump PR. Detected by branch name, not repo name, so
  # this holds even if a deploy worktree/checkout exists elsewhere.
  branch="$(git -C "$git_root" rev-parse --abbrev-ref HEAD 2>/dev/null || echo "")"
  if [[ "$branch" == "deploy" ]]; then
    say "Excluding $git_root (on the deploy branch — follows dev by the operator's deploy, never a bump PR)"
    continue
  fi

  CONSUMERS+=("$git_root")
done < <(find "${CONSUMER_ROOTS[@]}" -maxdepth 4 -iname ".pre-commit-config.yaml" -print0 2>/dev/null)

say "Found ${#CONSUMERS[@]} consumer(s) pinning dotty's exports."

# Explicit length guard, not a bare "${CONSUMERS[@]}" — bash 3.2 (this
# machine's real /bin/bash) treats referencing an empty array under
# set -u as an unbound-variable error; caught by testing the zero-export
# / zero-consumer case, not assumed.
if [[ ${#CONSUMERS[@]} -eq 0 ]]; then
  say "No consumers found — nothing to bump."
  exit 0
fi

for consumer in "${CONSUMERS[@]}"; do
  repo_name="$(basename "$consumer")"
  cfg="$consumer/.pre-commit-config.yaml"
  # [[:space:]]*, not \s* — BSD sed (the machine's real /usr/bin/sed) does
  # not support \s as a shorthand class in extended-regex mode, unlike
  # GNU sed; using it here silently left a leading space in the captured
  # rev, caught by re-running this against the real 7 consumer repos.
  current_rev="$(grep -A1 '^\s*-\s*repo:\s*https://github.com/lexijamesesq/dotty\s*$' "$cfg" | grep 'rev:' | head -1 | sed -E 's/.*rev:[[:space:]]*//')"

  if [[ "$current_rev" == "$TAG_JUST_CUT" ]]; then
    say "  $repo_name: already at $TAG_JUST_CUT, skipping"
    continue
  fi

  if [[ "$DRY_RUN" == "1" ]]; then
    say "  $repo_name: DRY-RUN — would bump $current_rev -> $TAG_JUST_CUT (branch $BUMP_BRANCH)"
    continue
  fi

  say "  $repo_name: bumping $current_rev -> $TAG_JUST_CUT"
  ( cd "$consumer"
    git fetch origin --quiet
    # Fast form: reads the remote's advertised HEAD symref directly,
    # rather than git remote show's full (slower) round trip.
    default_branch="$(git ls-remote --symref origin HEAD | sed -n 's#^ref: refs/heads/\(.*\)\tHEAD#\1#p')"
    if git ls-remote --exit-code --heads origin "$BUMP_BRANCH" >/dev/null 2>&1; then
      git checkout -B "$BUMP_BRANCH" "origin/$BUMP_BRANCH"
      git reset --hard "origin/$default_branch"
    else
      git checkout -B "$BUMP_BRANCH" "origin/$default_branch"
    fi
    pre-commit autoupdate --repo https://github.com/lexijamesesq/dotty
    if git diff --quiet -- "$cfg" 2>/dev/null; then
      say "    no change after autoupdate — skipping PR"
    else
      git add "$cfg"
      git commit -q -m "chore: bump dotty pre-commit pin to $TAG_JUST_CUT"
      git push -u origin "$BUMP_BRANCH" --force-with-lease
      # No --repo needed: gh infers it from this directory's own origin
      # remote, which is exactly this consumer, not a git-URL string.
      if gh pr view "$BUMP_BRANCH" >/dev/null 2>&1; then
        say "    updated existing PR on $BUMP_BRANCH"
      else
        gh pr create --head "$BUMP_BRANCH" --base "$default_branch" \
          --title "chore: bump dotty pre-commit pin to $TAG_JUST_CUT" \
          --body "Automated bump — $consumer's pin to lexijamesesq/dotty's exported hooks was behind $TAG_JUST_CUT."
      fi
    fi
    git checkout "$default_branch"
  )
done
