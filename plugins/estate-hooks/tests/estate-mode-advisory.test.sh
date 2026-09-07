#!/usr/bin/env bash
# Test for estate-mode-advisory.sh (SessionStart): states the identity mode by
# profile, and stays silent outside a Claude session.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/assert.sh"
HOOK="${HOOK:-${SCRIPT_DIR}/../hooks/estate-mode-advisory.sh}"
[[ -f "$HOOK" ]] || { echo "FATAL: $HOOK not found"; exit 2; }

run() { env -i HOME=/tmp CLAUDECODE="$1" CLAUDE_CONFIG_DIR="$2" PATH="/usr/bin:/bin" bash "$HOOK" 2>/dev/null; }

section "SessionStart advisory states the mode by profile"
out="$(run 1 /Users/x/.claude-personal)"
rc=0; [[ "$out" == *"Estate identity mode"* ]] || rc=1
assert_eq "personal -> estate mode advisory" "0" "$rc"
out="$(run 1 /Users/x/.claude-professional)"
rc=0; [[ "$out" == *"Employer identity mode"* ]] || rc=1
assert_eq "professional -> employer mode advisory" "0" "$rc"
out="$(run "" /Users/x/.claude-personal)"
rc=0; [[ -z "$out" ]] || rc=1
assert_eq "not a session -> silent" "0" "$rc"
out="$(run 1 /Users/x/.claude-weird)"
rc=0; [[ -z "$out" ]] || rc=1
assert_eq "unrecognized profile -> silent" "0" "$rc"

finish
