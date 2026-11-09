#!/usr/bin/env bash
# estate-mode-advisory.sh
#
# SessionStart hook: states the identity mode as advisory context. It is
# advisory BY NATURE -- a SessionStart hook is non-blocking and cannot refuse
# anything. Enforcement of an inconsistent baseline is the estate-identity-
# guard PreToolUse hook's job; this one only tells the session (and the human
# reading its transcript) which identity its GitHub writes carry -- including
# the case where the session is on neither baseline, so a session on a machine
# that has the plugin but no baseline is not left guessing.
#
# A personal session's baseline is read from its OWN environment: where
# GIT_CONFIG_GLOBAL points, exactly as the gh adapter decides. A SessionStart
# hook sees the settings env (checked with a real launch), so this is the
# session's truth; the estate gitconfig merely existing on disk is not, since
# it stays installed after the operator baseline takes over.
#
# Registered under SessionStart (startup + resume) in hooks.json, invoked as
# `bash "$CLAUDE_PLUGIN_ROOT"/hooks/estate-mode-advisory.sh` like the others.

set -uo pipefail

[[ "${CLAUDECODE:-}" == "1" ]] || exit 0

ESTATE_GITCONFIG="$HOME/.config/claude-estate/estate-mode.gitconfig"
OPERATOR_GITCONFIG="$HOME/.config/claude-operator/operator-mode.gitconfig"

case "$(basename "${CLAUDE_CONFIG_DIR:-}")" in
.claude-personal)
	case "${GIT_CONFIG_GLOBAL:-}" in
	"$OPERATOR_GITCONFIG")
		echo "Operator identity mode (personal profile): git and gh writes to GitHub authenticate as, and are authored by, the operator's own account (lexijamesesq), unsigned, with no co-author line -- not the Claude App. The estate-identity PreToolUse guard blocks any git/gh write if the baseline is inconsistent, and a git push additionally requires the pre-push scanner hook installed in the repo."
		;;
	"$ESTATE_GITCONFIG")
		echo "Estate identity mode (personal profile): git and gh writes to GitHub authenticate as, and are authored by, the Claude App (claude-the-enduring[bot]) alone — never as her, and with no co-author line. The estate-identity PreToolUse guard blocks any git/gh write if the baseline is inconsistent, and a git push additionally requires the pre-push scanner hook installed in the repo."
		;;
	*)
		echo "Personal profile — NOT enrolled in an identity baseline (GIT_CONFIG_GLOBAL is '${GIT_CONFIG_GLOBAL:-<unset>}', neither the operator's nor the App's). git and gh behave as they did before the identity layer. Where a baseline is installed on this machine, the estate-identity guard blocks git/gh writes from a session that matches neither: relaunch the session, or ask the operator."
		;;
	esac
	;;
.claude-professional)
	echo "Employer identity mode (professional profile): gh and git are owner-routed exactly as the credential includeIf is — repos under her own account use the Claude App, her employer's repos use her own login."
	;;
esac
exit 0
