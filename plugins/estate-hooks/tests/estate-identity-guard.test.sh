#!/usr/bin/env bash
# Test suite for estate-identity-guard.sh — PreToolUse enforcement of the
# estate identity baseline, gated on enrollment being a DISK fact.
#
# Two invariants matter most here and are both tested:
#  1. NOT ENROLLED -> personal pushes block, but reads/bootstrap stay available.
#  2. ENROLLED but the baseline is wrong -> the guard blocks (the bad-relaunch
#     case). Every break is one flipped value on an otherwise-good baseline.
#
# Run: bash plugins/estate-hooks/tests/estate-identity-guard.test.sh
set -uo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/lib/assert.sh"
HOOK="${HOOK:-${SCRIPT_DIR}/../hooks/estate-identity-guard.sh}"
[[ -f "$HOOK" ]] || {
	echo "FATAL: $HOOK not found"
	exit 2
}
command -v jq >/dev/null 2>&1 || {
	echo "FATAL: jq required"
	exit 2
}

BOT="325510841+claude-the-enduring[bot]@users.noreply.github.com"

# A scratch HOME with the estate baseline installed (i.e. ENROLLED).
SCRATCH="$(mktemp -d)"
trap 'rm -rf "$SCRATCH"' EXIT
CE="$SCRATCH/.config/claude-estate"
mkdir -p "$CE/bin" "$CE/gh-config" "$SCRATCH/.config/op-agent/bin" "$SCRATCH/.claude-personal"
: >"$CE/estate-mode.gitconfig"
: >"$CE/estate-env.sh"
: >"$CE/gh-config/hosts.yml"
printf '#!/bin/sh\n' >"$SCRATCH/.config/op-agent/bin/gh"
chmod +x "$SCRATCH/.config/op-agent/bin/gh"
printf '#!/bin/sh\n' >"$SCRATCH/.config/op-agent/bin/git-credential-estate"
chmod +x "$SCRATCH/.config/op-agent/bin/git-credential-estate"
ln -s "$SCRATCH/.config/op-agent/bin/gh" "$CE/bin/gh"

mkjson() { jq -n --arg c "$1" --arg cwd "${PAYLOAD_CWD:-}" '{tool_name:"Bash",tool_input:{command:$c}} + (if $cwd == "" then {} else {cwd:$cwd} end)'; }
# run_guard <cmd> [ENV_OVERRIDE...] -> RC. Good ENROLLED baseline, overrides win.
run_guard() {
	local cmd="$1"
	shift
	printf '%s' "$(mkjson "$cmd")" | env -i \
		HOME="$SCRATCH" CLAUDECODE=1 CLAUDE_CONFIG_DIR="$SCRATCH/.claude-personal" \
		GIT_CONFIG_GLOBAL="$CE/estate-mode.gitconfig" CLAUDE_ENV_FILE="$CE/estate-env.sh" \
		GH_CONFIG_DIR="$CE/gh-config" GIT_AUTHOR_EMAIL="$BOT" GIT_COMMITTER_EMAIL="$BOT" \
		SSH_AUTH_SOCK="" PATH="/usr/bin:/bin" \
		"$@" bash "$HOOK" >/dev/null 2>&1
	RC=$?
}
blocks() {
	run_guard "$@"
	assert_eq "BLOCK: $1 ${*:2}" "2" "$RC"
}
allows() {
	run_guard "$@"
	assert_eq "allow: $1 ${*:2}" "0" "$RC"
}

section "Enrollment gate — personal pushes need enrollment; reads and setup stay available"
mv "$CE/estate-mode.gitconfig" "$SCRATCH/estate-mode.gitconfig.bak"
allows 'git status'
allows 'gh pr create'
blocks 'git push origin main'
blocks 'git -C /fixture push origin main'
allows 'bash scripts/prepare-checkout.sh'
allows 'git clone https://github.com/lexijamesesq/core-skills.git'
allows 'git push origin main' CLAUDE_CONFIG_DIR="$SCRATCH/.claude-professional"
allows 'git push origin main' CLAUDECODE=""
mv "$SCRATCH/estate-mode.gitconfig.bak" "$CE/estate-mode.gitconfig"

section "Enrolled + good baseline is allowed"
allows 'git status'
allows 'gh pr list'
allows 'git commit -m x'

section "Out of scope — no opinion"
allows 'ls -la'
allows 'git status' CLAUDECODE=""
allows 'git status' CLAUDE_CONFIG_DIR="$SCRATCH/.claude-professional"

section "Enrolled + broken baseline blocks (each break is one flipped value)"
blocks 'git commit -m x' GIT_CONFIG_GLOBAL="/wrong"
blocks 'gh pr create' GH_CONFIG_DIR=""
blocks 'git commit -m x' CLAUDE_ENV_FILE="/wrong/estate-env.sh"
blocks 'git commit -m x' SSH_AUTH_SOCK="/tmp/leaked.sock"
blocks 'git commit -m x' GIT_AUTHOR_EMAIL="lexi@her.example"
blocks 'git commit -m x' GIT_COMMITTER_EMAIL=""

