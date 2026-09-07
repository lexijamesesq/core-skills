#!/usr/bin/env bash
# Test suite for plugins/estate-hooks/hooks/git-push-publish-guard.sh
#
# The hook is a PreToolUse (Bash) guard that denies a bare `git push`, on the
# theory that a session's own commits publish through the App's helper
# (GraphQL createCommitOnBranch, scanned before it ever calls the API) and a
# local commit+push bypasses that scan entirely. Tests drive it with crafted
# stdin JSON and assert on exit code: 2 = blocked (deny), 0 = allowed / no
# opinion (fail-open).
#
# Covers:
#   - git push in its bare, flagged, and non-adjacent forms
#   - Negatives: git commands that are not a push must pass
#   - Case-insensitive match
#   - Accepted over-blocks (safe direction): "git" and "push" as separate
#     words for unrelated reasons, or "push" inside a commit message
#   - Fail-open posture on infra errors (jq absent, empty/garbage stdin,
#     non-Bash tool)
#
# Run: bash plugins/estate-hooks/tests/git-push-publish-guard.test.sh

set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/assert.sh"

HOOK="${HOOK:-${SCRIPT_DIR}/../hooks/git-push-publish-guard.sh}"
# Invoked via `bash "$HOOK"` below (hooks.json's own invocation form for
# every hook in this plugin) -- the executable bit is irrelevant, since
# createCommitOnBranch (the App's commit API) has no way to set it and
# every hook here is registered as an interpreter invocation rather than a
# direct exec. Only existence is a real precondition.
[[ -f "$HOOK" ]] || { echo "FATAL: $HOOK not found"; exit 2; }

command -v jq >/dev/null 2>&1 || { echo "FATAL: jq required to build test fixtures"; exit 2; }

# mkjson <command-string> -> PreToolUse stdin JSON for the Bash tool
mkjson() { jq -n --arg c "$1" '{tool_name:"Bash",tool_input:{command:$c}}'; }

# A deterministic UNENROLLED HOME. The guard is only active before enrollment
# (see the enrollment-handoff section), so every "active guard" assertion below
# runs against a HOME with no estate gitconfig — otherwise the suite would flip
# on a machine that happens to be enrolled.
GUARD_HOME="$(mktemp -d)"    # deliberately no ~/.config/claude-estate/estate-mode.gitconfig
trap 'rm -rf "$GUARD_HOME"' EXIT

# fire <json> -> hook exit code (in RC), under the unenrolled HOME
fire() { printf '%s' "$1" | env HOME="$GUARD_HOME" bash "$HOOK" >/dev/null 2>&1; RC=$?; }

expect_block() { fire "$(mkjson "$1")"; assert_eq "BLOCK: $1" "2" "$RC"; }
expect_allow() { fire "$(mkjson "$1")"; assert_eq "allow: $1" "0" "$RC"; }

# === Vector: bare and flagged git push ===
section "git push — bare and flagged forms"
expect_block 'git push'
expect_block 'git push origin main'
expect_block 'git push -u origin main'
expect_block 'git push --force-with-lease'
expect_block 'GIT PUSH'                          # case-insensitive match

# === Non-adjacent forms: flags between the verb and the subcommand ===
section "git push — flags between verb and subcommand"
expect_block 'git -C /some/path push'
expect_block 'git --git-dir=/some/path push origin main'
expect_block 'git -c core.hooksPath=/dev/null push'

# === Shell-operator-abutted push ===
section "git push — abutting a shell operator"
expect_block 'git add -A && git push'
expect_block 'git commit -m "x" && git push origin main'
expect_block 'git push; echo done'
expect_block 'git push|cat'

# === Whitespace normalization ===
section "whitespace normalization"
expect_block 'git   push   origin main'
printf -v tabcmd 'git\tpush\torigin main'
expect_block "$tabcmd"

