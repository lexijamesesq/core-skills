#!/usr/bin/env bash
# probe.sh — SessionStart probe for the plugin spike.
# Appends one record to ~/.cache/claude/spike-probe.log:
#   the registration path (settings vs plugin, inferred from $0), $CLAUDE_PLUGIN_ROOT,
#   the sorted names of every CLAUDE_* / VAULT_* env var, and the stdin JSON.
# Warn-only, always exit 0.
set -uo pipefail
LOG="${HOME}/.cache/claude/spike-probe.log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || exit 0
INPUT=$(cat 2>/dev/null || true)
{
  printf '=== %s pid=%s\n' "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$$"
  printf 'self=%s\n' "${BASH_SOURCE[0]}"
  printf 'CLAUDE_PLUGIN_ROOT=%s\n' "${CLAUDE_PLUGIN_ROOT:-<unset>}"
  printf 'CLAUDE_PLUGIN_DATA=%s\n' "${CLAUDE_PLUGIN_DATA:-<unset>}"
  printf 'CLAUDE_PROJECT_DIR=%s\n' "${CLAUDE_PROJECT_DIR:-<unset>}"
  printf 'env_names=%s\n' "$(env | grep -E '^(CLAUDE|VAULT|GIT_SSH|LINEAR)' | cut -d= -f1 | sort | tr '\n' ' ')"
  printf 'stdin=%s\n' "$INPUT"
} >> "$LOG"
exit 0
