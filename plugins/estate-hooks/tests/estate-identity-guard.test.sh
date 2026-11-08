#!/usr/bin/env bash
# Test suite for estate-identity-guard.sh — PreToolUse enforcement of the
# estate identity baseline, gated on enrollment being a DISK fact.
#
# Two baselines are accepted (the App baseline and the operator baseline); a
# session must satisfy ONE completely. Enrollment is either baseline's
# gitconfig being installed. Three invariants matter most and are all tested:
#  1. NOT ENROLLED -> Claude pushes across profiles block, but reads/bootstrap stay available.
#  2. ENROLLED but the baseline is wrong -> the guard blocks (the bad-relaunch
#     case). Every break is one flipped value on an otherwise-good baseline.
#  3. Retiring one baseline's gitconfig must never drop the other baseline's
#     sessions into the not-enrolled block-all-push branch.
#
# NOT covered here, by design: whether the hook process inherits the session's
# settings env. The fixtures hand the hook an explicit env, so that inheritance
# is a real-launch check carried to the cutover. Likewise an env-based guard
# cannot see command-line `git -c` overrides or a repo-level core.sshCommand
# (same for both baselines), and the scanner check keys on the payload cwd, not
# the target repo of a `git -C`.
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
OPERATOR="938162+lexijamesesq@users.noreply.github.com"

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

# The operator baseline's files live in their own directory and are installed
# only where a section needs them (the enrollment gate needs neither present).
OP="$SCRATCH/.config/claude-operator"
install_operator() {
	mkdir -p "$OP/gh-config"
	printf '[credential "https://github.com"]\n\thelper =\n\thelper = !/fixture/pat-helper\n' >"$OP/operator-mode.gitconfig"
	printf '# fixture operator env\n' >"$OP/operator-env.sh"
}
remove_operator() { rm -rf "$OP"; }

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
# Same as run_guard but a session on the good OPERATOR baseline; overrides win.
run_guard_op() {
	local cmd="$1"
	shift
	run_guard "$cmd" GIT_CONFIG_GLOBAL="$OP/operator-mode.gitconfig" CLAUDE_ENV_FILE="$OP/operator-env.sh" \
		GH_CONFIG_DIR="$OP/gh-config" GIT_AUTHOR_EMAIL="$OPERATOR" GIT_COMMITTER_EMAIL="$OPERATOR" \
		GH_TOKEN="fixture-not-a-real-token" "$@"
}
blocks_op() {
	run_guard_op "$@"
	assert_eq "BLOCK (operator): $1 ${*:2}" "2" "$RC"
}
allows_op() {
	run_guard_op "$@"
	assert_eq "allow (operator): $1 ${*:2}" "0" "$RC"
}
blocks() {
	run_guard "$@"
	assert_eq "BLOCK: $1 ${*:2}" "2" "$RC"
}
allows() {
	run_guard "$@"
	assert_eq "allow: $1 ${*:2}" "0" "$RC"
}

section "Enrollment gate — all Claude profiles need enrollment to push"
mv "$CE/estate-mode.gitconfig" "$SCRATCH/estate-mode.gitconfig.bak"
allows 'git status'
allows 'gh pr create'
blocks 'git push origin main'
blocks 'git -C /fixture push origin main'
allows 'pre-commit install --hook-type pre-push'
allows 'git clone https://github.com/lexijamesesq/core-skills.git'
blocks 'git push origin main' CLAUDE_CONFIG_DIR="$SCRATCH/.claude-professional"
blocks 'git push origin main' CLAUDE_CONFIG_DIR="$SCRATCH/.claude"
blocks 'git push origin main' CLAUDE_CONFIG_DIR=""
allows 'git status' CLAUDE_CONFIG_DIR="$SCRATCH/.claude-professional"
allows 'gh pr create' CLAUDE_CONFIG_DIR="$SCRATCH/.claude-professional"
allows 'pre-commit install --hook-type pre-push' CLAUDE_CONFIG_DIR="$SCRATCH/.claude-professional"
allows 'git push origin main' CLAUDECODE=""
mv "$SCRATCH/estate-mode.gitconfig.bak" "$CE/estate-mode.gitconfig"

section "Enrolled + good baseline is allowed"
allows 'git status'
allows 'gh pr list'
allows 'git commit -m x'
# Owner routing is independent of the personal estate identity environment.
allows 'git push origin main' CLAUDE_CONFIG_DIR="$SCRATCH/.claude-professional" GIT_CONFIG_GLOBAL="/owner-routing"

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

