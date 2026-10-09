#!/usr/bin/env bash
# session-init.sh
#
# SessionStart hook: bootstraps per-session state.
#   - Ensures ~/.cache/claude/ exists with 0700 permissions
#   - Warns if VAULT_ROOT is unset inside what looks like a vault
#   - Prepares native checks in enrolled estate checkouts (HA stays excluded)
#
# Tolerant: failures here would block all sessions. Stderr-warn but exit 0.

set -uo pipefail

CACHE="${HOME}/.cache/claude"
mkdir -p "$CACHE" 2>/dev/null || {
	echo "session-init: failed to mkdir $CACHE" >&2
	exit 0
}
chmod 700 "$CACHE" 2>/dev/null || true

# Read hook input from stdin
INPUT=$(cat 2>/dev/null || true)
SESSION_CWD=""
if command -v jq >/dev/null 2>&1 && [[ -n "$INPUT" ]]; then
	SESSION_CWD=$(jq -r '.cwd // empty' <<<"$INPUT" 2>/dev/null || true)
fi

# Warn if VAULT_ROOT is unset but we appear to be inside a vault.
# Two hooks (vault-mcp-redirect, fix-obsidian-claude-sync) silently
# disable when VAULT_ROOT is missing — this is the only signal.
if [[ -z "${VAULT_ROOT:-}" && -n "$SESSION_CWD" ]]; then
	d="$SESSION_CWD"
	while [[ "$d" != "/" && "$d" != "." ]]; do
		if [[ -d "$d/.obsidian" ]]; then
			echo "session-init: WARNING — cwd is inside a vault ($d) but VAULT_ROOT is not set." >&2
			echo "  vault-mcp-redirect and fix-obsidian-claude-sync are INACTIVE this session." >&2
			echo "  Set VAULT_ROOT in settings.json env block to enable them." >&2
			break
		fi
		d="$(dirname "$d")"
	done
fi

# Run the shared local readiness helper before authoring. Scope by the current
# checkout's remote, not the plugin cache; unrelated projects have their own setup.
if [[ -n "$SESSION_CWD" ]] && command -v git >/dev/null 2>&1; then
	checkout=$(git -C "$SESSION_CWD" rev-parse --show-toplevel 2>/dev/null || true)
	remote=$(git -C "$SESSION_CWD" remote get-url origin 2>/dev/null || true)
	remote=${remote%/}
	case "$remote" in
	https://github.com/lexijamesesq/home-assistant | https://github.com/lexijamesesq/home-assistant.git | git@github.com:lexijamesesq/home-assistant | git@github.com:lexijamesesq/home-assistant.git) ;;
	https://github.com/lexijamesesq/* | git@github.com:lexijamesesq/*)
		helper="${DOTTY_CHECKOUT:-$HOME/bin/dotty}/scripts/prepare-checkout.sh"
		if [[ ! -x "$helper" ]] || ! bash "$helper" "$checkout" >&2; then
			jq -n --arg helper "$helper" '{hookSpecificOutput: {
					hookEventName: "SessionStart", additionalContext:
					("Checkout readiness is incomplete. Run " + $helper + " for this checkout and resolve its failure before authoring. Do not bypass hooks; use root AGENTS.md for the common contract.")}}'
		fi
		;;
	esac
fi

exit 0
