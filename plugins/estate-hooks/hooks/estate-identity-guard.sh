#!/usr/bin/env bash
# estate-identity-guard.sh
#
# PreToolUse (matcher: Bash) ENFORCEMENT for estate mode. A personal-profile
# ("estate") Claude session must write to GitHub only as the App, through a
# correctly-delivered baseline (the estate gitconfig, the CLAUDE_ENV_FILE that
# prepends the gh adapter, the bot GIT_AUTHOR/COMMITTER, the isolated
# GH_CONFIG_DIR). The identity ticket names "an automatic guard that refuses
# any git or gh write on an inconsistent baseline": a SessionStart hook CANNOT
# refuse (it is non-blocking), so the refusal lives HERE, where exit 2 blocks
# the tool.
#
# TWO BASELINES ARE ACCEPTED during the transition, and a session passes if it
# satisfies EITHER one completely (never a mix of the two):
#   - the App baseline: bot identity, the estate gitconfig, the gh adapter.
#   - the operator baseline: the operator's own identity (a fine-grained PAT
#     read through op-connect), the operator gitconfig, no adapter.
#
# ENROLLMENT IS A DISK FACT, NOT AN ENV FACT. A blueprint slice installs a
# baseline gitconfig at a fixed path; until one of the two exists, this
# machine is NOT enrolled. Reads and enrollment/bootstrap commands remain
# available, but git push from any Claude profile requires enrollment. This
# retains the former publishing guard's pre-enrollment scope without requiring
# its retired publishing helper. Once enrolled, only personal sessions require
# the estate baseline to be consistent --
# the file present with the env missing is exactly the bad-relaunch case to
# block, not to wave through.
#
# The checks are DETERMINISTIC disk/env facts, deliberately not "command -v"
# probes: whether a PreToolUse hook process inherits the CLAUDE_ENV_FILE PATH
# prepend is unproven, and an ssh-path check would encode a machine fact (a
# Homebrew openssh). Instead: CLAUDE_ENV_FILE equals the declared path and the
# file exists; the estate PATH dir holds exactly one entry, `gh`, a symlink to
# the adapter. Those are true iff the wiring was actually delivered.
#
# Scope: pre-enrollment push refusal covers all Claude profiles. Enrolled
# identity enforcement is personal-only; professional remains owner-routed by
# the adapter and ~/.gitconfig includeIf. Her terminal is her own.
# Fail-open on infra errors (no jq, unreadable input, non-Bash tool).

set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

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

# --- the estate baseline (fixed contract with the estate-identity slice) ---
ESTATE_DIR="$HOME/.config/claude-estate"
EXPECT_GITCONFIG="$ESTATE_DIR/estate-mode.gitconfig"
EXPECT_ENV_FILE="$ESTATE_DIR/estate-env.sh"
EXPECT_GH_CONFIG="$ESTATE_DIR/gh-config"
ESTATE_BIN="$ESTATE_DIR/bin"
EXPECT_ADAPTER="$HOME/.config/op-agent/bin/gh"
EXPECT_CRED_HELPER="$HOME/.config/op-agent/bin/git-credential-estate"
BOT_EMAIL="325510841+claude-the-enduring[bot]@users.noreply.github.com"

# The operator baseline. A separate directory from claude-estate on purpose:
# retiring the App baseline must not take this one with it.
OPERATOR_DIR="$HOME/.config/claude-operator"
OPERATOR_GITCONFIG="$OPERATOR_DIR/operator-mode.gitconfig"
OPERATOR_ENV_FILE="$OPERATOR_DIR/operator-env.sh"
OPERATOR_GH_CONFIG="$OPERATOR_DIR/gh-config"
OPERATOR_EMAIL="938162+lexijamesesq@users.noreply.github.com"

# Preserve the former guard's pre-enrollment push protection across Claude
# profiles; reads and setup remain available. Human sessions returned above.
# Enrolled means EITHER baseline's gitconfig is installed, so retiring one
# baseline's file never drops personal sessions into the block-all-push branch.
if [[ ! -f "$EXPECT_GITCONFIG" && ! -f "$OPERATOR_GITCONFIG" ]]; then
	if [[ "$uses_git" == 1 && "$LOWER" =~ (^|$BND)push($|$BND) ]]; then
		echo "estate-identity-guard: BLOCKED — enroll this machine in estate identity and prepare the checkout before git push; ordinary native pushes are supported after setup." >&2
		exit 2
	fi
	exit 0
fi

# Enrolled professional sessions retain their existing owner routing.
[[ "$(basename "${CLAUDE_CONFIG_DIR:-}")" == ".claude-personal" ]] || exit 0

