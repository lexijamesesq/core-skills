#!/usr/bin/env bash
# estate-mode-advisory.sh
#
# SessionStart hook: states the identity mode as advisory context. It is
# advisory BY NATURE -- a SessionStart hook is non-blocking and cannot refuse
# anything. Enforcement of an inconsistent baseline is the estate-identity-
# guard PreToolUse hook's job; this one only tells the session (and the human
# reading its transcript) which identity its GitHub writes carry -- including
# the case where this machine is NOT yet enrolled, so a session on a machine
# that has the plugin but not the estate baseline is not left guessing.
#
# Registered under SessionStart (startup + resume) in hooks.json, invoked as
# `bash "$CLAUDE_PLUGIN_ROOT"/hooks/estate-mode-advisory.sh` like the others.

set -uo pipefail

[[ "${CLAUDECODE:-}" == "1" ]] || exit 0

ESTATE_GITCONFIG="$HOME/.config/claude-estate/estate-mode.gitconfig"

case "$(basename "${CLAUDE_CONFIG_DIR:-}")" in
  .claude-personal)
    if [[ -f "$ESTATE_GITCONFIG" ]]; then
      echo "Estate identity mode (personal profile): git and gh writes to GitHub authenticate as, and are authored by, the Claude App (claude-the-enduring[bot]) with the operator as co-author — never as her. The estate-identity PreToolUse guard blocks any git/gh write if the baseline is inconsistent, and a git push additionally requires the pre-push scanner hook installed in the repo."
    else
      echo "Personal profile — NOT enrolled in estate identity mode (the estate baseline is not installed on this machine: $ESTATE_GITCONFIG is absent). git and gh behave as they did before the identity layer, and the estate-identity guard stays dormant until the operator enrolls this machine (applies the blueprint and relaunches)."
    fi
    ;;
  .claude-professional)
    echo "Employer identity mode (professional profile): gh and git are owner-routed exactly as the credential includeIf is — repos under her own account use the Claude App, her employer's repos use her own login."
    ;;
esac
exit 0
