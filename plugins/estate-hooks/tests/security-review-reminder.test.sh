#!/usr/bin/env bash
# shellcheck disable=SC2016,SC2088  # payload strings are LITERAL shell text ($GH, ~/…): never expanded here
# Test suite for estate-hooks/hooks/security-review-reminder.sh — scope only.
#
# The reminder replaced an inline `echo` whose `if: Bash(gh pr create *)`
# prefilter never matched the estate's real create commands (wrapper path,
# $GH, heredoc). It must print its one line on every create shape, stay
# silent on everything else, and never exit non-zero. Synthetic payloads only.
#
# Run: bash this-file.

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/assert.sh"

HOOK="${HOOK:-${SCRIPT_DIR}/../hooks/security-review-reminder.sh}"
[[ -f "$HOOK" ]] || {
	echo "FATAL: $HOOK not found"
	exit 2
}
command -v jq >/dev/null 2>&1 || {
	echo "FATAL: jq required for these tests"
	exit 2
}

run_case() { # <command> -> RC, OUT
	RC=0
	OUT="$(jq -nc --arg cmd "$1" '{tool_name:"Bash",tool_input:{command:$cmd}}' | bash "$HOOK" 2>/dev/null)" || RC=$?
}
reminds() { # <label> <command>
	run_case "$2"
	assert_eq "$1: exits 0" "0" "$RC"
	case "$OUT" in
	*"/security-review"*) pass "$1: prints the reminder" ;;
	*) fail "$1: prints the reminder" "got: '$OUT'" ;;
	esac
}
silent() { # <label> <command>
	run_case "$2"
	assert_eq "$1: exits 0" "0" "$RC"
	[[ -z "$OUT" ]] && pass "$1: silent" || fail "$1: silent" "got: '$OUT'"
}

section "Reminds on every create shape"
reminds "bare gh" 'gh pr create --fill'
reminds "wrapper path" '/opt/estate/bin/gh pr create --title x'
reminds "tilde wrapper path" '~/.local/bin/gh pr create --title x'
reminds "variable \$GH" '$GH pr create --title x'
reminds "quoted \"\${GH}\"" '"${GH}" pr create --title x'
reminds "heredoc'd script" $'bash <<\'B\'\nGH=/opt/estate/bin/gh\n$GH pr create --fill\nB'
reminds "cd prefix" 'cd ~/Repos/x && /opt/estate/bin/gh pr create --fill'
reminds "env assignment" 'GH_TOKEN=x gh pr create --fill'

section "Silent otherwise"
silent "gh pr edit" 'gh pr edit 3 --title x'
silent "gh pr view" '/opt/estate/bin/gh pr view 3'
silent "mere mention" 'echo "$GH pr create"'
silent "path merely containing gh" '/opt/bin/ghost pr create'
silent "look-alike subcommand" 'gh pr createfoo'
silent "unrelated" 'git status'

section "Fail-open"
RC=0
OUT="$(printf '' | bash "$HOOK" 2>/dev/null)" || RC=$?
assert_eq "empty stdin exits 0" "0" "$RC"
assert_eq "empty stdin silent" "" "$OUT"
RC=0
OUT="$(printf 'not-json' | bash "$HOOK" 2>/dev/null)" || RC=$?
assert_eq "garbage stdin exits 0" "0" "$RC"
RC=0
OUT="$(jq -nc '{tool_name:"Read",tool_input:{file_path:"x"}}' | bash "$HOOK" 2>/dev/null)" || RC=$?
assert_eq "non-Bash tool exits 0" "0" "$RC"
assert_eq "non-Bash tool silent" "" "$OUT"

finish