# Both baselines: these env vars override identity or credentials whatever the
# gitconfig says, so a session carrying either is on neither baseline.
no_credential_overrides() {
	[[ -z "${GIT_CONFIG_COUNT:-}" ]] ||
		{
			REASON="GIT_CONFIG_COUNT is set — env-injected git config overrides the baseline's identity and credentials"
			return 1
		}
	[[ -z "${GIT_ASKPASS:-}" ]] ||
		{
			REASON="GIT_ASKPASS is set — an askpass program overrides the baseline's credential helper"
			return 1
		}
	return 0
}

# Each baseline check sets REASON to the first thing wrong and returns 1, or
# returns 0 when the baseline is fully delivered. A session must satisfy one
# baseline entirely; a mix (say the operator gitconfig with the bot identity)
# satisfies neither and is blocked.
check_app_baseline() {
	{ [[ "${GIT_CONFIG_GLOBAL:-}" == "$EXPECT_GITCONFIG" ]] && [[ -f "$EXPECT_GITCONFIG" ]]; } ||
		{
			REASON="GIT_CONFIG_GLOBAL is '${GIT_CONFIG_GLOBAL:-<unset>}' or its file is missing; expected $EXPECT_GITCONFIG"
			return 1
		}
	[[ "${GH_CONFIG_DIR:-}" == "$EXPECT_GH_CONFIG" ]] ||
		{
			REASON="GH_CONFIG_DIR is '${GH_CONFIG_DIR:-<unset>}', expected $EXPECT_GH_CONFIG"
			return 1
		}
	{ [[ "${CLAUDE_ENV_FILE:-}" == "$EXPECT_ENV_FILE" ]] && [[ -f "$EXPECT_ENV_FILE" ]]; } ||
		{
			REASON="CLAUDE_ENV_FILE is '${CLAUDE_ENV_FILE:-<unset>}' or its file is missing; expected $EXPECT_ENV_FILE"
			return 1
		}
	[[ -z "${SSH_AUTH_SOCK:-}" ]] ||
		{
			REASON="SSH_AUTH_SOCK is set ('${SSH_AUTH_SOCK}') — an SSH agent leaked into estate mode"
			return 1
		}
	# The App baseline authenticates through the estate credential helper, never
	# an ambient token: both must be empty, so an injected token cannot win.
	[[ -z "${GH_TOKEN:-}" ]] ||
		{
			REASON="GH_TOKEN is set — the App baseline authenticates through the estate helper, not an ambient token"
			return 1
		}
	[[ -z "${GITHUB_TOKEN:-}" ]] ||
		{
			REASON="GITHUB_TOKEN is set — the App baseline authenticates through the estate helper, not an ambient token"
			return 1
		}
	no_credential_overrides || return 1
	[[ "${GIT_AUTHOR_EMAIL:-}" == "$BOT_EMAIL" ]] ||
		{
			REASON="GIT_AUTHOR_EMAIL is '${GIT_AUTHOR_EMAIL:-<unset>}', expected the App bot"
			return 1
		}
	[[ "${GIT_COMMITTER_EMAIL:-}" == "$BOT_EMAIL" ]] ||
		{
			REASON="GIT_COMMITTER_EMAIL is '${GIT_COMMITTER_EMAIL:-<unset>}', expected the App bot"
			return 1
		}

	# The estate PATH dir must hold EXACTLY the gh adapter symlink -- deterministic,
	# independent of this hook process's own PATH. (This is the mechanism the
	# CLAUDE_ENV_FILE prepend puts first for the session's Bash subprocesses.)
	# Enumerated by glob, not `ls` (SC2012), and bash-3.2-safe on empty.
	local _shopt_nullglob _shopt_dotglob
	_shopt_nullglob=$(shopt -p nullglob)
	_shopt_dotglob=$(shopt -p dotglob)
	shopt -s nullglob dotglob
	local _entries=("$ESTATE_BIN"/*)
	eval "$_shopt_nullglob"
	eval "$_shopt_dotglob"
	local entries="" _e
	if [[ ${#_entries[@]} -gt 0 ]]; then
		for _e in "${_entries[@]}"; do entries+="${entries:+ }$(basename "$_e")"; done
	fi
	{ [[ ${#_entries[@]} -eq 1 ]] && [[ "$entries" == "gh" ]]; } ||
		{
			REASON="the estate PATH dir $ESTATE_BIN must contain exactly 'gh', found: '${entries:-<empty/absent>}'"
			return 1
		}
	{ [[ -L "$ESTATE_BIN/gh" ]] && [[ "$(readlink "$ESTATE_BIN/gh")" == "$EXPECT_ADAPTER" ]]; } ||
		{
			REASON="$ESTATE_BIN/gh is not a symlink to the adapter $EXPECT_ADAPTER"
			return 1
		}

	[[ -x "$EXPECT_CRED_HELPER" ]] ||
		{
			REASON="the estate credential helper $EXPECT_CRED_HELPER is missing or not executable"
			return 1
		}
	return 0
}

# The operator baseline drops the App/broker-specific checks (the single-gh PATH
# dir and the estate credential helper): the operator's PAT is read by the
# gitconfig's own helper, and no adapter is prepended to PATH.
check_operator_baseline() {
	{ [[ "${GIT_CONFIG_GLOBAL:-}" == "$OPERATOR_GITCONFIG" ]] && [[ -f "$OPERATOR_GITCONFIG" ]]; } ||
		{
			REASON="GIT_CONFIG_GLOBAL is '${GIT_CONFIG_GLOBAL:-<unset>}' or its file is missing; expected $OPERATOR_GITCONFIG"
			return 1
		}
	[[ "${GH_CONFIG_DIR:-}" == "$OPERATOR_GH_CONFIG" ]] ||
		{
			REASON="GH_CONFIG_DIR is '${GH_CONFIG_DIR:-<unset>}', expected $OPERATOR_GH_CONFIG"
			return 1
		}
	{ [[ "${CLAUDE_ENV_FILE:-}" == "$OPERATOR_ENV_FILE" ]] && [[ -f "$OPERATOR_ENV_FILE" ]]; } ||
		{
			REASON="CLAUDE_ENV_FILE is '${CLAUDE_ENV_FILE:-<unset>}' or its file is missing; expected $OPERATOR_ENV_FILE"
			return 1
		}
	[[ -z "${SSH_AUTH_SOCK:-}" ]] ||
		{
			REASON="SSH_AUTH_SOCK is set ('${SSH_AUTH_SOCK}') — an SSH agent leaked into the session"
			return 1
		}
	# The operator baseline authenticates gh with the PAT that operator-env.sh puts
	# in GH_TOKEN; without it gh would fall through to whatever else is available.
	[[ -n "${GH_TOKEN:-}" ]] ||
		{
			REASON="GH_TOKEN is empty — the operator baseline needs the PAT from operator-env.sh"
			return 1
		}
	no_credential_overrides || return 1
	[[ "${GIT_AUTHOR_EMAIL:-}" == "$OPERATOR_EMAIL" ]] ||
		{
			REASON="GIT_AUTHOR_EMAIL is '${GIT_AUTHOR_EMAIL:-<unset>}', expected the operator"
			return 1
		}
	[[ "${GIT_COMMITTER_EMAIL:-}" == "$OPERATOR_EMAIL" ]] ||
		{
			REASON="GIT_COMMITTER_EMAIL is '${GIT_COMMITTER_EMAIL:-<unset>}', expected the operator"
			return 1
		}
	# Delivered, not just present: a zero-byte stub must not pass. Non-empty plus
	# one key marker is enough -- the gitconfig carries a credential helper with a
	# value (the bare `helper =` reset line does not count), the env file has
	# content, and the gh config dir is a directory.
	grep -Eq '^[[:space:]]*helper[[:space:]]*=[[:space:]]*[^[:space:]]' "$OPERATOR_GITCONFIG" 2>/dev/null ||
		{
			REASON="$OPERATOR_GITCONFIG is empty or has no credential helper line"
			return 1
		}
	[[ -s "$OPERATOR_ENV_FILE" ]] ||
		{
			REASON="$OPERATOR_ENV_FILE is empty"
			return 1
		}
	[[ -d "$OPERATOR_GH_CONFIG" ]] ||
		{
			REASON="$OPERATOR_GH_CONFIG is not a directory"
			return 1
		}
	return 0
}

fail() {
	{
		echo "estate-identity-guard: BLOCKED — this machine is enrolled in a GitHub identity"
		echo "baseline but the session matches neither, so this git/gh command could"
		echo "authenticate or attribute as the wrong identity."
		echo "  App baseline:      $1"
		echo "  operator baseline: $2"
		echo "This is the bad-relaunch case (the baseline files are installed but the session"
		echo "env is wrong). Relaunch the session, or ask the operator — do not route around it."
	} >&2
	exit 2
}

if ! check_app_baseline; then
	app_reason="$REASON"
	check_operator_baseline || fail "$app_reason" "$REASON"
fi

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
