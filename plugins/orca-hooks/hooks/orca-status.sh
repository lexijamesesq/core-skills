#!/usr/bin/env bash
# Forwards one Claude Code hook event to the script the Orca desktop app
# installs and maintains, so Orca shows exact session status. Outside an Orca
# pane, or when Orca's script is absent, it drains the event and exits.
#
# The caller sets ORCA_HOOK_AGENT_PID to the Claude Code process id; Orca's
# script reads it. Pass "quiet" for events whose hook must print nothing.
set -u

orca_hook="${HOME-}/.orca/agent-hooks/claude-hook.sh"

if [[ -n "${ORCA_PANE_KEY-}${ORCA_AGENT_PANE-}" && -x "$orca_hook" ]]; then
	export ORCA_HOOK_AGENT_PID="${ORCA_HOOK_AGENT_PID-}"
	exec /bin/sh "$orca_hook"
fi

cat >/dev/null 2>&1 || true
[[ "${1-}" == quiet ]] || printf '{}\n'
