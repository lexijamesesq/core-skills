#!/usr/bin/env bash
# pr-verdict-watch-arm.sh
#
# PostToolUse hook on `gh pr create`. Margot (the PR reviewer, a GitHub App)
# and the operator post their verdict ON THE PR — a review, a required check,
# a comment — never back into the session that opened it. Without this hook
# that verdict dead-ends: the session moves on unaware the PR is not
# mergeable. This hook makes the session aware, natively, the moment it opens
# a PR: it emits ONE paragraph of additionalContext telling the session to arm
# a single harness Monitor on the PR it just created, watching that PR's
# reviews and comments and waking the session when a verdict or an operator
# comment lands. The notification-spike's minimum: vendor-primitive only — the
# Monitor the harness already uses for CI waits, no listener, no webhook, no
# always-on process.
#
# WHY additionalContext, NOT stdout: for PostToolUse, plain stdout goes to the
# debug log only and the model never sees it (only UserPromptSubmit /
# SessionStart / a couple others treat stdout as context). The one supported
# way to put text in front of the model from a PostToolUse hook is the JSON
# field hookSpecificOutput.additionalContext. That is what this emits.
#
# SUBAGENT BRANCH: a foreground subagent's background tasks are killed when it
# returns its final result, so a Monitor armed from inside one would die
# seconds later. The PostToolUse payload carries `agent_id` ONLY when the hook
# fires inside a subagent (docs: "Present only when the hook fires inside a
# subagent call"). When present, the paragraph instead tells the subagent to
# report the PR URL as the first line of its result, so the PARENT session —
# whose Monitor outlives the turn — arms the watch.
#
# FAIL-OPEN by design: this is a convenience hook, not a guard. Any problem
# (no jq, no PR URL in the output, malformed input) exits 0 silently and emits
# nothing — it must never block a `gh pr create` or spam an unrelated command.
#
# SELF-SCOPE: the settings `"if": "Bash(gh pr create *)"` pre-filter FAILS OPEN
# into running this hook for any command containing $(...), backticks, or $VAR
# (Claude Code cannot statically evaluate those), so this hook decides its own
# scope: it fires only when `gh pr create` appears in command position AND the
# tool output contains a real PR URL. The URL check matters twice — it is the
# PR to watch, and it keeps the hook silent on a `gh pr create --help`, a
# dry run, or a failed create.
#
# Tests: ../tests/pr-verdict-watch-arm.test.sh

set -uo pipefail

# jq is required to parse the payload and to emit well-formed JSON. Missing jq
# is fail-open (this hook never blocks a PR create).
command -v jq >/dev/null 2>&1 || exit 0

INPUT="$(cat 2>/dev/null || true)"
[[ -n "$INPUT" ]] || exit 0

TOOL_NAME="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null || true)"
[[ "$TOOL_NAME" == "Bash" ]] || exit 0

COMMAND="$(printf '%s' "$INPUT" | jq -r '.tool_input.command // empty' 2>/dev/null || true)"
[[ -n "$COMMAND" ]] || exit 0

# ---------------------------------------------------------------------------
# SELF-SCOPE: `gh pr create` in COMMAND POSITION (start, or after a shell
# separator, optionally behind wrapper words and leading env assignments) —
# never a bare substring, so an `echo "gh pr create"` or a doc edit does not
# match. Line continuations are stripped and newlines become separators first,
# the same normalisation gh-pr-body-guard.sh uses.
# ---------------------------------------------------------------------------
_norm="${COMMAND//\\$'\n'/ }"        # line continuations -> single space
_norm="${_norm//$'\n'/ ; }"          # newlines are command separators
_norm="$(tr -s '[:space:]' ' ' <<<"$_norm")"
_norm="${_norm//\"/}"; _norm="${_norm//\'/}"
_RE='(^|[;&|(`])[[:space:]]*((env|time|sudo|nohup|command)[[:space:]]+)*([A-Za-z_][A-Za-z0-9_]*=[^ ]* )*gh[[:space:]]+pr[[:space:]]+create([[:space:]]|$)'
[[ "$_norm" =~ $_RE ]] || exit 0

# ---------------------------------------------------------------------------
# Find the PR URL in the tool output. tool_response may be a string or an
# object ({stdout, stderr, ...}); tojson stringifies either, and gh prints the
# new PR's URL to stdout as the LAST line on success (any notices print above
# it), so the last match is the created PR — a decoy PR URL in an earlier
# notice line does not win. No URL -> fail-open (a --help, a dry run, or a
# failed create).
# ---------------------------------------------------------------------------
RESP="$(printf '%s' "$INPUT" | jq -r '.tool_response // empty | if type=="string" then . else tojson end' 2>/dev/null || true)"
PR_URL="$(printf '%s' "$RESP" | grep -oE 'https://github\.com/[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+/pull/[0-9]+' | tail -1)"
[[ -n "$PR_URL" ]] || exit 0

