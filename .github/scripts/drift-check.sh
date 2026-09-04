#!/usr/bin/env bash
# drift-check.sh — proves the one duplicate this repo still carries from
# dotty is byte-identical to dotty's CURRENT main, not frozen at whatever
# SHA it was extracted from.
#
# Narrowed after dotty's own copies were retired: this repo used to duplicate dotty's 18 packaged
# skills, the attack-kitty agent, nine hook scripts, and the statusline —
# all deliberate temporary duplicates pending dotty's own cutover-deletion
# slice. That slice ran; dotty's copies are gone, so every one of those
# comparisons would now fail with "dotty source missing" (staleness, not
# drift) rather than test anything real. gitleaks-common.sh is the one
# duplicate that remains by design: it sources from dotty's separate
# git-hooks/ (the pre-commit export channel, never deleted, never packaged
# elsewhere), so it still needs a live drift check.
#
# Exit 0 iff the one tracked pair is byte-identical.
set -euo pipefail

DOTTY_CLONE="${1:?usage: drift-check.sh <path-to-fresh-dotty-clone> <path-to-this-repo>}"
WL_ROOT="${2:?usage: drift-check.sh <path-to-fresh-dotty-clone> <path-to-this-repo>}"

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

diff_one "gitleaks-common.sh" \
  "$DOTTY_CLONE/git-hooks/gitleaks-common.sh" \
  "$WL_ROOT/plugins/estate-hooks/hooks/gitleaks-common.sh"

if [[ "$fail" -ne 0 ]]; then
  echo
  echo "DRIFT DETECTED — dotty main has moved and gitleaks-common.sh"
  echo "hasn't been re-synced. Re-copy it from dotty's current git-hooks/"
  echo "and re-verify."
  exit 1
fi

echo
echo "gitleaks-common.sh matches dotty main. No drift."
