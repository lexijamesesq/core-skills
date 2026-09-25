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
# with the shared command-position match below.
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

# The same normalisation gh-pr-body-guard.sh uses: continuations stripped,
# newlines become separators, whitespace collapsed, shell quotes dropped.
_norm="${COMMAND//\\$'\n'/ }"
_norm="${_norm//$'\n'/ ; }"
_norm="$(tr -s '[:space:]' ' ' <<<"$_norm")"
_norm="${_norm//\"/}"
_norm="${_norm//\'/}"

# GH IN COMMAND POSITION — one definition, kept IDENTICAL in five hooks:
# gh-pr-body-guard.sh, gh-pr-body-template-guard.sh, pr-cache.sh,
# pr-verdict-watch-arm.sh and security-review-reminder.sh. No shared file
# fits: the two helpers these hooks source (gitleaks-common.sh,
# house-code-common.sh) are drift-checked byte-for-byte against dotty.
# Change all five together.
#
# Command position = start of string, or after a separator (; && || | ( `),
# optionally preceded by wrapper words (env/time/sudo/nohup/command) and by
# leading env assignments (FOO=bar gh pr create ...). The gh token is any of:
#   gh                       bare, on PATH
#   <anything>/gh            a path ending in /gh — the estate's mandated
#                            wrapper is invoked by path, never as bare `gh`
#   $NAME / ${NAME}          a shell variable holding that path
# shellcheck disable=SC2016  # regex-literal dollar (\$NAME), not a shell expansion
_GH_CMD='(^|[;&|(`])[[:space:]]*((env|time|sudo|nohup|command)[[:space:]]+)*([A-Za-z_][A-Za-z0-9_]*=[^ ]* )*(gh|[^ ;&|(`]*/gh|\$[A-Za-z_][A-Za-z0-9_]*|\$\{[A-Za-z_][A-Za-z0-9_]*\})[[:space:]]+pr[[:space:]]+'
_RE_CREATE="${_GH_CMD}"'create([[:space:]]|$)'
[[ "$_norm" =~ $_RE_CREATE ]] || exit 0

echo 'Reminder: run /security-review before creating PRs for substantive changes.'
exit 0
