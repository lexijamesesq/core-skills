#!/usr/bin/env bash
# estate-identity-guard.sh
#
# PreToolUse (matcher: Bash) enforcement of two push protections for Claude
# sessions. It does not look at which GitHub identity or credential path a
# session uses: no environment variable, token, gitconfig content or PATH
# entry decides whether a git or gh command runs.
#
# 1. NOT ENROLLED -> `git push` is refused for every Claude profile. Enrollment
#    is a disk fact: the agents' gitconfig is installed
#    (~/.config/claude-operator/operator-mode.gitconfig). Reads and
#    enrollment/bootstrap commands stay available.
# 2. A personal-profile `git push` requires the native pre-push scanner
#    (an executable pre-commit shim at Git's effective hook path) in the
#    current repo, so "the push was scanned" is a real invariant. Professional
#    sessions are owner-routed and are not scanner-checked here.
#
# Scope: only bare `git` / `gh` words match; absolute-path invocations and a
# plain shell are not seen (defense-in-depth, not a boundary).
# Fail-open on infra errors (no jq, unreadable input, non-Bash tool, a push
# from a directory outside any Git work tree).

set -uo pipefail

INPUT=$(cat 2>/dev/null)
[[ -z "$INPUT" ]] && exit 0
TOOL=$(jq -r '.tool_name // empty' <<<"$INPUT" 2>/dev/null)
[[ "$TOOL" == "Bash" ]] || exit 0
CMD=$(jq -r '.tool_input.command // empty' <<<"$INPUT" 2>/dev/null)
[[ -z "$CMD" ]] && exit 0

[[ "${CLAUDECODE:-}" == "1" ]] || exit 0

LOWER=$(tr '[:upper:]' '[:lower:]' <<<"$CMD")
BND="[[:space:];&|\"'()]"
uses_git=0
uses_gh=0
[[ "$LOWER" =~ (^|$BND)git($|$BND) ]] && uses_git=1
[[ "$LOWER" =~ (^|$BND)gh($|$BND) ]] && uses_gh=1
[[ "$uses_git" == 1 || "$uses_gh" == 1 ]] || exit 0

# The gitconfig whose presence on disk marks a machine as enrolled.
OPERATOR_GITCONFIG="$HOME/.config/claude-operator/operator-mode.gitconfig"

# Pre-enrollment push protection covers every Claude profile; reads and setup
# remain available. Human sessions returned above.
if [[ ! -f "$OPERATOR_GITCONFIG" ]]; then
	if [[ "$uses_git" == 1 && "$LOWER" =~ (^|$BND)push($|$BND) ]]; then
		echo "estate-identity-guard: BLOCKED — enroll this machine in estate identity and prepare the checkout before git push; ordinary native pushes are supported after setup." >&2
		exit 2
	fi
	exit 0
fi

# Enrolled professional sessions retain their existing owner routing.
[[ "$(basename "${CLAUDE_CONFIG_DIR:-}")" == ".claude-personal" ]] || exit 0

push_fail() {
	{
		echo "estate-identity-guard: BLOCKED — $1"
	} >&2
	exit 2
}

# A `git push` additionally requires the native pre-push scanner installed in
# the current repo (the pre-commit shim at Git's effective hook path).
# Clones and linked worktrees must resolve the same installed hook owner;
# refusing here makes "the push was scanned" a real invariant.
if [[ "$uses_git" == 1 && "$LOWER" =~ (^|$BND)push($|$BND) ]]; then
	checkout=$(jq -r '.cwd // "."' <<<"$INPUT")
	toplevel=$(git -C "$checkout" rev-parse --show-toplevel 2>/dev/null || true)
	if [[ -n "$toplevel" ]]; then
		hook=$(git -C "$toplevel" rev-parse --path-format=absolute --git-path hooks/pre-push)
		[[ -x "$hook" ]] ||
			push_fail "the pre-push scanner hook is not installed in $toplevel ($hook absent or not executable) — install it with pre-commit install --hook-type pre-push. A push must be scanned before it uploads."
		grep -q "pre-commit" "$hook" 2>/dev/null ||
			push_fail "the pre-push hook in $toplevel is not the pre-commit scanner shim (no pre-commit marker)"
	fi
fi

exit 0
