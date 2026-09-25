#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2088  # payload strings are LITERAL shell text ($GH, ~/…): never expanded here
# Test suite for estate-hooks/hooks/gh-scope-common.sh — the ONE definition
# of "gh pr <verb> in command position" — and for the contract that every PR
# hook consumes it rather than carrying its own copy.
#
# Three things are proven here:
#   1. Conformance: each of the five PR hooks sources gh-scope-common.sh by a
#      ${BASH_SOURCE[0]}-relative path, and NO hook defines the rule locally
#      (no `_GH_CMD=`, no inline copy of the regex). This is the drift guard
#      the non-author review asked for: the rule was five comment-synced
#      copies, and this test fails the moment a sixth appears.
#   2. The rule itself: every shape the estate uses matches; look-alikes and
#      mere mentions do not.
#   3. Missing helper, per contract: the fail-open hooks (pr-cache,
#      pr-verdict-watch-arm, security-review-reminder) say nothing and exit
#      0; the fail-closed guards (gh-pr-body-guard, gh-pr-body-template-guard)
#      BLOCK (exit 2) naming the missing file.
#
# Run: bash this-file.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/assert.sh"

HOOKS_DIR="${SCRIPT_DIR}/../hooks"
HELPER="$HOOKS_DIR/gh-scope-common.sh"
[[ -f "$HELPER" ]] || {
	echo "FATAL: $HELPER not found"
	exit 2
}
command -v jq >/dev/null 2>&1 || {
	echo "FATAL: jq required for these tests"
	exit 2
}

CONSUMERS=(gh-pr-body-guard.sh gh-pr-body-template-guard.sh pr-cache.sh pr-verdict-watch-arm.sh security-review-reminder.sh)
FAIL_OPEN=(pr-cache.sh pr-verdict-watch-arm.sh security-review-reminder.sh)
FAIL_CLOSED=(gh-pr-body-guard.sh gh-pr-body-template-guard.sh)

# ============================================================================
# 1. Conformance.
# ============================================================================
section "every PR hook sources gh-scope-common.sh by a BASH_SOURCE-relative path"
for h in "${CONSUMERS[@]}"; do
	if grep -qE '^[[:space:]]*source "\$HERE/gh-scope-common\.sh"' "$HOOKS_DIR/$h" &&
		grep -qE 'HERE="\$\(cd "\$\(dirname "\$\{BASH_SOURCE\[0\]\}"\)" && pwd\)"' "$HOOKS_DIR/$h"; then
		pass "$h sources \$HERE/gh-scope-common.sh"
	else
		fail "$h sources \$HERE/gh-scope-common.sh" "no source line found"
	fi
done

