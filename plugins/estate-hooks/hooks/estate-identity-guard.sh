#!/usr/bin/env bash
# estate-identity-guard.sh
#
# PreToolUse (matcher: Bash) ENFORCEMENT for estate mode. A personal-profile
# ("estate") Claude session must write to GitHub only as the App, through a
# correctly-delivered baseline (the credential helper, the profile-aware gh
# adapter on PATH, the bot GIT_AUTHOR/COMMITTER, the isolated GH_CONFIG_DIR).
# The identity ticket's own acceptance names an "automatic guard that refuses
# any git or gh write on an inconsistent baseline": a SessionStart hook CANNOT
# refuse (it is non-blocking), so the refusal lives HERE, at PreToolUse, where
# exit 2 actually blocks the tool.
#
# This exists because the delivery mechanism is undocumented and empirical:
# settings env overriding the shell, CLAUDE_ENV_FILE prepending the adapter
# dir, GIT_CONFIG_GLOBAL selecting the estate gitconfig. If any of that failed
# to apply (a stale profile, a settings miss, a bad relaunch), a `git push` or
# `gh` write would silently authenticate/attribute as HER instead of the App
# -- the exact silent hole this guard turns into a loud, blocking refusal.
#
# Scope: personal-profile sessions only. A professional session is owner-routed
# by the adapter and the ~/.gitconfig includeIf (not a single estate baseline),
# and her own terminal is her own -- this guard has no opinion on either.
#
# Fail-open on infra errors (no jq, unreadable input, non-Bash tool): a broken
# guard degrades to no opinion, never bricks the Bash tool. It is defense that
# makes the delivered baseline observable-and-enforced, not a sandbox.

set -uo pipefail

command -v jq >/dev/null 2>&1 || exit 0

INPUT=$(cat 2>/dev/null)
[[ -z "$INPUT" ]] && exit 0
TOOL=$(jq -r '.tool_name // empty' <<<"$INPUT" 2>/dev/null)
[[ "$TOOL" == "Bash" ]] || exit 0
CMD=$(jq -r '.tool_input.command // empty' <<<"$INPUT" 2>/dev/null)
[[ -z "$CMD" ]] && exit 0

# Estate sessions only: dual key (CLAUDECODE=1 AND the personal profile) so a
# stray terminal `export CLAUDE_CONFIG_DIR=.claude-personal` cannot summon the
# guard where it does not belong.
[[ "${CLAUDECODE:-}" == "1" ]] || exit 0
[[ "$(basename "${CLAUDE_CONFIG_DIR:-}")" == ".claude-personal" ]] || exit 0

# Only gate commands that actually invoke git or gh (as standalone words).
LOWER=$(tr '[:upper:]' '[:lower:]' <<<"$CMD")
BND="[[:space:];&|\"'()]"
uses_git=0; uses_gh=0
[[ "$LOWER" =~ (^|$BND)git($|$BND) ]] && uses_git=1
[[ "$LOWER" =~ (^|$BND)gh($|$BND) ]] && uses_gh=1
[[ "$uses_git" == 1 || "$uses_gh" == 1 ]] || exit 0

# --- the expected estate baseline (fixed contract with the estate-identity
# blueprint slice + the settings env; $HOME-relative, resolved live) ---
EXPECT_GITCONFIG="$HOME/.config/claude-estate/estate-mode.gitconfig"
EXPECT_GH_CONFIG="$HOME/.config/claude-estate/gh-config"
EXPECT_GH_ADAPTER="$HOME/.config/op-agent/bin/gh"
EXPECT_CRED_HELPER="$HOME/.config/op-agent/bin/git-credential-estate"
BOT_EMAIL="325510841+claude-the-enduring[bot]@users.noreply.github.com"

fail() {
  {
    echo "estate-identity-guard: BLOCKED — the estate identity baseline is inconsistent,"
    echo "so this git/gh command could authenticate or attribute as the wrong identity."
    echo "  reason: $1"
    echo "This session is not correctly in estate mode. Relaunch after 'system-blueprint"
    echo "apply', or ask the operator — this is not a check to route around."
  } >&2
  exit 2
}

[[ "${GIT_CONFIG_GLOBAL:-}" == "$EXPECT_GITCONFIG" ]] \
  || fail "GIT_CONFIG_GLOBAL is '${GIT_CONFIG_GLOBAL:-<unset>}', expected $EXPECT_GITCONFIG"
[[ "${GH_CONFIG_DIR:-}" == "$EXPECT_GH_CONFIG" ]] \
  || fail "GH_CONFIG_DIR is '${GH_CONFIG_DIR:-<unset>}', expected $EXPECT_GH_CONFIG"
[[ -z "${SSH_AUTH_SOCK:-}" ]] \
  || fail "SSH_AUTH_SOCK is set ('${SSH_AUTH_SOCK}') — an SSH agent leaked into estate mode"
[[ "${GIT_AUTHOR_EMAIL:-}" == "$BOT_EMAIL" ]] \
  || fail "GIT_AUTHOR_EMAIL is '${GIT_AUTHOR_EMAIL:-<unset>}', expected the App bot"
[[ "${GIT_COMMITTER_EMAIL:-}" == "$BOT_EMAIL" ]] \
  || fail "GIT_COMMITTER_EMAIL is '${GIT_COMMITTER_EMAIL:-<unset>}', expected the App bot"

# bare `gh` must resolve to the estate adapter (through the one-binary dir the
# CLAUDE_ENV_FILE prepends), never the real gh on the base PATH.
gh_path=$(command -v gh 2>/dev/null || true)
gh_resolved="$gh_path"
[[ -L "$gh_path" ]] && gh_resolved=$(readlink "$gh_path")
[[ "$gh_resolved" == "$EXPECT_GH_ADAPTER" ]] \
  || fail "bare 'gh' resolves to '${gh_path:-<none>}' (-> '${gh_resolved:-<none>}'), not the estate adapter $EXPECT_GH_ADAPTER"

# ssh (and by the same dir, scp/op-sa) must NOT be shadowed by the estate PATH.
ssh_path=$(command -v ssh 2>/dev/null || true)
[[ "$ssh_path" == "/usr/bin/ssh" ]] \
  || fail "'ssh' resolves to '${ssh_path:-<none>}', not /usr/bin/ssh — the estate PATH is over-shadowing binaries it must not"

[[ -x "$EXPECT_CRED_HELPER" ]] \
  || fail "the estate credential helper $EXPECT_CRED_HELPER is missing or not executable"

# A `git push` additionally requires the native pre-push scanner installed in
# the current repo (the pre-commit shim at .git/hooks/pre-push). No global
# templatedir/hooksPath exists, so a fresh clone has none until installed;
# refusing here makes "the push was scanned" a real invariant, not a hope.
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