# === Negatives — legit git commands must pass ===
section "negatives — must NOT block"
expect_allow 'git status'
expect_allow 'git commit -m "x"'
expect_allow 'git add -A'
expect_allow 'git log --oneline -5'
expect_allow 'git pull origin main'
expect_allow 'git fetch origin'
expect_allow 'git diff'
expect_allow 'gh pr create --title x --body y'
expect_allow 'git checkout -b feature'

# === Accepted over-blocks (documented, safe direction) ===
section "accepted over-blocks (safe direction)"
expect_block 'git log && push origin main'               # "push" names an unrelated command
expect_allow 'push_to_queue'                              # no word boundary around "push" -- not a match, by design
expect_block 'git commit -m "explain how git push works here"'  # message mentions it
expect_block 'echo "git push" && git log'                # both words, unrelated act

# === Enrollment hand-off — dormant when enrolled, active when not ===
# Once ~/.config/claude-estate/estate-mode.gitconfig exists on disk this machine
# is enrolled and the estate-identity guard owns pushes, so this blanket guard
# stands down (exit 0). Until then it stays active (exit 2). Keyed on the same
# disk fact as the identity guard; driven with an explicit scratch HOME each way.
section "enrollment hand-off — silent when enrolled, active when not"
ENROLLED_HOME="$(mktemp -d)"; mkdir -p "$ENROLLED_HOME/.config/claude-estate"
: > "$ENROLLED_HOME/.config/claude-estate/estate-mode.gitconfig"
UNENROLLED_HOME="$(mktemp -d)"    # no estate-mode.gitconfig on disk
# Feed stdin by here-string, NOT a `printf | hook` pipe: when enrolled the hook
# exits at the gate WITHOUT reading stdin, so a pipe can leave printf writing to
# a closed read end (EPIPE) — under `set -o pipefail` that surfaces as a spurious
# exit 1 (races on the runner's scheduling; seen on bash 5/Linux, not bash 3.2).
# A here-string has no pipe and no such race.
ENROLL_JSON="$(mkjson 'git push origin main')"
env HOME="$ENROLLED_HOME" bash "$HOOK" >/dev/null 2>&1 <<<"$ENROLL_JSON"
assert_eq "enrolled (gitconfig present) -> guard silent, push allowed" "0" "$?"
env HOME="$UNENROLLED_HOME" bash "$HOOK" >/dev/null 2>&1 <<<"$ENROLL_JSON"
assert_eq "not enrolled (gitconfig absent) -> guard active, push blocked" "2" "$?"
rm -rf "$ENROLLED_HOME" "$UNENROLLED_HOME"

# === Fail-open posture on infra errors ===
# Run under the unenrolled HOME so the enrollment gate does not short-circuit
# what these assertions actually test (the jq/parse fail-open paths).
section "fail-open — infra errors never block"
NOJQ=$(mktemp -d -t gppg-nojq.XXXXXX)
ln -s "$(command -v bash)" "$NOJQ/bash" 2>/dev/null
NOJQ_FIXTURE=$(mkjson 'git push')
PATH="$NOJQ" HOME="$GUARD_HOME" bash "$HOOK" <<<"$NOJQ_FIXTURE" >/dev/null 2>&1
assert_eq "jq absent -> exit 0 (fail-open)" "0" "$?"
rm -rf "$NOJQ"

printf 'not-json-at-all {{{' | HOME="$GUARD_HOME" bash "$HOOK" >/dev/null 2>&1
assert_eq "garbage stdin -> exit 0" "0" "$?"

printf '' | HOME="$GUARD_HOME" bash "$HOOK" >/dev/null 2>&1
assert_eq "empty stdin -> exit 0" "0" "$?"

printf '%s' '{"tool_name":"Read","tool_input":{"file_path":"/tmp/x"}}' | HOME="$GUARD_HOME" bash "$HOOK" >/dev/null 2>&1
assert_eq "non-Bash tool -> exit 0" "0" "$?"

finish
