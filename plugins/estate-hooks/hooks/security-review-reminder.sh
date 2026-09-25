#!/usr/bin/env bash
# security-review-reminder.sh
#
# PreToolUse reminder on `gh pr create`: prints one line asking for a
# /security-review before a substantive PR is opened. Advisory only — it
# never blocks (always exit 0) and never inspects the PR.
#
# WHY A SCRIPT, NOT AN `echo` WITH AN `if` PREFILTER: this reminder used to
# be an inline `echo` registered with `"if": "Bash(gh pr create *)"`. That
# prefilter drops any command that does not START with the bare words
# `gh pr create` (unless it carries $(...), backticks, or $VAR), and the
# estate never runs bare `gh` — it invokes its wrapper by path or through a
# variable holding that path — so the reminder never fired on a real create
# (the same receipted defect as the three PR hooks). It now self-scopes
# with gh-scope-common.sh's command-position match.
#
# FAIL-OPEN: no jq, no input, wrong tool — say nothing, exit 0.

set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0
INPUT="$(cat 2>/dev/null || true)"
[[ -n "$INPUT" ]] || exit 0
TOOL_NAME="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)"
[[ "$TOOL_NAME" == "Bash" ]] || exit 0
COMMAND="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
[[ -n "$COMMAND" ]] || exit 0

# The rule lives in gh-scope-common.sh. Missing -> fail-open (say nothing).
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -r "$HERE/gh-scope-common.sh" ]] || exit 0
source "$HERE/gh-scope-common.sh"

gh_pr_in_command_position "$COMMAND" create || exit 0

echo 'Reminder: run /security-review before creating PRs for substantive changes.'
exit 0
