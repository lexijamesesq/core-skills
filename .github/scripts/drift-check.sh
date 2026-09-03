#!/usr/bin/env bash
# drift-check.sh — proves the content this repo duplicates from dotty is
# still byte-identical to dotty's CURRENT main, not frozen at whatever SHA
# it was extracted from.
#
# Why this exists: the skills/agent move into this repo (and the hooks/statusline
# packaging before it) is a deliberate temporary duplicate — dotty keeps
# its own copies until a later cutover ticket removes them. A duplicate
# that can silently drift out of sync with its source is worse than no
# duplicate at all, so this check re-resolves dotty's live HEAD on every
# run and diffs against it — never a pinned historical SHA (a frozen-SHA
# comparison would miss exactly the drift direction that matters: dotty's
# copy is the actively-used one during this window, so IT is what's more
# likely to move out from under the plugin's promise of parity).
#
# Exit 0 iff every tracked pair is byte-identical, except the one
# documented, intentional exception below.
set -euo pipefail

DOTTY_CLONE="${1:?usage: drift-check.sh <path-to-fresh-dotty-clone> <path-to-this-repo>}"
WL_ROOT="${2:?usage: drift-check.sh <path-to-fresh-dotty-clone> <path-to-this-repo>}"

# Skills + the one agent moved into this repo, duplicated at
# dotty:.claude/skills/<name> <-> here:plugins/work-lifecycle/skills/<name>.
# house-qa is deliberately not compared here: the packaged copy carries a
# path fix dotty's copy will never receive, because dotty's copy is deleted
# by the next slice in this series.
SKILLS=(
  linear traffic-cone wayfinder vertical-slice grilling prototype
  domain-modeling research dispatch attack-kitty publish smoke
  sample-universe github-readme project-state session-start session-closeout
)

# Hook scripts duplicated by the earlier estate-hooks spike,
# dotty:.claude/hooks/<name> <-> here:plugins/estate-hooks/hooks/<name>,
# except gitleaks-common.sh which sources from dotty's separate git-hooks/.
HOOK_SCRIPTS=(
  pr-cache.sh vault-mcp-redirect.sh git-hook-bypass-guard.sh
  gh-pr-body-guard.sh linear-transition-guard.sh
  gated-verb-standalone-guard.sh fix-obsidian-claude-sync.sh
  session-init.sh
)

# gh-pr-body-guard.sh's source line is the one documented, intentional
# packaging delta (a cache can't resolve dotty's "../../git-hooks/" layout,
# so the packaged copy sources gitleaks-common.sh as a sibling instead) —
# recorded on this repo's originating spike. Every other file must match
# dotty's current main exactly.
EXPECTED_DELTA_FILES=("gh-pr-body-guard.sh")

fail=0

diff_one() {
  local label="$1" src="$2" dst="$3" allow_delta="${4:-0}"
  if [[ ! -f "$src" ]]; then
    echo "DRIFT-CHECK FAIL: $label — dotty source missing at $src (staleness — the source moved)"
    fail=1
    return
  fi
  if [[ ! -f "$dst" ]]; then
    echo "DRIFT-CHECK FAIL: $label — packaged copy missing at $dst"
    fail=1
    return
  fi
  if ! diff -q "$src" "$dst" >/dev/null 2>&1; then
    if [[ "$allow_delta" == "1" ]]; then
      echo "OK (documented delta): $label differs from dotty as expected"
    else
      echo "DRIFT-CHECK FAIL: $label has drifted from dotty main — $src vs $dst"
      fail=1
    fi
  else
    echo "OK: $label matches dotty main"
  fi
}

for skill in "${SKILLS[@]}"; do
  src_dir="$DOTTY_CLONE/.claude/skills/$skill"
  dst_dir="$WL_ROOT/plugins/work-lifecycle/skills/$skill"
  if [[ ! -d "$src_dir" ]]; then
    echo "DRIFT-CHECK FAIL: skill '$skill' — dotty source dir missing at $src_dir"
    fail=1
    continue
  fi
  if [[ ! -d "$dst_dir" ]]; then
    echo "DRIFT-CHECK FAIL: skill '$skill' — packaged copy dir missing at $dst_dir"
    fail=1
    continue
  fi
  # Compare git-tracked files only — dotty's own .gitignore already keeps
  # __pycache__/.pytest_cache/.DS_Store etc. out of `git ls-files`.
  while IFS= read -r rel; do
    diff_one "skill $skill / $rel" "$src_dir/$rel" "$dst_dir/$rel"
  done < <(git -C "$DOTTY_CLONE" ls-files ".claude/skills/$skill" | sed "s|^\.claude/skills/$skill/||")
done

diff_one "agent attack-kitty.md" \
  "$DOTTY_CLONE/.claude/agents/attack-kitty.md" \
  "$WL_ROOT/plugins/work-lifecycle/agents/attack-kitty.md"

for hook in "${HOOK_SCRIPTS[@]}"; do
  allow=0
  for delta in "${EXPECTED_DELTA_FILES[@]}"; do
    [[ "$hook" == "$delta" ]] && allow=1
  done
  diff_one "hook $hook" \
    "$DOTTY_CLONE/.claude/hooks/$hook" \
    "$WL_ROOT/plugins/estate-hooks/hooks/$hook" \
    "$allow"
done

diff_one "gitleaks-common.sh" \
  "$DOTTY_CLONE/git-hooks/gitleaks-common.sh" \
  "$WL_ROOT/plugins/estate-hooks/hooks/gitleaks-common.sh"

if [[ "$fail" -ne 0 ]]; then
  echo
  echo "DRIFT DETECTED — dotty main has moved and this repo's duplicate content"
  echo "hasn't been re-synced. Re-copy the drifted file(s) from dotty's current"
  echo "main and re-verify (see this repo's originating spike's ruling comments bb62d4da / e555d36f"
  echo "/ 49d58312 for the disposition each duplicate carries)."
  exit 1
fi

echo
echo "All duplicated content matches dotty main. No drift."
