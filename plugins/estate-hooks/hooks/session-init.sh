#!/usr/bin/env bash
# session-init.sh
#
# SessionStart hook: bootstraps per-session state.
#   - Ensures ~/.cache/claude/ exists with 0700 permissions
#
# Tolerant: failures here would block all sessions. Stderr-warn but exit 0.

set -uo pipefail

CACHE="${HOME}/.cache/claude"
mkdir -p "$CACHE" 2>/dev/null || {
	echo "session-init: failed to mkdir $CACHE" >&2
	exit 0
}
chmod 700 "$CACHE" 2>/dev/null || true

exit 0
