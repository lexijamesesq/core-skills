#!/usr/bin/env bash
# Native local project boundaries; keep scheduled current-main drift independent.
set -euo pipefail
root=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
cd "$root"
component=${1:?usage: check-push.sh linear|estate-hooks|plugin|shared-copy|standalone}
case "$component" in linear | estate-hooks | plugin | shared-copy | standalone) ;; *)
	echo "Unknown component: $component" >&2
	exit 2
	;;
esac
paths=$(mktemp)
trap 'rm -f "$paths"' EXIT
if [[ -n "${PRE_COMMIT_FROM_REF:-}" && -n "${PRE_COMMIT_TO_REF:-}" ]]; then
	outgoing=$PRE_COMMIT_TO_REF
	git diff --name-only --no-renames -z "$PRE_COMMIT_FROM_REF" "$PRE_COMMIT_TO_REF" >"$paths"
elif [[ -n "${PRE_COMMIT_REMOTE_NAME:-}" && -n "${PRE_COMMIT_LOCAL_BRANCH:-}" ]]; then
	# Match native pre-commit's first/root-push ancestry, retaining deletions.
	outgoing=$PRE_COMMIT_LOCAL_BRANCH
	git rev-parse --verify "$outgoing^{commit}" >/dev/null
	git log --format= --name-only --no-renames -z "$PRE_COMMIT_LOCAL_BRANCH" --not "--remotes=$PRE_COMMIT_REMOTE_NAME" >"$paths"
else
	echo 'Cannot select push checks: native outgoing range is unavailable.' >&2
	exit 2
fi
relevant=false
while IFS= read -r -d '' path; do
	path=${path#$'\n'}
	case "$path" in .pre-commit-config.yaml | .github/scripts/check-push.sh | plugins/estate-hooks/tests/lib/fixture-env.sh) relevant=true ;; esac
	case "$component:$path" in
	linear:plugins/core/skills/linear/scripts/* | linear:plugins/core/skills/traffic-cone/scripts/* | linear:pyproject.toml | linear:uv.lock | linear:requirements*.txt) relevant=true ;;
	estate-hooks:plugins/estate-hooks/*) relevant=true ;;
	plugin:.claude-plugin/* | plugin:plugins/*) relevant=true ;;
	shared-copy:.github/scripts/drift-check.sh | shared-copy:plugins/estate-hooks/hooks/gitleaks-common.sh | shared-copy:plugins/estate-hooks/hooks/house-code-common.sh | shared-copy:plugins/estate-hooks/hooks/pr-body-check.py) relevant=true ;;
	standalone:.github/scripts/standalone-check.sh | standalone:plugins/estate-hooks/hooks/* | standalone:plugins/core/skills/linear/scripts/* | standalone:plugins/core/skills/traffic-cone/scripts/*) relevant=true ;;
	esac
done <"$paths"
rm -f "$paths"
trap - EXIT
[[ "$relevant" == true ]] || {
	echo "core-skills $component: no affected inputs"
	exit 0
}
# Selection may describe a different ref than this checkout. Never claim
# project coverage for content the selected suites are not actually reading.
outgoing=$(git rev-parse --verify "$outgoing^{commit}") || exit 2
head=$(git rev-parse --verify HEAD) || exit 2
untracked=$(git ls-files --others --exclude-standard) || exit 2
if [[ "$outgoing" != "$head" ]] || ! git diff --quiet "$outgoing" -- ||
	! git diff --cached --quiet "$outgoing" -- ||
	[[ -n "$untracked" ]]; then
	echo 'BLOCKED: push checks require a clean checkout/worktree at the pushed head (including the index and nonignored untracked files).' >&2
	exit 2
fi
# Only child fixtures lose Git routing/config; selection above uses the actual
# author checkout. Product validation/drift are read-only and retain their tools.
isolate="$root/plugins/estate-hooks/tests/lib/fixture-env.sh"
case "$component" in
linear)
	cd plugins/core/skills/linear/scripts
	exec bash "$isolate" uvx pytest@9.1.1 tests
	;;
estate-hooks)
	for suite in "$root"/plugins/estate-hooks/tests/*.test.sh; do
		echo ">>> ${suite##*/}"
		bash "$isolate" bash "$suite"
	done
	;;
plugin) exec claude plugin validate --strict . ;;
shared-copy)
	dotty=${DOTTY_CHECKOUT:-$HOME/bin/dotty}
	[[ -f "$dotty/.pre-commit-hooks.yaml" ]] || {
		echo 'Maintained DOTTY_CHECKOUT is required for shared-copy verification.' >&2
		exit 2
	}
	exec bash .github/scripts/drift-check.sh "$dotty" "$root"
	;;
standalone) exec bash "$isolate" bash .github/scripts/standalone-check.sh "$root" ;;
esac