section "no hook defines the rule locally (the helper is the only copy)"
# The regex's distinctive fragment: the path-ending-in-/gh alternative.
FRAG='[^ ;&|(`]*/gh'
for f in "$HOOKS_DIR"/*.sh; do
	b="$(basename "$f")"
	[[ "$b" == "gh-scope-common.sh" ]] && continue
	if grep -qF "$FRAG" "$f" || grep -qE '^[[:space:]]*_GH_CMD=' "$f"; then
		fail "$b carries no local copy of the rule" "found _GH_CMD= or the regex fragment"
	else
		pass "$b carries no local copy of the rule"
	fi
done
grep -qF "$FRAG" "$HELPER" && pass "the helper carries the rule" || fail "the helper carries the rule" "fragment absent"

# ============================================================================
# 2. The rule.
# ============================================================================
# shellcheck source=../hooks/gh-scope-common.sh
source "$HELPER"

section "gh_pr_in_command_position: every shape the estate uses matches"
for c in 'gh pr create --fill' '/opt/estate/bin/gh pr create --title x' '~/.local/bin/gh pr create' '$GH pr create' '${GH} pr create' '"$GH" pr create' 'time env FOO=bar gh pr create' 'cd ~/x && /opt/estate/bin/gh pr create' $'bash <<\'B\'\nGH=/opt/estate/bin/gh\n$GH pr create --fill\nB' $'gh pr \\\ncreate' 'out=$(gh pr create --fill)' 'gh pr "create"'; do
	if gh_pr_in_command_position "$c" create; then pass "matches: ${c//$'\n'/⏎}"; else fail "matches: ${c//$'\n'/⏎}" "no match"; fi
done

section "gh_pr_in_command_position: verb alternation and non-matches"
gh_pr_in_command_position 'gh pr edit 3 --body x' "create|edit" && pass "edit via alternation" || fail "edit via alternation" "no match"
gh_pr_in_command_position 'gh pr merge 3' "create|merge" && pass "merge via alternation" || fail "merge via alternation" "no match"
for c in 'echo "gh pr create"' 'echo "$GH pr create"' 'grep "gh pr create" f' '/opt/bin/ghost pr create' 'gh pr createfoo' 'gh pr view 3' 'git status' 'c=create; gh pr $c'; do
	if gh_pr_in_command_position "$c" create; then fail "does not match: $c" "matched"; else pass "does not match: $c"; fi
done
gh_pr_in_command_position 'gh pr edit 3' create && fail "edit is not create" "matched" || pass "edit is not create"

section "gh_scope_normalize (a trailing space from tr is expected; the rule tolerates it)"
norm() {
	local n
	n="$(gh_scope_normalize "$1")"
	printf '%s' "${n% }"
}
assert_eq "continuation joined" "gh pr create --fill" "$(norm $'gh pr \\\ncreate --fill')"
assert_eq "newline becomes a separator" "a ; b" "$(norm $'a\nb')"
assert_eq "quotes stripped, whitespace collapsed" "gh pr create" "$(norm '"gh"   pr  '"'"'create'"'"'')"

section "gh_scope_target_dir / gh_scope_cd_chain_dir: where gh runs"
CDT="$(mktemp -d -t gh-scope-cd.XXXXXX)"
CDT="$(cd "$CDT" && pwd)"
mkdir -p "$CDT/a/sub" "$CDT/b" "$CDT/home/tilde-repo" "$CDT/with space"
assert_eq "no cd: the payload cwd" "$CDT/b" "$(gh_scope_target_dir 'gh pr create --fill' "$CDT/b")"
assert_eq "single absolute cd" "$CDT/a" "$(gh_scope_target_dir "cd $CDT/a && gh pr create" "$CDT/b")"
assert_eq "relative cd appends to the payload cwd" "$CDT/a/sub" "$(gh_scope_target_dir 'cd sub && gh pr create' "$CDT/a")"
assert_eq "chained cd: the LAST cd wins" "$CDT/a/sub" "$(gh_scope_target_dir "cd $CDT/a && cd sub && gh pr create" "$CDT/b")"
assert_eq "absolute mid-chain target replaces" "$CDT/b" "$(gh_scope_target_dir "cd $CDT/a && cd $CDT/b && gh pr create" "$CDT")"
assert_eq "; and || are separators too" "$CDT/a/sub" "$(gh_scope_target_dir "cd $CDT/a; cd sub || exit 1; gh pr create" "$CDT/b")"
assert_eq "newline is a separator" "$CDT/a" "$(gh_scope_target_dir $'cd '"$CDT"$'/a\ngh pr create' "$CDT/b")"
assert_eq "~ expands under HOME" "$CDT/home/tilde-repo" "$(HOME="$CDT/home" gh_scope_target_dir 'cd ~/tilde-repo && gh pr create' "$CDT/b")"
assert_eq "\$HOME expands" "$CDT/home/tilde-repo" "$(HOME="$CDT/home" gh_scope_target_dir 'cd $HOME/tilde-repo && gh pr create' "$CDT/b")"
assert_eq "backslash-escaped space in the path" "$CDT/with space" "$(gh_scope_target_dir "cd $CDT/with\\ space && gh pr create" "$CDT/b")"
assert_eq "a cd that fails to resolve: chain dir is EMPTY (never guessed)" "" "$(gh_scope_cd_chain_dir "cd $CDT/a ; cd nonexistent ; gh pr create" "$CDT/b")"
assert_eq "a cd that fails to resolve: target falls back to the payload cwd" "$CDT/b" "$(gh_scope_target_dir "cd $CDT/nonexistent && gh pr create" "$CDT/b")"
assert_eq "cd with no argument: chain dir is EMPTY" "" "$(gh_scope_cd_chain_dir "cd ; gh pr create" "$CDT/b")"
assert_eq "no leading cd: chain dir is EMPTY" "" "$(gh_scope_cd_chain_dir "gh pr create && cd $CDT/a" "$CDT/b")"
rm -rf "$CDT"

# ============================================================================
# 3. Missing helper, per contract.
# ============================================================================
TMP="$(mktemp -d -t gh-scope-test.XXXXXX)"
trap 'rm -rf "$TMP"' EXIT INT TERM
ISO="$TMP/hooks"
mkdir -p "$ISO"
cp "$HOOKS_DIR"/*.sh "$HOOKS_DIR"/pr-body-check.py "$ISO/"
rm -f "$ISO/gh-scope-common.sh"
PAYLOAD="$(jq -nc --arg cwd "$TMP" '{tool_name:"Bash",tool_input:{command:"gh pr create --fill"},tool_response:"https://github.com/o/r/pull/1\n",cwd:$cwd}')"

section "helper missing: fail-open hooks say nothing and exit 0"
for h in "${FAIL_OPEN[@]}"; do
	RC=0
	OUT="$(printf '%s' "$PAYLOAD" | bash "$ISO/$h" 2>/dev/null)" || RC=$?
	assert_eq "$h exits 0 without the helper" "0" "$RC"
	assert_eq "$h is silent without the helper" "" "$OUT"
done

section "helper missing: fail-closed guards BLOCK (exit 2) naming the file"
for h in "${FAIL_CLOSED[@]}"; do
	RC=0
	ERR="$(printf '%s' "$PAYLOAD" | bash "$ISO/$h" 2>&1 >/dev/null)" || RC=$?
	assert_eq "$h exits 2 without the helper" "2" "$RC"
	case "$ERR" in
	*"gh-scope-common.sh is missing"*) pass "$h names the missing helper" ;;
	*) fail "$h names the missing helper" "got: $ERR" ;;
	esac
done

finish
