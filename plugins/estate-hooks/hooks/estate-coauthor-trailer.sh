#!/usr/bin/env bash
# estate-coauthor-trailer.sh
#
# A git `prepare-commit-msg` hook (NOT a Claude Code hook -- it is not in
# hooks.json). In an estate session the author is the Claude App bot; this
# adds the operator as co-author so her attribution rides every bot commit,
# idempotently, the way the retired API publisher used to add it.
#
# Fires only for a fresh commit whose author IS the bot: it no-ops for her own
# commits (professional / her terminal) and skips merge / squash / amend
# sources so it never relabels imported history (a rebase or cherry-pick that
# reuses a prior author's message is left exactly as it was).
#
# INSTALL (open routing -- see the PR): this must land in each repo as
# `.git/hooks/prepare-commit-msg`. Estate mode cannot use core.hooksPath (the
# native pre-push scanner owns .git/hooks), and pre-commit's
# default_install_hook_types is [pre-commit, pre-push, commit-msg] -- not
# prepare-commit-msg. The recommendation is to ship this as a dotty-exported
# git hook installed per-repo by the same `pre-commit install --install-hooks`
# that installs the scanner (adding prepare-commit-msg to the install types),
# i.e. system-delegate3's mechanism. It is versioned here in the estate-hooks
# collection so the logic has one home regardless of where the install lands.

set -uo pipefail

MSG_FILE="${1:-}"
SRC="${2:-}"
[[ -n "$MSG_FILE" && -f "$MSG_FILE" ]] || exit 0

# Never touch imported/rewritten history -- only a fresh commit's own message.
case "$SRC" in
  merge|squash|commit) exit 0 ;;
esac

# Estate mode only: the commit's author must be the App bot.
BOT_EMAIL="325510841+claude-the-enduring[bot]@users.noreply.github.com"
[[ "${GIT_AUTHOR_EMAIL:-}" == "$BOT_EMAIL" ]] || exit 0

TRAILER="Co-authored-by: Alexis Bussa <938162+lexijamesesq@users.noreply.github.com>"

# git interpret-trailers places it in the message's trailer block correctly
# (creating the blank-line-separated block if there is none) and
# addIfDifferentNeighbor makes it idempotent -- a second run adds nothing.
if command -v git >/dev/null 2>&1; then
  git interpret-trailers --if-exists addIfDifferentNeighbor \
    --trailer "$TRAILER" --in-place "$MSG_FILE" 2>/dev/null && exit 0
fi

# Fallback if interpret-trailers is somehow unavailable: append idempotently.
grep -qiF "$TRAILER" "$MSG_FILE" && exit 0
[[ -n "$(tail -c1 "$MSG_FILE" 2>/dev/null)" ]] && printf '\n' >> "$MSG_FILE"
printf '\n%s\n' "$TRAILER" >> "$MSG_FILE"
exit 0
