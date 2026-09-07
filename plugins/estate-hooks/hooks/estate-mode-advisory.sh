#!/usr/bin/env bash
# estate-mode-advisory.sh
#
# SessionStart hook: states the identity mode as advisory context. It is
# advisory BY NATURE -- a SessionStart hook is non-blocking and cannot refuse
# anything (verified: exit 2 does not block session start). Enforcement of an
# inconsistent baseline is the estate-identity-guard PreToolUse hook's job;
# this one only tells the session (and the human reading its transcript) which
# identity its GitHub writes will carry, so a wrong mode is at least visible
# from the first line.
#
# Registered under SessionStart (startup + resume) in hooks.json, invoked as
# `bash "$CLAUDE_PLUGIN_ROOT"/hooks/estate-mode-advisory.sh` like the others.

set -uo pipefail

[[ "${CLAUDECODE:-}" == "1" ]] || exit 0

case "$(basename "${CLAUDE_CONFIG_DIR:-}")" in
  .claude-personal)
    echo "Estate identity mode (personal profile): git and gh writes to GitHub authenticate as, and are authored by, the Claude App (claude-the-enduring[bot]) with the operator as co-author — never as her. The estate-identity PreToolUse guard blocks any git/gh write if the baseline is inconsistent, and a git push additionally requires the pre-push scanner hook installed in the repo."
    ;;
  .claude-professional)
    echo "Employer identity mode (professional profile): gh and git are owner-routed exactly as the credential includeIf is — repos under her own account use the Claude App, her employer's repos use her own login."
    ;;
esac
exit 0
