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
	# Where the session's own env points, and whether that file is really installed, as the guard decides: a setting
	# that names a baseline whose file is missing is not that baseline.
	gcg="${GIT_CONFIG_GLOBAL:-}"
	if [[ "$gcg" == "$OPERATOR_GITCONFIG" && -f "$OPERATOR_GITCONFIG" ]]; then
		echo "Operator identity mode (personal profile): git and gh writes to GitHub authenticate as, and are authored by, the operator's own account (lexijamesesq), unsigned, with no co-author line -- not the Claude App. The estate-identity PreToolUse guard blocks any git/gh write if the baseline is inconsistent, and a git push additionally requires the pre-push scanner hook installed in the repo."
	elif [[ "$gcg" == "$ESTATE_GITCONFIG" && -f "$ESTATE_GITCONFIG" ]]; then
		echo "Estate identity mode (personal profile): git and gh writes to GitHub authenticate as, and are authored by, the Claude App (claude-the-enduring[bot]) alone — never as her, and with no co-author line. The estate-identity PreToolUse guard blocks any git/gh write if the baseline is inconsistent, and a git push additionally requires the pre-push scanner hook installed in the repo."
	elif [[ ! -f "$ESTATE_GITCONFIG" && ! -f "$OPERATOR_GITCONFIG" ]]; then
		echo "Personal profile — NOT enrolled in an identity baseline: no estate or operator gitconfig is installed on this machine (GIT_CONFIG_GLOBAL is '${gcg:-<unset>}'). git and gh behave as they did before the identity layer, except that the estate-identity guard blocks git push until the machine is enrolled (apply the blueprint and relaunch)."
	else
		echo "Personal profile — NOT enrolled in either identity baseline: GIT_CONFIG_GLOBAL is '${gcg:-<unset>}', which is neither the operator's nor the App's gitconfig, or names a file that is missing. A baseline is installed on this machine, so the estate-identity guard blocks every git and gh command from this session, reads included, until it is relaunched on a baseline: relaunch the session, or ask the operator."
	fi
	;;
.claude-professional)
	echo "Employer identity mode (professional profile): gh and git are owner-routed exactly as the credential includeIf is — repos under her own account use the Claude App, her employer's repos use her own login."
	;;
esac
exit 0
