#!/usr/bin/env bash
# Shared scanner helpers and PR-body parser must match the supplied dotty source.
# Exit 0 iff every tracked pair is byte-identical.
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
			echo "DRIFT-CHECK FAIL: $label has drifted from supplied dotty source — $src vs $dst"
			fail=1
		fi
	else
		echo "OK: $label matches supplied dotty source"
	fi
}

diff_one "gitleaks-common.sh" \
	"$DOTTY_CLONE/git-hooks/gitleaks-common.sh" \
	"$WL_ROOT/plugins/estate-hooks/hooks/gitleaks-common.sh"

diff_one "house-code-common.sh" \
	"$DOTTY_CLONE/git-hooks/house-code-common.sh" \
	"$WL_ROOT/plugins/estate-hooks/hooks/house-code-common.sh"

diff_one "pr-body-check.py" \
	"$DOTTY_CLONE/.github/scripts/pr-body-check.py" \
	"$WL_ROOT/plugins/estate-hooks/hooks/pr-body-check.py"

if [[ "$fail" -ne 0 ]]; then
	echo
	echo "DRIFT DETECTED — supplied dotty source has moved and a tracked duplicate"
	echo "hasn't been re-synced. Re-copy it from the matching dotty source"
	echo "and re-verify."
	exit 1
fi

echo
echo "Shared scanner helpers and PR-body checker match supplied dotty source. No drift."
