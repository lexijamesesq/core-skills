#!/usr/bin/env bash
# gh-scope-common.sh — the ONE definition of "a `gh pr <verb>` in command
# position", shared by every hook that decides its own scope on a PR
# command: gh-pr-body-guard.sh, gh-pr-body-template-guard.sh, pr-cache.sh,
# pr-verdict-watch-arm.sh and security-review-reminder.sh.
#
# WHY ONE FILE: the rule used to be copied into each hook and kept in step
# by a comment — the exact drift class the PR-hooks fix exists to remove
# (non-author review, this repo's PR #111). This helper is this repo's own
# (only gitleaks-common.sh and house-code-common.sh are drift-checked
# against dotty), so it can carry the rule. tests/gh-scope-common.test.sh
# proves every consumer sources it and none defines the rule locally.
#
# WHY SELF-SCOPE AT ALL: a settings `"if": "Bash(gh pr *)"` prefilter drops
# any command that does not START with the bare words `gh pr` unless it
# carries $(...), backticks, or $VAR — and the estate never runs bare `gh`.
# It invokes its wrapper by path, or through a variable holding that path,
# often inside a heredoc'd script. Found live: the arm-a-Monitor hook was
# silent on every real PR create, and the fail-closed secret scan skipped
# them. So the PR hooks carry no prefilter and decide scope here.
#
# THE RULE. Command position = start of the (normalised) text, or after a
# shell separator (; && || | ( `), optionally preceded by wrapper words
# (env/time/sudo/nohup/command) and by leading env assignments
# (FOO=bar gh pr create ...). The gh token is any of:
#   gh                       bare, on PATH
#   <anything>/gh            a path ending in /gh — the mandated wrapper is
#                            invoked by path, never as bare `gh`
#   $NAME / ${NAME}          a shell variable holding that path
# followed by ` pr ` and then the verb(s) the caller names.
#
# NORMALISATION first (gh_scope_normalize): a line continuation becomes a
# space (`gh pr \<newline>create` is one command); a real newline becomes
# ` ; ` (it IS a separator — collapsing it to a space would hide a create
# on a later line of a script behind leading whitespace); whitespace
# collapses; shell quotes are stripped (the shell removes them before
# executing, so `gh pr "create"` and `"$GH" pr create` are real commands —
# removing quotes only ever ADDS matches, never masks one).
#
# POROSITY (disclosed): string matching cannot see through indirection — a
# subcommand held in a variable (`c=create; gh pr $c`), an alias, a
# function, `eval`. The threat model is the ordinary command, not an
# operator routing around their own hooks.
#
# This file is sourced, not executed. It defines one variable and four
# functions. Each consumer decides what a MISSING helper means under its
# own contract: a fail-open hook says nothing (exit 0); a fail-closed guard
# blocks.

# The prefix through ` pr `; the caller appends the verb alternation.
# shellcheck disable=SC2016  # regex-literal dollar (\$NAME), not a shell expansion
GH_SCOPE_CMD_RE='(^|[;&|(`])[[:space:]]*((env|time|sudo|nohup|command)[[:space:]]+)*([A-Za-z_][A-Za-z0-9_]*=[^ ]* )*(gh|[^ ;&|(`]*/gh|\$[A-Za-z_][A-Za-z0-9_]*|\$\{[A-Za-z_][A-Za-z0-9_]*\})[[:space:]]+pr[[:space:]]+'

# gh_scope_normalize <command> -> prints the normalised command text.
gh_scope_normalize() {
	local n="$1"
	n="${n//\\$'\n'/ }" # line continuations -> single space
	n="${n//$'\n'/ ; }" # newlines are command separators
	n="$(tr -s '[:space:]' ' ' <<<"$n")"
	n="${n//\"/}"
	n="${n//\'/}"
	printf '%s' "$n"
}

# gh_pr_in_command_position <command> <verbs>
# <verbs> is an ERE alternation without parens, e.g. create, "create|edit".
# Returns 0 iff `gh pr <verb>` (gh in any of the three shapes) stands in
# command position somewhere in the normalised command.
gh_pr_in_command_position() {
	local norm re
	norm="$(gh_scope_normalize "$1")"
	re="${GH_SCOPE_CMD_RE}($2)([[:space:]]|\$)"
	[[ "$norm" =~ $re ]]
}

# gh_scope_cd_chain_dir <normalised-command> <payload-cwd>
# Need: Claude Code's PreToolUse payload reports the SESSION cwd, not the
# directory a command cd's into, and a cd inside a Bash command does not
# persist — so `cd <repo> && gh pr create ...` arrives with cwd = the
# session root. Both PR guards need the directory gh will ACTUALLY run in:
# the secret guard to resolve a relative --body-file and to exclude the cd
# prefix from its scan, the template guard for the same body file and for
# which repo's template applies. One copy of the walk, here (it was
# duplicated verbatim in both guards; non-author review, PR #111).
# Prints the EFFECTIVE working directory after consuming ALL leading
# `cd <path>` segments (delimited by && || ; or a newline, already ';' in
# the normalised text), applied IN ORDER: an absolute or ~/$HOME target
# replaces, a relative target appends to the running dir, and every
# intermediate MUST resolve to a real directory. Prints nothing if there is
# no leading cd OR any segment fails to resolve (never guess the effective
# dir — a single-cd read would collapse `cd A && cd B` to A and read the
# wrong body).
gh_scope_cd_chain_dir() {
	local s="$1" cwd="$2" seg path eff=""
	s="${s//&&/;}"
	s="${s//||/;}" # canonicalise sequencing ops -> ;
	while :; do
		s="${s#"${s%%[![:space:]]*}"}"        # left-trim
		[[ "$s" == cd[[:space:]]* ]] || break # next segment isn't a cd -> stop
		seg="${s%%;*}"                        # this segment, up to the first ;
		if [[ "$seg" == "$s" ]]; then s=""; else s="${s#*;}"; fi
		path="${seg#cd}"
		path="${path#"${path%%[![:space:]]*}"}" # strip leading ws after 'cd'
		path="${path%"${path##*[![:space:]]}"}" # right-trim
		[[ -n "$path" ]] || return 0            # 'cd' with no arg -> bail (fail)
		path="${path//\\ / }"                   # unescape backslash-spaces
		path="${path/#\~/$HOME}"
		path="${path//\$HOME/$HOME}"
		case "$path" in
		/*) eff="$path" ;;             # absolute -> replace
		*) eff="${eff:-$cwd}/$path" ;; # relative -> append to running dir
		esac
		eff="$(cd "$eff" 2>/dev/null && pwd)" || return 0 # must be a real dir
	done
	[[ -n "$eff" ]] && printf '%s' "$eff"
}

# gh_scope_target_dir <command> <payload-cwd>
# Prints the directory gh will run in: the resolved cd-chain target when the
# command has one, else the payload cwd. (A chain that does not resolve
# falls back to the payload cwd — the guards then resolve a relative body
# file against it, which is what gh would do after a failed cd aborts the
# && chain: nothing runs, and a block on an unreadable body is the safe
# answer.)
gh_scope_target_dir() {
	local d
	d="$(gh_scope_cd_chain_dir "$(gh_scope_normalize "$1")" "$2")"
	printf '%s' "${d:-$2}"
}
