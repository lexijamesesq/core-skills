#!/usr/bin/env bash
# git-push-publish-guard.sh
#
# PreToolUse hook (matcher: Bash): denies a bare `git push` of a session's
# own local commits. Under the App identity, publishing goes through the
# helper (GraphQL createCommitOnBranch, scanned before it ever calls the
# API) so the commit is created directly on GitHub as Verified with the
# operator as co-author — a local `git commit` + `git push` bypasses that
# scan entirely and would push under whatever identity git's HTTPS
# credential helper resolves (the App's own containment then applies to
# writes it makes no distinction for: a session's own local commit history
# was never scanned by the publish helper's chain).
#
# Packaged in this plugin, registered in hooks.json's PreToolUse array
# alongside git-hook-bypass-guard.sh and the other estate guards — not a
# settings.json entry: the settings-slice fail-closed precondition stays
# unchanged, guard hooks come from this plugin rather than a profile's
# settings.json, and settings.json's own `hooks` key stays `{}`. Matches
# the shape of git-hook-bypass-guard.sh
# (same fail-open posture, same tool-scoped Bash-porous honesty note) — see
# that file's own header for the full disclosure this one inherits rather
# than repeats.
#
# Scope: session-invoked Bash only. Does not reach the Home Assistant Pi's
# own pushes (those run over SSH on the Pi's own shell, never through this
# session's tool calls) or a session's `gh pr merge` (merging an
# already-open, already-scanned PR is not the same act as pushing an
# unscanned local commit).
#
# Fail-open on infra errors, same reasoning as git-hook-bypass-guard.sh:
# a broken hook degrades to no opinion, never bricks the session's Bash
# tool entirely.
#
# Accepted over-blocks (safe direction, same acceptance as
# git-hook-bypass-guard.sh's own): matching "git" and "push" as separate
# words anywhere in the command (not requiring adjacency, so `git -C <path>
# push` is still caught) means a command containing both words for unrelated
# reasons is also denied — e.g. `git log && push origin main` where "push"
# names some other command entirely, or a commit message that itself
# mentions "git push" (git commit -m "explain how git push works here").
# (Note: a "push" substring with no word boundary around it, e.g.
# `push_to_queue`, does NOT match — the word-boundary regex requires "push"
# to end at a boundary character or end-of-string, so that case is NOT
# blocked; only a standalone "push" token is.) A string-match guard cannot
# tell a real invocation from an incidental co-occurrence; we accept the
# false deny (a retype, with a clear reason printed) rather than build a
# shell parser to distinguish them — the alternative (adjacency-only
# matching) has a real false-negative gap instead: `git -C <path> push`
# slips through unblocked.
#
# Effective date: plugin update + session restart or reload, same as any
# other estate-hooks change — a running session keeps whatever hooks.json
# it loaded at start.

set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat 2>/dev/null)
[[ -z "$INPUT" ]] && exit 0

TOOL_NAME=$(jq -r '.tool_name // empty' <<<"$INPUT" 2>/dev/null)
[[ "$TOOL_NAME" == "Bash" ]] || exit 0

CMD=$(jq -r '.tool_input.command // empty' <<<"$INPUT" 2>/dev/null)
[[ -z "$CMD" ]] && exit 0

CMD_NORM=$(tr -s '[:space:]' ' ' <<<"$CMD")
LOWER_NORM=$(tr '[:upper:]' '[:lower:]' <<<"$CMD_NORM")

deny() {
    {
        echo "git-push-publish-guard: blocked — a session's own commits publish through"
        echo "the App's publish helper (scans, then creates a Verified commit via the"
        echo "GitHub API), never a bare git push. This is not a bypass to route around —"
        echo "ask the operator if the helper genuinely cannot do what you need."
    } >&2
    exit 2
}

BND="[[:space:];&|\"']"

# Match "git" and "push" as separate words anywhere in the command, not
# requiring adjacency — git accepts flags between the verb and the
# subcommand (git -C <path> push, git --git-dir=x push), and adjacency-only
# matching lets exactly that ordinary pattern slip through unblocked.
RE_GIT_WORD="(^|$BND)git($|$BND)"
RE_PUSH_WORD="(^|$BND)push($|$BND)"
if [[ "$LOWER_NORM" =~ $RE_GIT_WORD && "$LOWER_NORM" =~ $RE_PUSH_WORD ]]; then
    deny "git push (including git -C <path> push and similar flagged forms)"
fi

exit 0
