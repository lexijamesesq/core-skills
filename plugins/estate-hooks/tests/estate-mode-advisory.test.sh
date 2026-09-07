#!/usr/bin/env bash
# Test for estate-mode-advisory.sh (SessionStart): states the identity mode by
# profile AND enrollment (personal + estate files present -> estate mode;
# personal + files absent -> NOT enrolled), and is silent outside a session.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/assert.sh"
HOOK="${HOOK:-${SCRIPT_DIR}/../hooks/estate-mode-advisory.sh}"
[[ -f "$HOOK" ]] || { echo "FATAL: $HOOK not found"; exit 2; }

# enrolled scratch HOME
ENR="$(mktemp -d)"; mkdir -p "$ENR/.config/claude-estate"; : > "$ENR/.config/claude-estate/estate-mode.gitconfig"
# not-enrolled scratch HOME (dir exists, gitconfig absent)
UNE="$(mktemp -d)"; mkdir -p "$UNE/.config/claude-estate"
trap 'rm -rf "$ENR" "$UNE"' EXIT

run() { env -i HOME="$1" CLAUDECODE="$2" CLAUDE_CONFIG_DIR="$3" PATH="/usr/bin:/bin" bash "$HOOK" 2>/dev/null; }

section "personal + enrolled -> estate mode"
out="$(run "$ENR" 1 "$ENR/.claude-personal")"
rc=0; [[ "$out" == *"Estate identity mode"* ]] || rc=1
assert_eq "enrolled personal -> estate mode line" "0" "$rc"

section "personal + NOT enrolled -> not-enrolled advisory"
out="$(run "$UNE" 1 "$UNE/.claude-personal")"
rc=0; [[ "$out" == *"NOT enrolled"* ]] || rc=1
assert_eq "unenrolled personal -> not-enrolled line" "0" "$rc"

section "professional -> employer mode; non-session -> silent"
out="$(run "$ENR" 1 "$ENR/.claude-professional")"
rc=0; [[ "$out" == *"Employer identity mode"* ]] || rc=1
assert_eq "professional -> employer mode line" "0" "$rc"
out="$(run "$ENR" "" "$ENR/.claude-personal")"
rc=0; [[ -z "$out" ]] || rc=1
assert_eq "not a session -> silent" "0" "$rc"

finish
