#!/usr/bin/env bash
# Test for estate-mode-advisory.sh (SessionStart): states the identity mode of a
# personal session from where ITS OWN GIT_CONFIG_GLOBAL points, as the gh adapter
# decides (App baseline -> estate mode; operator baseline -> operator mode;
# anything else -> NOT enrolled), and is silent outside a session. The estate
# gitconfig merely existing on disk does not decide it: it stays installed after
# the operator baseline takes over.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/assert.sh"
HOOK="${HOOK:-${SCRIPT_DIR}/../hooks/estate-mode-advisory.sh}"
[[ -f "$HOOK" ]] || {
	echo "FATAL: $HOOK not found"
	exit 2
}

# scratch HOME with BOTH baselines' gitconfigs installed, as the machine is after the operator baseline lands
BOTH="$(mktemp -d)"
mkdir -p "$BOTH/.config/claude-estate" "$BOTH/.config/claude-operator"
: >"$BOTH/.config/claude-estate/estate-mode.gitconfig"
: >"$BOTH/.config/claude-operator/operator-mode.gitconfig"
ESTATE_CFG="$BOTH/.config/claude-estate/estate-mode.gitconfig"
OPERATOR_CFG="$BOTH/.config/claude-operator/operator-mode.gitconfig"
trap 'rm -rf "$BOTH"' EXIT

# run <home> <CLAUDECODE> <config dir> [GIT_CONFIG_GLOBAL]
run() {
	local gcg=()
	[[ $# -ge 4 ]] && gcg=(GIT_CONFIG_GLOBAL="$4")
	env -i HOME="$1" CLAUDECODE="$2" CLAUDE_CONFIG_DIR="$3" PATH="/usr/bin:/bin" ${gcg[@]+"${gcg[@]}"} bash "$HOOK" 2>/dev/null
}

section "personal + App baseline in the session env -> estate mode"
out="$(run "$BOTH" 1 "$BOTH/.claude-personal" "$ESTATE_CFG")"
rc=0
[[ "$out" == *"Estate identity mode"* && "$out" == *"Claude App"* ]] || rc=1
assert_eq "App-baseline personal -> estate mode line naming the App" "0" "$rc"

section "personal + operator baseline in the session env -> operator mode, unsigned"
out="$(run "$BOTH" 1 "$BOTH/.claude-personal" "$OPERATOR_CFG")"
rc=0
[[ "$out" == *"Operator identity mode"* && "$out" == *"unsigned"* ]] || rc=1
assert_eq "operator-baseline personal -> operator mode line" "0" "$rc"
rc=0
[[ "$out" == *"claude-the-enduring"* ]] && rc=1
assert_eq "operator mode does not name the App's bot as the author" "0" "$rc"

# The defect this fixes: the estate gitconfig is on disk (it stays for the tick) while the session's env is the operator's.
section "estate gitconfig on disk, session env operator -> still operator mode"
out="$(run "$BOTH" 1 "$BOTH/.claude-personal" "$OPERATOR_CFG")"
rc=0
[[ "$out" == *"Estate identity mode"* ]] && rc=1
assert_eq "the estate file existing does not make an operator session an App session" "0" "$rc"

section "personal + neither baseline -> NOT enrolled (unset, or somewhere else)"
out="$(run "$BOTH" 1 "$BOTH/.claude-personal")"
rc=0
[[ "$out" == *"NOT enrolled"* && "$out" == *"<unset>"* ]] || rc=1
assert_eq "no GIT_CONFIG_GLOBAL -> not-enrolled line, even with both files installed" "0" "$rc"
out="$(run "$BOTH" 1 "$BOTH/.claude-personal" "/somewhere/else.gitconfig")"
rc=0
[[ "$out" == *"NOT enrolled"* && "$out" == *"/somewhere/else.gitconfig"* ]] || rc=1
assert_eq "an unrelated GIT_CONFIG_GLOBAL -> not-enrolled line naming it" "0" "$rc"

section "professional -> employer mode; non-session -> silent"
out="$(run "$BOTH" 1 "$BOTH/.claude-professional" "$ESTATE_CFG")"
rc=0
[[ "$out" == *"Employer identity mode"* ]] || rc=1
assert_eq "professional -> employer mode line" "0" "$rc"
out="$(run "$BOTH" "" "$BOTH/.claude-personal" "$OPERATOR_CFG")"
rc=0
[[ -z "$out" ]] || rc=1
assert_eq "not a session -> silent" "0" "$rc"

finish
