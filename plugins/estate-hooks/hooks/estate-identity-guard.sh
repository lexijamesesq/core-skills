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
# ENROLLMENT IS A DISK FACT, NOT AN ENV FACT. The estate-identity blueprint
# slice installs the estate gitconfig at a fixed path; until it does, this
# machine is NOT enrolled and this guard has NO opinion. That ordering is what
# makes it safe to ship this plugin BEFORE the operator enrolls (applies the
# slice + settings and relaunches): an unenrolled personal session is not
# blocked. Once the file is present, the estate baseline MUST be consistent --
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
# Scope: personal-profile sessions only (professional is owner-routed by the
# adapter and the ~/.gitconfig includeIf; her terminal is her own).
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
[[ "$(basename "${CLAUDE_CONFIG_DIR:-}")" == ".claude-personal" ]] || exit 0

LOWER=$(tr '[:upper:]' '[:lower:]' <<<"$CMD")
BND="[[:space:];&|\"'()]"
uses_git=0; uses_gh=0
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

# Enrollment gate: not enrolled -> no opinion (so shipping this before
# enrollment cannot brick a session).
[[ -f "$EXPECT_GITCONFIG" ]] || exit 0

fail() {
  {
    echo "estate-identity-guard: BLOCKED — this machine is enrolled in estate identity"
    echo "mode but the session's baseline is inconsistent, so this git/gh command could"
    echo "authenticate or attribute as the wrong identity."
    echo "  reason: $1"
    echo "This is the bad-relaunch case (the estate files are installed but the session"
    echo "env is wrong). Relaunch the session, or ask the operator — do not route around it."
  } >&2
  exit 2
}

[[ "${GIT_CONFIG_GLOBAL:-}" == "$EXPECT_GITCONFIG" ]] \
  || fail "GIT_CONFIG_GLOBAL is '${GIT_CONFIG_GLOBAL:-<unset>}', expected $EXPECT_GITCONFIG"
[[ "${GH_CONFIG_DIR:-}" == "$EXPECT_GH_CONFIG" ]] \
  || fail "GH_CONFIG_DIR is '${GH_CONFIG_DIR:-<unset>}', expected $EXPECT_GH_CONFIG"
{ [[ "${CLAUDE_ENV_FILE:-}" == "$EXPECT_ENV_FILE" ]] && [[ -f "$EXPECT_ENV_FILE" ]]; } \
  || fail "CLAUDE_ENV_FILE is '${CLAUDE_ENV_FILE:-<unset>}' or its file is missing; expected $EXPECT_ENV_FILE"
[[ -z "${SSH_AUTH_SOCK:-}" ]] \
  || fail "SSH_AUTH_SOCK is set ('${SSH_AUTH_SOCK}') — an SSH agent leaked into estate mode"
[[ "${GIT_AUTHOR_EMAIL:-}" == "$BOT_EMAIL" ]] \
  || fail "GIT_AUTHOR_EMAIL is '${GIT_AUTHOR_EMAIL:-<unset>}', expected the App bot"
[[ "${GIT_COMMITTER_EMAIL:-}" == "$BOT_EMAIL" ]] \
  || fail "GIT_COMMITTER_EMAIL is '${GIT_COMMITTER_EMAIL:-<unset>}', expected the App bot"

# The estate PATH dir must hold EXACTLY the gh adapter symlink -- deterministic,
# independent of this hook process's own PATH. (This is the mechanism the
# CLAUDE_ENV_FILE prepend puts first for the session's Bash subprocesses.)
# Enumerated by glob, not `ls` (SC2012), and bash-3.2-safe on empty.
shopt -s nullglob dotglob
_entries=( "$ESTATE_BIN"/* )
shopt -u nullglob dotglob
entries=""
if [[ ${#_entries[@]} -gt 0 ]]; then
  for _e in "${_entries[@]}"; do entries+="${entries:+ }$(basename "$_e")"; done
fi
{ [[ ${#_entries[@]} -eq 1 ]] && [[ "$entries" == "gh" ]]; } \
  || fail "the estate PATH dir $ESTATE_BIN must contain exactly 'gh', found: '${entries:-<empty/absent>}'"
{ [[ -L "$ESTATE_BIN/gh" ]] && [[ "$(readlink "$ESTATE_BIN/gh")" == "$EXPECT_ADAPTER" ]]; } \
  || fail "$ESTATE_BIN/gh is not a symlink to the adapter $EXPECT_ADAPTER"

[[ -x "$EXPECT_CRED_HELPER" ]] \
  || fail "the estate credential helper $EXPECT_CRED_HELPER is missing or not executable"

# A `git push` additionally requires the native pre-push scanner installed in
# the current repo (the pre-commit shim at .git/hooks/pre-push). No global
# templatedir/hooksPath exists, so a fresh clone has none until installed;
# refusing here makes "the push was scanned" a real invariant.
if [[ "$uses_git" == 1 && "$LOWER" =~ (^|$BND)push($|$BND) ]]; then
  toplevel=$(git rev-parse --show-toplevel 2>/dev/null || true)
  if [[ -n "$toplevel" ]]; then
    hook="$toplevel/.git/hooks/pre-push"
    [[ -f "$hook" ]] \
      || fail "the pre-push scanner hook is not installed in $toplevel (.git/hooks/pre-push absent) — run 'pre-commit install --install-hooks'. A push must be scanned before it uploads."
    grep -q "pre-commit" "$hook" 2>/dev/null \
      || fail "the pre-push hook in $toplevel is not the pre-commit scanner shim (no pre-commit marker)"
  fi
fi

exit 0