# owner/repo and number from the URL.
PR_NUM="${PR_URL##*/}"
_rest="${PR_URL#https://github.com/}"        # owner/repo/pull/N
PR_REPO="${_rest%%/pull/*}"                    # owner/repo
[[ "$PR_NUM" =~ ^[0-9]+$ && "$PR_REPO" == */* ]] || exit 0

# agent_id is present ONLY inside a subagent call (Claude Code docs).
AGENT_ID="$(printf '%s' "$INPUT" | jq -r '.agent_id // empty' 2>/dev/null || true)"

# ---------------------------------------------------------------------------
# Build the paragraph.
# ---------------------------------------------------------------------------
if [[ -n "$AGENT_ID" ]]; then
    CTX="You opened PR #${PR_NUM} on ${PR_REPO} (${PR_URL}) from inside a subagent. Do NOT arm a Monitor here: a subagent's background tasks are killed when you return your final result, so the watch would die seconds after arming. Instead, report this PR URL as the FIRST LINE of your result, exactly:
${PR_URL}
The parent session will arm the verdict Monitor on it. (Margot's verdict and the operator's comments land on the PR, not in this session, so the PR is not mergeable until acted on.)"
else
    # The watch command. gh pr view is in the auto-mode allow list (gh api is
    # not); it polls every 45s, seeds existing reviews/comments on the first
    # pass so it never re-announces them, then emits one line per NEW review
    # (any author — Margot's verdict OR the operator's Approve/Request-changes
    # click) and per NEW comment by the operator or Margot, and exits when the
    # PR merges or closes. Process substitution (not a pipe) keeps the seen-set
    # updates in the loop's own shell.
    WATCH_CMD="R='${PR_REPO}'; N=${PR_NUM}; OP='lexijamesesq'; MG='margot-the-meticulous'
SEEN=\"\$(mktemp)\"; trap 'rm -f \"\$SEEN\"' EXIT; first=1
while :; do
  J=\"\$(gh pr view \"\$N\" --repo \"\$R\" --json reviews,comments,state,url 2>/dev/null)\" || { sleep 45; continue; }
  [ -n \"\$J\" ] || { sleep 45; continue; }
  URL=\"\$(printf '%s' \"\$J\" | jq -r '.url')\"; STATE=\"\$(printf '%s' \"\$J\" | jq -r '.state')\"
  while IFS=\"\$(printf '\\t')\" read -r kind id who what; do
    [ -n \"\$id\" ] || continue
    grep -qxF \"\$id\" \"\$SEEN\" 2>/dev/null && continue
    printf '%s\\n' \"\$id\" >> \"\$SEEN\"
    [ \"\$first\" -eq 1 ] && continue
    printf 'PR #%s: new %s by %s (%s) — %s — read it; fix and push, or reply.\\n' \"\$N\" \"\$kind\" \"\$who\" \"\$what\" \"\$URL\"
  done < <(printf '%s' \"\$J\" | jq -r --arg op \"\$OP\" --arg mg \"\$MG\" '( .reviews[]? | select(.state!=\"PENDING\") | \"review\\t\"+.id+\"\\t\"+(.author.login//\"?\")+\"\\t\"+.state ), ( .comments[]? | select((.author.login//\"\")==\$op or (.author.login//\"\")==\$mg or (.author.login//\"\")==(\$mg+\"[bot]\")) | \"comment\\t\"+.id+\"\\t\"+(.author.login//\"?\")+\"\\tcomment\" )')
  first=0
  case \"\$STATE\" in
    MERGED) printf 'PR #%s MERGED — %s — watch done.\\n' \"\$N\" \"\$URL\"; exit 0;;
    CLOSED) printf 'PR #%s CLOSED — %s — watch done.\\n' \"\$N\" \"\$URL\"; exit 0;;
  esac
  sleep 45
done"

    CTX="You just opened PR #${PR_NUM} on ${PR_REPO} (${PR_URL}). Margot (the PR reviewer) and the operator post their verdict ON THE PR — a review, a required check, a comment — not back into this session, so this PR is NOT mergeable until you act on what lands there. Arm ONE persistent Monitor now (persistent: true) with exactly this command, then keep working — do not poll by hand:

${WATCH_CMD}

It emits on any new review (Margot's verdict, or the operator's Approve/Request-changes click, which is her authority) and on any new comment by the operator or Margot, and exits when the PR merges or closes. When it wakes you, open the link, read what landed, and act: fix and push, or reply in the thread."
fi

jq -n --arg ctx "$CTX" \
    '{hookSpecificOutput: {hookEventName: "PostToolUse", additionalContext: $ctx}}'

exit 0