section "CLAUDE_ENV_FILE points at a MISSING file -> block"
rm -f "$CE/estate-env.sh"
blocks 'git status'
: >"$CE/estate-env.sh"

section "Estate PATH dir must be exactly the gh symlink"
# an extra file in the dir -> block
: >"$CE/bin/leftover"
blocks 'git status'
rm -f "$CE/bin/leftover"
allows 'git status' # restored
# gh replaced by a non-symlink / wrong target -> block
rm -f "$CE/bin/gh"
printf '#!/bin/sh\n' >"$CE/bin/gh"
blocks 'git status'
rm -f "$CE/bin/gh"
ln -s "$SCRATCH/.config/op-agent/bin/gh" "$CE/bin/gh"

section "Missing credential helper blocks"
mv "$SCRATCH/.config/op-agent/bin/git-credential-estate" "$SCRATCH/helper.bak"
blocks 'git status'
mv "$SCRATCH/helper.bak" "$SCRATCH/.config/op-agent/bin/git-credential-estate"

section "git push — the pre-push scanner hook must be installed in the repo"
# GIT_CONFIG_GLOBAL=/dev/null so this scratch repo does not inherit the dev
# shell's global git config: an ENROLLED shell's estate-mode.gitconfig sets
# init.templateDir, which would copy the pre-push scanner hook into .git/hooks
# and defeat the "without scanner hook -> block" case just below.
repo="$SCRATCH/repo"
while IFS= read -r key; do unset "$key"; done < <(git rev-parse --local-env-vars)
mkdir -p "$repo"
(cd "$repo" && GIT_CONFIG_GLOBAL=/dev/null git init -q)
run_in_repo() { (
	cd "$repo" && run_guard "$@"
	echo "$RC"
); }
rc="$(run_in_repo 'git push origin main')"
assert_eq "push without scanner hook -> block" "2" "$rc"
mkdir -p "$repo/.git/hooks"
printf '#!/usr/bin/env bash\n# File generated by pre-commit: https://pre-commit.com\n' >"$repo/.git/hooks/pre-push"
chmod +x "$repo/.git/hooks/pre-push"
rc="$(run_in_repo 'git push origin main')"
assert_eq "push with pre-commit scanner hook -> allow" "0" "$rc"

section "Payload cwd selects the checkout independently of the hook process cwd"
# Process cwd is outside Git; ignoring .cwd would silently allow the missing hook.
run_from_scratch() { (
	cd "$SCRATCH" || exit 1
	PAYLOAD_CWD="$repo" run_guard 'git push origin main'
	echo "$RC"
); }
rc="$(run_from_scratch)"
assert_eq "payload checkout with scanner allows from outside Git" "0" "$rc"
mv "$repo/.git/hooks/pre-push" "$SCRATCH/scanner.bak"
rc="$(run_from_scratch)"
assert_eq "payload checkout without scanner blocks from outside Git" "2" "$rc"
mv "$SCRATCH/scanner.bak" "$repo/.git/hooks/pre-push"
rm -f "$repo/.git/hooks/pre-push"
rc="$(run_in_repo 'git status')"
assert_eq "non-push git command not gated on the scanner hook" "0" "$rc"

section "Effective hook path in a linked worktree and custom hook directory"
GIT_CONFIG_GLOBAL=/dev/null git -C "$repo" -c user.name=Fixture -c user.email=fixture@example.invalid commit --allow-empty -qm seed
GIT_CONFIG_GLOBAL=/dev/null git -C "$repo" worktree add -qb fixture "$SCRATCH/worktree"
printf '#!/bin/sh\n# File generated by pre-commit: https://pre-commit.com\n' >"$repo/.git/hooks/pre-push"
chmod +x "$repo/.git/hooks/pre-push"
original_repo="$repo"
repo="$SCRATCH/worktree"
rc="$(run_in_repo 'git push origin main')"
assert_eq "linked worktree finds the common effective scanner hook" "0" "$rc"
repo="$original_repo"
mkdir -p "$repo/custom-hooks"
GIT_CONFIG_GLOBAL=/dev/null git -C "$repo" config core.hooksPath custom-hooks
rc="$(run_in_repo 'git push origin main')"
assert_eq "custom hook path without scanner blocks despite default hook" "2" "$rc"
cp "$repo/.git/hooks/pre-push" "$repo/custom-hooks/pre-push"
rc="$(run_in_repo 'git push origin main')"
assert_eq "custom effective scanner hook is found" "0" "$rc"
chmod -x "$repo/custom-hooks/pre-push"
rc="$(run_in_repo 'git push origin main')"
assert_eq "nonexecutable scanner cannot authorize a push" "2" "$rc"

section "Fail-open on infra errors"
printf 'not json {{{' | bash "$HOOK" >/dev/null 2>&1
assert_eq "garbage stdin -> exit 0" "0" "$?"
printf '' | bash "$HOOK" >/dev/null 2>&1
assert_eq "empty stdin -> exit 0" "0" "$?"
printf '%s' '{"tool_name":"Read","tool_input":{"file_path":"/x"}}' | bash "$HOOK" >/dev/null 2>&1
assert_eq "non-Bash tool -> exit 0" "0" "$?"

finish