section "Operator baseline — allowed, and every break blocks"
install_operator
allows_op 'git status'
allows_op 'gh pr list'
allows_op 'git commit -m x'
# professional/non-Claude stay out of scope on this baseline too
allows_op 'git status' CLAUDE_CONFIG_DIR="$SCRATCH/.claude-professional"
blocks_op 'git commit -m x' GIT_CONFIG_GLOBAL="/wrong"
blocks_op 'gh pr create' GH_CONFIG_DIR=""
blocks_op 'git commit -m x' CLAUDE_ENV_FILE="/wrong/operator-env.sh"
blocks_op 'git commit -m x' SSH_AUTH_SOCK="/tmp/leaked.sock"
blocks_op 'git commit -m x' GIT_AUTHOR_EMAIL="lexi@her.example"
blocks_op 'git commit -m x' GIT_COMMITTER_EMAIL=""
rm -f "$OP/operator-env.sh"
blocks_op 'git status'
printf '# fixture operator env\n' >"$OP/operator-env.sh"
# The operator baseline does not need the App's adapter dir or credential helper.
mv "$SCRATCH/.config/op-agent/bin/git-credential-estate" "$SCRATCH/helper.bak"
rm -f "$CE/bin/gh"
allows_op 'git status'
blocks 'git status' # the App baseline still needs both
mv "$SCRATCH/helper.bak" "$SCRATCH/.config/op-agent/bin/git-credential-estate"
ln -s "$SCRATCH/.config/op-agent/bin/gh" "$CE/bin/gh"

section "Dual baseline — checks are per baseline, never mixed"
# The operator gitconfig carrying the bot identity: each value is valid in some
# baseline, but the session satisfies neither baseline as a whole.
blocks_op 'git commit -m x' GIT_AUTHOR_EMAIL="$BOT" GIT_COMMITTER_EMAIL="$BOT"

section "Credential channel and delivery"
# One case per distinct protection, not per variable name or code line.
# No ambient token in an App session (an injected token would be what gh uses).
blocks 'gh pr create' GH_TOKEN="injected"
# The real App session carries the token vars SET BUT EMPTY; that must stay allowed.
allows 'git status' GH_TOKEN="" GITHUB_TOKEN=""
# The operator baseline requires the PAT.
blocks_op 'gh pr create' GH_TOKEN=""
# No env-injected config or askpass override on a valid baseline (identity and
# credentials would come from the override, not the baseline).
blocks_op 'git status' GIT_CONFIG_COUNT="1"
# Presence is not delivery: each operator file must hold content.
printf '[user]\n\tuseConfigOnly = true\n' >"$OP/operator-mode.gitconfig" # content, no credential helper
blocks_op 'git status'
install_operator
: >"$OP/operator-env.sh"
blocks_op 'git status'
install_operator
rm -rf "$OP/gh-config"
: >"$OP/gh-config" # a file where the directory belongs
blocks_op 'git status'
rm -f "$OP/gh-config"
install_operator

section "Enrollment is either baseline's gitconfig, not estate-mode alone"
repo="$SCRATCH/repo-enroll"
mkdir -p "$repo"
(cd "$repo" && GIT_CONFIG_GLOBAL=/dev/null git init -q)
mkdir -p "$repo/.git/hooks"
printf '#!/usr/bin/env bash\n# File generated by pre-commit: https://pre-commit.com\n' >"$repo/.git/hooks/pre-push"
chmod +x "$repo/.git/hooks/pre-push"
enrolled_push() { (
	cd "$repo" && "$1" 'git push origin main'
	echo "$RC"
); }
# estate-mode retired, operator gitconfig present: still enrolled and allowed
mv "$CE/estate-mode.gitconfig" "$SCRATCH/estate-mode.gitconfig.bak"
rc="$(enrolled_push run_guard_op)"
assert_eq "operator-only install: operator push is enrolled and allowed" "0" "$rc"
allows_op 'git status'
blocks_op 'git status' GIT_AUTHOR_EMAIL="lexi@her.example" # enrolled, so a bad baseline still blocks
# a leftover App-baseline session is not allowed once its gitconfig is gone
blocks 'git status'
mv "$SCRATCH/estate-mode.gitconfig.bak" "$CE/estate-mode.gitconfig"
# the pre-push scanner requirement is shared by both baselines
rm -f "$repo/.git/hooks/pre-push"
rc="$(enrolled_push run_guard_op)"
assert_eq "operator baseline push without scanner hook -> block" "2" "$rc"
printf '#!/usr/bin/env bash\n# File generated by pre-commit: https://pre-commit.com\n' >"$repo/.git/hooks/pre-push"
chmod +x "$repo/.git/hooks/pre-push"
# the reverse: operator files absent, estate-mode present (today's machines)
remove_operator
allows 'git status'
rc="$(enrolled_push run_guard)"
assert_eq "App-only install: App push is enrolled and allowed" "0" "$rc"
blocks_op 'git status'
# neither present: not enrolled, push blocks for any profile
mv "$CE/estate-mode.gitconfig" "$SCRATCH/estate-mode.gitconfig.bak"
rc="$(enrolled_push run_guard)"
assert_eq "neither baseline installed: push blocks" "2" "$rc"
mv "$SCRATCH/estate-mode.gitconfig.bak" "$CE/estate-mode.gitconfig"
install_operator

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
