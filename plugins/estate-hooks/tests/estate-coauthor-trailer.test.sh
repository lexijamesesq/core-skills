#!/usr/bin/env bash
# Test for estate-coauthor-trailer.sh (a git prepare-commit-msg hook): the
# operator's co-author trailer is added to a fresh BOT commit, idempotently,
# and only then -- not to her own commits, and not to merge/squash/amend.
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/assert.sh"
HOOK="${HOOK:-${SCRIPT_DIR}/../hooks/estate-coauthor-trailer.sh}"
[[ -f "$HOOK" ]] || { echo "FATAL: $HOOK not found"; exit 2; }

BOT="325510841+claude-the-enduring[bot]@users.noreply.github.com"
TRAILER="Co-authored-by: Alexis Bussa <938162+lexijamesesq@users.noreply.github.com>"
WORK="$(mktemp -d)"; trap 'rm -rf "$WORK"' EXIT

# grep -c already prints the count (0 or N) on stdout; capture it and swallow
# grep's nonzero exit on zero matches so it doesn't double-print via `|| echo`.
count_trailer() { local n; n=$(grep -cF "$TRAILER" "$1" 2>/dev/null); printf '%s' "${n:-0}"; }

section "Bot commit gets the trailer, idempotently"
printf 'Add a thing\n' > "$WORK/m1"
GIT_AUTHOR_EMAIL="$BOT" bash "$HOOK" "$WORK/m1" message
assert_eq "trailer added for a bot commit" "1" "$(count_trailer "$WORK/m1")"
GIT_AUTHOR_EMAIL="$BOT" bash "$HOOK" "$WORK/m1" message
assert_eq "a second run adds no duplicate" "1" "$(count_trailer "$WORK/m1")"

section "Her own commit gets no trailer"
printf 'Her commit\n' > "$WORK/m2"
GIT_AUTHOR_EMAIL="lexi@her.example" bash "$HOOK" "$WORK/m2" message
assert_eq "no trailer for a non-bot author" "0" "$(count_trailer "$WORK/m2")"

section "History is never relabelled (merge/squash/amend skipped)"
for src in merge squash commit; do
  printf 'Imported %s\n' "$src" > "$WORK/m-$src"
  GIT_AUTHOR_EMAIL="$BOT" bash "$HOOK" "$WORK/m-$src" "$src"
  assert_eq "source=$src is skipped even for the bot" "0" "$(count_trailer "$WORK/m-$src")"
done

section "Missing/empty args are a clean no-op"
bash "$HOOK" >/dev/null 2>&1; assert_eq "no message file -> exit 0" "0" "$?"
bash "$HOOK" "$WORK/does-not-exist" message >/dev/null 2>&1; assert_eq "absent file -> exit 0" "0" "$?"

finish
