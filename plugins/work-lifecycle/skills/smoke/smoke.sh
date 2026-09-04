#!/usr/bin/env bash
# smoke.sh — /smoke's probe suite.
#
# On-demand Mac-side configuration health check: proves each protection layer
# (hooks, lint gate, registered automation) is wired RIGHT NOW, not that it
# was wired the day it shipped. Read-only, no network, no credentials, no
# writes — every probe exercises the real surface (pipes JSON at the real
# hook, runs the real test suite, parses the real live settings.json) and
# reports; it never fixes anything.
#
# Output: one line per probe, "PASS|FAIL <probe-name>: <detail>", then a
# summary line. Exit 0 iff zero FAILs.
#
# Each probe runs a STALENESS assertion before its health assertion: if the
# surface it targets is missing or moved, that is itself a loud FAIL naming
# the staleness — never a silent skip. A probe that quietly stops checking
# because its target moved is worse than a probe that never existed.
#
# Growth rule: a probe is added only after a real silent-misconfiguration
# incident bites — never speculatively. See SKILL.md for the probes'
# incident provenance.
#
# Spec: SKILL.md (this directory)

set -uo pipefail

# No self-location variable (HERE/SKILLS_DIR) needed anymore: every probe
# resolves its targets from declared state (core.json, plugins.json,
# installed_plugins.json) rather than a path relative to this script's own
# location — this rework retired the last probe (5, the old
# blueprint-coverage) that walked a co-located skills tree.

FAIL_COUNT=0
RESULT_LINES=()

# report <PASS|FAIL> <probe-name> <detail...> — records one result line and
# tallies failures. Never exits — every probe runs regardless of prior FAILs.
report() {
    local status="$1" name="$2"
    shift 2
    RESULT_LINES+=("$status $name: $*")
    [[ "$status" == "FAIL" ]] && FAIL_COUNT=$((FAIL_COUNT + 1))
}

# resolve_estate_hooks_install <profile_dir> — echoes the installPath of
# estate-hooks@work-lifecycle's scope:user install entry from that profile's
# installed_plugins.json, or nothing if unresolved. Shared by probe 1 (which
# needs one real cache to pipe JSON at) and probe 6 (defined further down,
# which keeps its own inline resolution — this helper exists for probe 1
# only, to avoid a second divergent implementation).
PY_RESOLVE_ESTATE_HOOKS_CACHE="$(cat <<'PYEOF'
import json, os, sys
path = sys.argv[1]
try:
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
except Exception:
    sys.exit(0)
entries = data.get("plugins", {}).get("estate-hooks@work-lifecycle", [])
for e in entries:
    if isinstance(e, dict) and e.get("scope") == "user":
        p = e.get("installPath", "")
        if p and os.path.isdir(p):
            print(p)
            break
PYEOF
)"

# ---------------------------------------------------------------------------
# Probe 1: hook-tilde-expansion
#
# Proves vault-mcp-redirect.sh still expands a tilde-form VAULT_ROOT before
# comparing it against a realpath-resolved target. Regression class: the
# 2026-06-02 incident where both vault hooks compared a realpath-resolved
# absolute path against an UNEXPANDED tilde, so the `case` match never fired
# and generic tools silently passed through on every vault .md file.
#
# Reworked: the hook used to be resolved by a path relative to
# this script's own location (valid when smoke.sh and the hooks shipped
# from the same dotty checkout). Post-cutover, hooks ship from the separate
# estate-hooks@work-lifecycle plugin — this probe was silently broken
# (confirmed live pre-rework: FAIL, hook missing at a path inside
# work-lifecycle's own tree that was never where hooks lived). Resolves the
# hook from the installed estate-hooks cache instead, scoped to a profile
# where settings "hooks" is the literal {} shape (plugin-served).
# ---------------------------------------------------------------------------
probe_hook_tilde_expansion() {
    local name="hook-tilde-expansion"
    local profiles_root="${SMOKE_PROFILES_ROOT_OVERRIDE:-$HOME}"
    local profile_dirs=() d

    for d in "$profiles_root"/.claude-*; do
        [[ -f "$d/settings.json" ]] || continue
        local shape
        shape="$(python3 -c '
import json, sys
try:
    with open(sys.argv[1], "r", encoding="utf-8") as f:
        s = json.load(f)
except Exception:
    print("ERROR"); sys.exit()
print("EMPTY" if s.get("hooks", object()) == {} else "OTHER")
' "$d/settings.json" 2>/dev/null)"
        [[ "$shape" == "EMPTY" ]] && profile_dirs+=("$d")
    done

    # Staleness: no plugin-served profile means nothing live to resolve the
    # hook from — this is itself the failure this probe exists to catch
    # post-cutover, not a condition to skip past.
    if [[ "${#profile_dirs[@]}" -eq 0 ]]; then
        report FAIL "$name" \
            "no \$HOME/.claude-* profile has settings.json \"hooks\":{} (staleness — no plugin-served profile to resolve the hook from)"
        return
    fi

    local profile_dir="${profile_dirs[0]}"
    local installed_path="$profile_dir/plugins/installed_plugins.json"
    if [[ ! -f "$installed_path" ]]; then
        report FAIL "$name" \
            "installed_plugins.json missing at $installed_path (staleness)"
        return
    fi

    local install_path
    install_path="$(python3 -c "$PY_RESOLVE_ESTATE_HOOKS_CACHE" "$installed_path" 2>/dev/null)"

    if [[ -z "$install_path" ]]; then
        report FAIL "$name" \
            "estate-hooks@work-lifecycle installPath unresolved from $installed_path (staleness — the probed surface moved)"
        return
    fi

    local hook="$install_path/hooks/vault-mcp-redirect.sh"

    if [[ ! -x "$hook" ]]; then
        report FAIL "$name" \
            "vault-mcp-redirect.sh missing or not executable at $hook (staleness — the probed surface moved)"
        return
    fi

    # The probed path need not exist — the hook's realpath fallback returns
    # the raw target unchanged when realpath can't resolve it.
    local payload rc_block rc_open
    payload='{"tool_name":"Read","tool_input":{"file_path":"'"$HOME"'/__smoke_fixture__/x.md"}}'

    # Health, block case: tilde-form VAULT_ROOT, single-quoted so THIS shell
    # never expands it — the hook must expand it internally (via its own
    # ${VAULT/#\~/$HOME}) and block (exit 2). If the hook's tilde-expansion
    # regresses, this exit code silently reverts to 0.
    # shellcheck disable=SC2088  # intentional — this probe exists to prove
    # the HOOK expands the tilde; expanding it here would defeat the test.
    printf '%s' "$payload" | VAULT_ROOT='~/__smoke_fixture__' "$hook" >/dev/null 2>&1
    rc_block=$?

    # Inverse control: VAULT_ROOT unset entirely must fail-open (exit 0).
    # Without this control, a hook that always exits 2 (e.g. broken jq
    # detection) would look like a PASS above for the wrong reason.
    printf '%s' "$payload" | env -u VAULT_ROOT "$hook" >/dev/null 2>&1
    rc_open=$?

    if [[ "$rc_block" -eq 2 && "$rc_open" -eq 0 ]]; then
        report PASS "$name" \
            "resolved via $(basename "$profile_dir")'s estate-hooks cache ($install_path); tilde VAULT_ROOT blocked (exit 2); unset VAULT_ROOT fell open (exit 0)"
    else
        report FAIL "$name" \
            "expected block=2/open=0, got block=$rc_block/open=$rc_open — tilde-expansion regression (2026-06-02 class)"
    fi
}

# ---------------------------------------------------------------------------
# Probe 2: lint-suite
#
# Proves lint.py's fixture suite still passes. Regression class: a false-
# green fixture class plus a python-version drift that changed check
# behavior between machines — both caught only by re-running the suite, not
# by reading the script.
# ---------------------------------------------------------------------------
probe_lint_suite() {
    local name="lint-suite"
    local tests_dir="$HOME/Repos/wiki/.claude/skills/lint-knowledge/tests"
    local runner="$tests_dir/run_tests.py"

    # Staleness: the suite this probe runs must still exist at its known path.
    if [[ ! -f "$runner" ]]; then
        report FAIL "$name" \
            "run_tests.py missing at $runner (staleness — the probed surface moved)"
        return
    fi

    local output rc tail_text
    output="$(cd "$tests_dir" && python3 run_tests.py 2>&1)"
    rc=$?

    if [[ "$rc" -eq 0 ]]; then
        report PASS "$name" "run_tests.py exited 0"
    else
        tail_text="$(printf '%s\n' "$output" | tail -n 5 | tr '\n' '|')"
        report FAIL "$name" "run_tests.py exited $rc — tail: $tail_text"
    fi
}

# ---------------------------------------------------------------------------
# Probe 3: hook-registration-integrity
#
# Proves every DECLARED profile (dotty-private's plugins.json — the
# blueprint's declared-plugin state, read here rather than hardcoded so a
# third declared profile is picked up automatically) has settings.json
# "hooks" in the literal {} shape (fully plugin-served, per this ticket's
# deletion of dotty's hook scripts) AND has no registered .sh hook command
# still resolving under ~/bin/dotty/.claude — the failure this guards
# against: a hand-edit or merge mistake reintroducing a path registration
# while dotty's files still physically exist (a transitional-window or
# regression case the plain isfile()+executable check can't catch, since a
# file that legitimately still exists passes it regardless of whether it
# should be registered by path at all).
#
# A $HOME/.claude-* directory that ISN'T one of plugins.json's declared
# profiles (a backup snapshot, the noise ~/.claude/ profile) is reported
# informationally and never gates the probe — mirrors probe 6's existing
# "not applicable" treatment of a non-{} hooks shape.
#
# Regression class (pre-rework): a stale registered hook — a settings.json
# entry pointing at a path that moved or lost its executable bit, invisible
# until the hook silently failed to fire.
# ---------------------------------------------------------------------------
PY_HOOK_CHECK="$(cat <<'PYEOF'
import json, os, sys

DOTTY_PREFIX = os.path.realpath(os.path.expanduser("~/bin/dotty/.claude"))


def registered_sh_commands(hooks_root):
    cmds = []
    if not isinstance(hooks_root, dict):
        return cmds
    for _event, entries in hooks_root.items():
        if not isinstance(entries, list):
            continue
        for entry in entries:
            if not isinstance(entry, dict):
                continue
            for h in entry.get("hooks", []):
                if not isinstance(h, dict):
                    continue
                cmd = h.get("command", "")
                if not cmd:
                    continue
                toks = cmd.split()
                if not toks:
                    continue
                first = toks[0]
                expanded = os.path.expanduser(first) if first.startswith("~") else first
                if expanded.endswith(".sh"):
                    cmds.append(expanded)
    return cmds


def check_declared_profile(path):
    with open(path, "r", encoding="utf-8") as f:
        data = json.load(f)
    hooks_root = data.get("hooks", object())
    cmds = registered_sh_commands(hooks_root if isinstance(hooks_root, dict) else {})
    under_dotty = [
        c for c in cmds
        if os.path.realpath(c) == DOTTY_PREFIX
        or os.path.realpath(c).startswith(DOTTY_PREFIX + os.sep)
    ]
    problems = []
    if hooks_root != {}:
        problems.append('"hooks" is not the literal {} shape')
    if under_dotty:
        problems.append("registered command(s) still point under ~/bin/dotty/.claude: " + ", ".join(under_dotty))
    bad_files = [c for c in cmds if not (os.path.isfile(c) and os.access(c, os.X_OK))]
    if bad_files:
        problems.append("registered .sh missing/non-executable: " + ", ".join(bad_files))
    return problems


args = sys.argv[1:]
sep = args.index("--") if "--" in args else len(args)
strict_paths = args[:sep]
other_paths = args[sep + 1:]

overall_bad = False
for path in strict_paths:
    label = os.path.basename(os.path.dirname(path)).replace(".claude-", "")
    try:
        problems = check_declared_profile(path)
    except Exception as e:
        print(f"BAD\t{label}\tunreadable: {e}")
        overall_bad = True
        continue
    if problems:
        overall_bad = True
        print(f"BAD\t{label}\t" + "; ".join(problems))
    else:
        print(f"OK\t{label}\thooks: {{}} confirmed, no registered .sh under dotty")

for path in other_paths:
    label = os.path.basename(os.path.dirname(path)).replace(".claude-", "")
    print(f"SKIP\t{label}\tnot a plugins.json-declared profile — informational only, not gated")

sys.exit(1 if overall_bad else 0)
PYEOF
)"

probe_hook_registration_integrity() {
    local name="hook-registration-integrity"
    local plugins_state="${SMOKE_PLUGINS_JSON_OVERRIDE:-$HOME/bin/dotty-private/.claude/blueprint/plugins.json}"
    local profiles_root="${SMOKE_PROFILES_ROOT_OVERRIDE:-$HOME}"

    if [[ ! -f "$plugins_state" ]]; then
        report FAIL "$name" \
            "plugins.json missing at $plugins_state (staleness — the blueprint state file moved)"
        return
    fi

    local declared_profiles
    declared_profiles="$(python3 -c '
import json, sys
state = json.load(open(sys.argv[1]))
print(" ".join(sorted(state.keys())))
' "$plugins_state" 2>/dev/null)"

    if [[ -z "$declared_profiles" ]]; then
        report FAIL "$name" \
            "0 profiles declared in plugins.json (parse failure or empty state — never a clean pass)"
        return
    fi

    local strict_paths=() other_paths=() d prof declared_set=" "
    for prof in $declared_profiles; do
        declared_set="$declared_set $prof "
        local p="$profiles_root/.claude-$prof/settings.json"
        [[ -f "$p" ]] && strict_paths+=("$p")
    done

    for d in "$profiles_root"/.claude-*; do
        [[ -f "$d/settings.json" ]] || continue
        local base_prof="${d##*/.claude-}"
        [[ "$declared_set" == *" $base_prof "* ]] && continue
        other_paths+=("$d/settings.json")
    done

    if [[ "${#strict_paths[@]}" -eq 0 ]]; then
        report FAIL "$name" \
            "none of plugins.json's declared profiles ($declared_profiles) has a live settings.json (staleness)"
        return
    fi

    local py_out py_rc
    # Branched, not a nested "${arr[@]+"${arr[@]}"}" guard — bash 3.2
    # (macOS's shipped /bin/bash) raises "unbound variable" under `set -u`
    # when expanding an empty array directly, but the nested-quote guard
    # idiom itself triggers a separate bash 3.2 parser fault when combined
    # with this heredoc's surrounding content. strict_paths is always
    # non-empty here (checked above); only other_paths can legitimately be
    # empty (no non-declared $HOME/.claude-* directories found).
    if [[ "${#other_paths[@]}" -eq 0 ]]; then
        py_out="$(python3 -c "$PY_HOOK_CHECK" "${strict_paths[@]}" -- 2>&1)"
    else
        py_out="$(python3 -c "$PY_HOOK_CHECK" "${strict_paths[@]}" -- "${other_paths[@]}" 2>&1)"
    fi
    py_rc=$?

    local detail_parts=() overall_ok=1 line_status label rest
    while IFS=$'\t' read -r line_status label rest; do
        [[ -z "$line_status" ]] && continue
        if [[ "$line_status" == "OK" || "$line_status" == "SKIP" ]]; then
            detail_parts+=("$label: $rest")
        else
            overall_ok=0
            detail_parts+=("$label: $line_status $rest")
        fi
    done <<<"$py_out"

    # Manual join, not `IFS='; '; "${arr[*]}"` — array-join IFS uses only its
    # FIRST character as the separator, which would silently drop the space.
    local joined="" part
    for part in "${detail_parts[@]}"; do
        [[ -z "$joined" ]] && joined="$part" || joined="$joined; $part"
    done

    if [[ "$py_rc" -eq 0 && "$overall_ok" -eq 1 ]]; then
        report PASS "$name" "$joined"
    else
        report FAIL "$name" "$joined"
    fi
}

# ---------------------------------------------------------------------------
# Probe 4: core-symlink-integrity
#
# Proves every per-entry symlink declared in the core blueprint slice exists,
# is a symlink, and resolves to the declared target — not merely that it
# resolves. Regression class: the 2026-07-18 incidents where a dangling
# agents symlink persisted for two months after its target was deleted, and
# ~/.git pointed at a tree whose content sat one level down, producing 56
# phantom deletions visible to any session under $HOME.
#
# Reworked: the agents surface's declared key never carried the
# ".md" suffix core.sh's own resolve_link_name()/link_suffix() appends when
# WRITING the physical link file — core.json stores the bare key ("attack-
# kitty"), core.sh writes "attack-kitty.md". This probe read the bare key
# straight back with no suffix logic of its own, so any real agents entry
# would have been checked against the wrong filename. Unexercised by live
# state today (agents is declared empty in both profiles, retired by the
# cutover), so proven here against a constructed core.json fixture with a
# fake agent entry, not live state.
# ---------------------------------------------------------------------------
probe_core_symlink_integrity() {
    local name="core-symlink-integrity"
    local state_file="${SMOKE_CORE_JSON_OVERRIDE:-$HOME/bin/dotty-private/.claude/blueprint/core.json}"

    if [[ ! -f "$state_file" ]]; then
        report FAIL "$name" \
            "core.json missing at $state_file (staleness — the blueprint state file moved)"
        return
    fi

    # A parse/structure failure is staleness (report FAIL, never silently
    # treated as "zero entries"); a clean parse with zero entries is a real,
    # expected state since the thin-layer rules/CLAUDE.md move — core.sh
    # dropped the rules surface entirely, and skills/agents are both
    # legitimately {} once every skill and the agent ship from plugins. The
    # two cases share no output shape: STRUCTURE_ERROR only prints on a
    # parse/shape failure, never alongside a real (possibly zero-length)
    # entry list, so bash never has to guess which case it's in.
    local py_out py_rc
    py_out="$(python3 -c '
import json, sys
try:
    with open(sys.argv[1]) as f:
        state = json.load(f)
    if not isinstance(state, dict) or not {"personal", "professional"} <= state.keys():
        raise ValueError("missing personal/professional top-level keys")
    for profile in ("personal", "professional"):
        if not isinstance(state[profile], dict):
            raise ValueError(f"{profile} is not an object")
except Exception as e:
    print(f"STRUCTURE_ERROR\t{e}")
    sys.exit(1)
for profile, surfaces in sorted(state.items()):
    for surface, entries in sorted(surfaces.items()):
        for name, target in sorted(entries.items()):
            print(f"ENTRY\t{profile}\t{surface}\t{name}\t{target}")
' "$state_file")"
    py_rc=$?

    if [[ "$py_rc" -ne 0 ]]; then
        report FAIL "$name" \
            "core.json failed to parse or has an unexpected shape: ${py_out#*$'\t'} (staleness — the declared-state schema moved)"
        return
    fi

    local bad=0 checked=0 issues=""
    while IFS=$'\t' read -r tag profile surface entry_name declared_target; do
        [[ "$tag" != "ENTRY" ]] && continue
        local resolved_name="$entry_name"
        [[ "$surface" == "agents" ]] && resolved_name="${entry_name}.md"
        local expanded_target="${declared_target/#\~/$HOME}"
        local link="$HOME/.claude-$profile/$surface/$resolved_name"
        checked=$((checked + 1))

        if [[ ! -L "$link" ]]; then
            issues="$issues $profile/$surface/$resolved_name(not-a-symlink)"
            bad=$((bad + 1))
        elif [[ "$(readlink "$link")" != "$expanded_target" ]]; then
            issues="$issues $profile/$surface/$resolved_name(wrong-target)"
            bad=$((bad + 1))
        elif [[ ! -e "$link" ]]; then
            issues="$issues $profile/$surface/$resolved_name(dangling)"
            bad=$((bad + 1))
        fi
    done <<<"$py_out"

    if [[ "$bad" -eq 0 ]]; then
        report PASS "$name" "$checked declared symlinks verified"
    else
        report FAIL "$name" "$bad/$checked broken:$issues"
    fi
}

# ---------------------------------------------------------------------------
# Probe 5: plugin-shadow-integrity (was blueprint-coverage)
#
# Proves no profile's own (blueprint-managed) skills/ or agents/ directory
# has a live entry — symlink, dangling symlink, real dir, or file — sharing
# a name with something an enabled, declared plugin already serves. A
# shadow silently wins over the plugin (Claude Code resolves a local entry
# before a plugin one), so an undetected shadow is a skill/agent quietly
# running stale or wrong content with no visible signal.
#
# Reworked: the old check ("every dir in the co-located skills
# tree has a core.json entry in both profiles") was self-referential — it
# compared whichever skills/ directory smoke.sh happened to be installed
# beside against core.json, so running it from a location other than dotty
# (this repo) produced false "undeclared" positives for every packaged
# skill, in both profiles (confirmed live pre-rework: 36 false positives).
# It also inverted the actual post-cutover invariant: dotty's copies no
# longer need core.json entries at all — a profile's managed dirs must be
# EMPTY of plugin-served names, not full of declared ones.
#
# Reads dotty-private's plugins.json (the declared plugin-id list per
# profile) rather than hardcoding work-lifecycle/estate-hooks, so it covers
# any future plugin (e.g. a future wiki/operator plugin) automatically IF
# that plugin packages skills/agents at the same top-level skills/ +
# agents/*.md layout work-lifecycle uses — a design assumption to confirm
# when such a plugin ships, not a guarantee plugins.json itself establishes.
# ---------------------------------------------------------------------------
# Written to a temp file, not captured via "$(cat <<'PYEOF' ... )" like this
# file's other embedded scripts — that pattern reliably makes bash 3.2
# (macOS's shipped /bin/bash) fail this specific block at RUNTIME with
# "bad substitution: no closing `)'", despite `bash -n` reporting clean
# syntax; isolated and reproduced against multiple content variants before
# concluding it's a bash 3.2 parser defect specific to this heredoc's
# length/structure combination, not a content bug. A temp file sidesteps
# heredoc-inside-command-substitution entirely.
PY_SHADOW_CHECK_FILE="$(mktemp -t smoke-shadow-check)"
trap 'rm -f "$PY_SHADOW_CHECK_FILE"' EXIT
cat > "$PY_SHADOW_CHECK_FILE" <<'PYEOF'
import glob
import json
import os
import sys


def load_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def installed_path_for(profile_dir, plugin_id):
    installed_path = os.path.join(profile_dir, "plugins", "installed_plugins.json")
    try:
        installed = load_json(installed_path)
    except Exception:
        return None
    entries = installed.get("plugins", {}).get(plugin_id, [])
    for e in entries:
        if isinstance(e, dict) and e.get("scope") == "user":
            p = e.get("installPath")
            if p and os.path.isdir(p):
                return p
    return None


def skill_dirs(install_path):
    # plugin.json's own "skills" field (a string or array of paths relative
    # to the plugin root, glob patterns included — e.g. ".claude/skills/*")
    # is the authoritative attribution when present; a plugin that packages
    # skills anywhere other than a top-level skills/ dir (a wiki plugin
    # serving from ".claude/skills/*") would otherwise be attributed zero
    # skills by this probe and report a silent, wrong PASS — exactly the
    # failure class this probe exists to catch. Falls back to the default
    # skills/* glob only when the field is absent (work-lifecycle's own
    # plugin.json today: no "skills" key).
    manifest_path = os.path.join(install_path, ".claude-plugin", "plugin.json")
    try:
        manifest = load_json(manifest_path)
    except Exception:
        manifest = {}
    field = manifest.get("skills")
    if field is None:
        patterns = [os.path.join(install_path, "skills", "*")]
    else:
        values = [field] if isinstance(field, str) else (field if isinstance(field, list) else [])
        patterns = [os.path.join(install_path, v) for v in values]
    found = []
    for pattern in patterns:
        for match in glob.glob(pattern):
            base = os.path.basename(match.rstrip("/"))
            if os.path.isdir(match) and not base.startswith((".", "__")):
                found.append(base)
    return found


def served_names(install_path):
    names = set()
    for name in skill_dirs(install_path):
        names.add(("skills", name))
    agents_dir = os.path.join(install_path, "agents")
    if os.path.isdir(agents_dir):
        for fn in os.listdir(agents_dir):
            if fn.endswith(".md"):
                names.add(("agents", fn[:-3]))
    return names


def main():
    plugins_state_path, profiles_root = sys.argv[1], sys.argv[2]
    state = load_json(plugins_state_path)

    checked = 0
    problems = []
    unresolved = []

    for profile, decl in sorted(state.items()):
        profile_dir = os.path.join(profiles_root, f".claude-{profile}")
        plugin_ids = decl.get("plugins", [])
        served = set()
        for pid in plugin_ids:
            ip = installed_path_for(profile_dir, pid)
            if not ip:
                unresolved.append(f"{profile}: plugin {pid} installPath unresolved")
                continue
            served |= served_names(ip)
        for surface, sname in sorted(served):
            checked += 1
            filename = sname if surface == "skills" else sname + ".md"
            live_entry = os.path.join(profile_dir, surface, filename)
            if os.path.lexists(live_entry):
                problems.append(f"{profile}: {surface}/{filename} shadows a plugin-served name")

    # checked == 0 is never a clean pass, whether it's a parse/empty-state
    # failure or every declared plugin's installPath went unresolved (a
    # broken/missing install — unresolved entries must not silently mask
    # this the way "checked == 0 and not unresolved" used to let them).
    if checked == 0:
        for u in unresolved:
            print("FAIL\t" + u)
        if not unresolved:
            print("ERROR\t0 plugin-served names discovered from plugins.json - parse failure or empty declared state")
        sys.exit(1)

    for u in unresolved:
        print("WARN\t" + u)

    if problems:
        for p in problems:
            print("FAIL\t" + p)
        sys.exit(1)

    print(f"OK\t{checked} plugin-served names checked across declared profiles, zero live shadows")
    sys.exit(0)


main()
PYEOF

probe_plugin_shadow_integrity() {
    local name="plugin-shadow-integrity"
    local plugins_state="${SMOKE_PLUGINS_JSON_OVERRIDE:-$HOME/bin/dotty-private/.claude/blueprint/plugins.json}"
    local profiles_root="${SMOKE_PROFILES_ROOT_OVERRIDE:-$HOME}"

    if [[ ! -f "$plugins_state" ]]; then
        report FAIL "$name" \
            "plugins.json missing at $plugins_state (staleness — the blueprint state file moved)"
        return
    fi

    local py_out py_rc
    py_out="$(python3 "$PY_SHADOW_CHECK_FILE" "$plugins_state" "$profiles_root" 2>&1)"
    py_rc=$?

    local detail_parts=() overall_ok=1 line_status rest
    while IFS=$'\t' read -r line_status rest; do
        [[ -z "$line_status" ]] && continue
        if [[ "$line_status" == "OK" || "$line_status" == "WARN" ]]; then
            detail_parts+=("$rest")
        else
            overall_ok=0
            detail_parts+=("$line_status $rest")
        fi
    done <<<"$py_out"

    local joined="" part
    for part in "${detail_parts[@]}"; do
        [[ -z "$joined" ]] && joined="$part" || joined="$joined; $part"
    done

    if [[ "$py_rc" -eq 0 && "$overall_ok" -eq 1 ]]; then
        report PASS "$name" "$joined"
    else
        report FAIL "$name" "$joined"
    fi
}

# ---------------------------------------------------------------------------
# Probe 6: plugin-hook-serving-integrity
#
# Proves that when a profile's settings.json registers no hooks directly
# (hooks: {}), meaning its guards are meant to run from the
# estate-hooks@work-lifecycle plugin, that plugin is actually enabled AND its
# installed cache still serves every hook the plugin declares — cross-checked
# against hooks/manifest.json's "hooks" list (ground truth authored
# alongside the scripts, kept out of plugin.json itself since that file's
# own "hooks" key is reserved by Claude Code for a different shape), not
# against hooks.json alone, which would be self-referential.
# Regression class: 2026-09-02 — a plugin-packaging spike found that
# enabling/disabling a plugin only mutates enabledPlugins in settings.json
# with nothing auditing it — a profile silently disabled would drop all
# nine guard hooks (git-hook-bypass, gh-pr-body, gated-verb, etc.) with zero
# visible signal until an incident proved it missing, the same failure
# shape as every other probe in this file.
#
# Generalizes to any number of profiles: globs $HOME/.claude-* for
# directories that carry a settings.json, rather than hardcoding
# personal/professional as probes 3-4 do.
# ---------------------------------------------------------------------------
PY_PLUGIN_HOOK_CHECK="$(cat <<'PYEOF'
import json, os, sys

PLUGIN_KEY = "estate-hooks@work-lifecycle"


def load_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def registered_sh_basenames(hooks_root):
    names = set()
    if not isinstance(hooks_root, dict):
        return names
    for _event, entries in hooks_root.items():
        if not isinstance(entries, list):
            continue
        for entry in entries:
            if not isinstance(entry, dict):
                continue
            for h in entry.get("hooks", []):
                if not isinstance(h, dict):
                    continue
                cmd = h.get("command", "")
                if not cmd:
                    continue
                toks = cmd.split()
                if not toks:
                    continue
                first = toks[0].strip('"')
                base = os.path.basename(first)
                if base.endswith(".sh"):
                    names.add(base)
    return names


def check_profile(profile_dir):
    label = os.path.basename(profile_dir)
    settings_path = os.path.join(profile_dir, "settings.json")
    try:
        settings = load_json(settings_path)
    except Exception as e:
        return ("FAIL", label, f"settings.json unreadable at {settings_path}: {e} (staleness)")

    # Only a literal hooks: {} means "guards are meant to be plugin-served" —
    # a missing "hooks" key entirely (e.g. a pre-plugin-era profile) is not a
    # shape this probe is designed to reason about, same bucket as a profile
    # with hooks registered directly.
    _absent = object()
    hooks_value = settings.get("hooks", _absent)
    if hooks_value != {}:
        return ("PASS", label,
                 "settings.json \"hooks\" is not the literal {} shape (absent, non-empty, or "
                 "non-dict) — plugin-serving probe not applicable")

    enabled = settings.get("enabledPlugins", {}).get(PLUGIN_KEY)
    if enabled is not True:
        return ("FAIL", label,
                 f'hooks:{{}} (plugin-served) but enabledPlugins["{PLUGIN_KEY}"] is '
                 f"{enabled!r}, not true — guards are silently disabled")

    installed_path = os.path.join(profile_dir, "plugins", "installed_plugins.json")
    try:
        installed = load_json(installed_path)
    except Exception as e:
        return ("FAIL", label,
                 f"installed_plugins.json unreadable at {installed_path}: {e} (staleness)")

    entries = installed.get("plugins", {}).get(PLUGIN_KEY, [])
    user_entries = [e for e in entries if isinstance(e, dict) and e.get("scope") == "user"]
    if not user_entries:
        return ("FAIL", label,
                 f'enabledPlugins["{PLUGIN_KEY}"] is true but installed_plugins.json has no '
                 f"scope:user install entry for it — enabled but not actually installed")

    install_path = user_entries[0].get("installPath")
    if not install_path or not os.path.isdir(install_path):
        return ("FAIL", label, f"installPath missing or not a directory: {install_path}")

    # A "hooks" key in plugin.json ITSELF is reserved by Claude Code for
    # hook-config file paths (must be "./*.json" shapes) — putting the
    # ground-truth script list there collided with that schema and broke
    # `claude plugin validate --strict` (27 errors, caught post-merge). The
    # ground truth lives in a sibling file instead, outside the schema
    # validate --strict inspects.
    manifest_path = os.path.join(install_path, "hooks", "manifest.json")
    try:
        manifest = load_json(manifest_path)
    except Exception as e:
        return ("FAIL", label, f"hooks/manifest.json unreadable at {manifest_path}: {e} (staleness)")

    declared = manifest.get("hooks")
    if not isinstance(declared, list) or not declared:
        return ("FAIL", label,
                 f'hooks/manifest.json at {manifest_path} has no non-empty "hooks" list '
                 "(staleness — ground-truth field missing)")

    hooks_json_path = os.path.join(install_path, "hooks", "hooks.json")
    try:
        hooks_json = load_json(hooks_json_path)
    except Exception as e:
        return ("FAIL", label, f"hooks/hooks.json unreadable at {hooks_json_path}: {e} (staleness)")

    registered = registered_sh_basenames(hooks_json.get("hooks", {}))

    missing_registration = sorted(set(declared) - registered)
    extra_registration = sorted(registered - set(declared))

    missing_files = []
    for fname in declared:
        p = os.path.join(install_path, "hooks", fname)
        if not os.path.isfile(p) or os.path.getsize(p) == 0:
            missing_files.append(fname)

    problems = []
    if missing_registration:
        problems.append("declared in hooks/manifest.json but not registered in hooks.json: "
                         + ", ".join(missing_registration))
    if extra_registration:
        problems.append("registered in hooks.json but not declared in hooks/manifest.json: "
                         + ", ".join(extra_registration))
    if missing_files:
        problems.append("missing or empty in cache hooks/: " + ", ".join(missing_files))

    if problems:
        return ("FAIL", label, f"cache at {install_path} — " + "; ".join(problems))

    return ("PASS", label,
            f"{len(declared)} plugin-declared hooks all registered in hooks.json and present "
            f"non-empty in cache ({install_path})")


def main():
    results = [check_profile(p) for p in sys.argv[1:]]
    overall_ok = all(r[0] == "PASS" for r in results)
    for status, label, detail in results:
        print(f"{status}\t{label}\t{detail}")
    sys.exit(0 if overall_ok else 1)


main()
PYEOF
)"

probe_plugin_hook_serving() {
    local name="plugin-hook-serving-integrity"
    local profile_dirs=() d

    for d in "$HOME"/.claude-*; do
        [[ -f "$d/settings.json" ]] && profile_dirs+=("$d")
    done

    # Staleness: at least one $HOME/.claude-* profile directory with a
    # settings.json must exist, or there is nothing live to check.
    if [[ "${#profile_dirs[@]}" -eq 0 ]]; then
        report FAIL "$name" \
            "no \$HOME/.claude-* directory with a settings.json found (staleness — the probed surface moved)"
        return
    fi

    local py_out py_rc
    py_out="$(python3 -c "$PY_PLUGIN_HOOK_CHECK" "${profile_dirs[@]}")"
    py_rc=$?

    local detail_parts=() overall_ok=1 line_status label rest
    while IFS=$'\t' read -r line_status label rest; do
        [[ -z "$line_status" ]] && continue
        if [[ "$line_status" == "PASS" ]]; then
            detail_parts+=("$label: $rest")
        else
            overall_ok=0
            detail_parts+=("$label: $line_status $rest")
        fi
    done <<<"$py_out"

    local joined="" part
    for part in "${detail_parts[@]}"; do
        [[ -z "$joined" ]] && joined="$part" || joined="$joined; $part"
    done

    if [[ "$py_rc" -eq 0 && "$overall_ok" -eq 1 ]]; then
        report PASS "$name" "$joined"
    else
        report FAIL "$name" "$joined"
    fi
}

# ---------------------------------------------------------------------------
# Probe 7: plugin-enablement-integrity (new — SKILL.md's one declared
# growth-rule exception, added from a named coverage gap rather than an
# incident; see SKILL.md's Identity section for why that's not a silent
# departure from "grows by regression only")
#
# Proves every plugin dotty-private's plugins.json declares, per profile, is
# actually enabled (enabledPlugins[<id>] is true) AND actually installed
# (installed_plugins.json carries a scope:user entry for it) — the
# declared-vs-live check probe 6 already runs for one hardcoded id
# (estate-hooks@work-lifecycle), generalized here across the full declared
# list so a future wiki/operator plugin is covered with no further edit
# to THIS probe (same plugins.json-reading design as probe 5's rework).
#
# Also asserts, once (not per-plugin): both profiles' `plugins` links
# resolve (via readlink) to the same single real directory, and that
# directory is not itself inside a git working tree — the shared plugin
# cache was deliberately moved out of dotty-private's own checkout into
# ~/.local/share/claude-estate/plugins during the cutover specifically so
# that a `git clean`/checkout-reset in dotty-private could never take the
# installed cache both profiles depend on down with it; this assertion is
# what would have caught the cache silently drifting back inside a
# checkout. Bundled into this probe rather than split into an eighth: both
# checks answer the same question ("is the plugin channel fully live and
# structurally sound for every profile"), so one PASS/FAIL name for both is
# more legible than two names for one invariant — a caller reading FAIL
# plugin-enablement-integrity always gets the same next step, "read the
# detail line," regardless of which half tripped.
#
# Regression class this closes: nothing before this rework asserted the
# FULL declared-plugin set is enabled+installed across every profile in one
# place — probe 6 only ever checked estate-hooks; a silently-disabled
# work-lifecycle (or a future wiki/operator) had no probe naming it.
# ---------------------------------------------------------------------------
PY_ENABLEMENT_CHECK="$(cat <<'PYEOF'
import json, os, sys


def load_json(path):
    with open(path, "r", encoding="utf-8") as f:
        return json.load(f)


def main():
    plugins_state_path, profiles_root = sys.argv[1], sys.argv[2]
    state = load_json(plugins_state_path)

    checked = 0
    problems = []

    for profile, decl in sorted(state.items()):
        profile_dir = os.path.join(profiles_root, f".claude-{profile}")
        settings_path = os.path.join(profile_dir, "settings.json")
        try:
            settings = load_json(settings_path)
        except Exception as e:
            problems.append(f"{profile}: settings.json unreadable: {e}")
            continue
        installed_path = os.path.join(profile_dir, "plugins", "installed_plugins.json")
        try:
            installed = load_json(installed_path)
        except Exception as e:
            problems.append(f"{profile}: installed_plugins.json unreadable: {e}")
            continue

        enabled_map = settings.get("enabledPlugins", {})
        for pid in decl.get("plugins", []):
            checked += 1
            if enabled_map.get(pid) is not True:
                problems.append(f"{profile}: {pid} enabledPlugins is {enabled_map.get(pid)!r}, not true")
                continue
            entries = installed.get("plugins", {}).get(pid, [])
            user_entries = [e for e in entries if isinstance(e, dict) and e.get("scope") == "user"]
            if not user_entries:
                problems.append(f"{profile}: {pid} enabled but installed_plugins.json has no scope:user entry")

    if checked == 0:
        print("ERROR\t0 declared plugins checked (parse failure or empty declared state — never a clean pass)")
        sys.exit(1)

    if problems:
        for p in problems:
            print("FAIL\t" + p)
        sys.exit(1)

    print(f"OK\t{checked} declared-plugin enablement checks passed across declared profiles")
    sys.exit(0)


main()
PYEOF
)"

probe_plugin_enablement_integrity() {
    local name="plugin-enablement-integrity"
    local plugins_state="${SMOKE_PLUGINS_JSON_OVERRIDE:-$HOME/bin/dotty-private/.claude/blueprint/plugins.json}"
    local profiles_root="${SMOKE_PROFILES_ROOT_OVERRIDE:-$HOME}"

    if [[ ! -f "$plugins_state" ]]; then
        report FAIL "$name" \
            "plugins.json missing at $plugins_state (staleness — the blueprint state file moved)"
        return
    fi

    local py_out py_rc
    py_out="$(python3 -c "$PY_ENABLEMENT_CHECK" "$plugins_state" "$profiles_root" 2>&1)"
    py_rc=$?

    local detail_parts=() overall_ok=1 line_status rest
    while IFS=$'\t' read -r line_status rest; do
        [[ -z "$line_status" ]] && continue
        if [[ "$line_status" == "OK" ]]; then
            detail_parts+=("$rest")
        else
            overall_ok=0
            detail_parts+=("$line_status $rest")
        fi
    done <<<"$py_out"

    # The shared-cache symlink check runs once, not per plugin — both
    # profiles must point at the same real directory outside any checkout.
    local personal_link="${SMOKE_PROFILES_ROOT_OVERRIDE:-$HOME}/.claude-personal/plugins"
    local professional_link="${SMOKE_PROFILES_ROOT_OVERRIDE:-$HOME}/.claude-professional/plugins"
    local personal_target="" professional_target="" symlink_problem=""

    if [[ -L "$personal_link" ]]; then personal_target="$(readlink "$personal_link")"; fi
    if [[ -L "$professional_link" ]]; then professional_target="$(readlink "$professional_link")"; fi

    if [[ -z "$personal_target" || -z "$professional_target" ]]; then
        symlink_problem="one or both of $personal_link / $professional_link is not a symlink"
    elif [[ "$personal_target" != "$professional_target" ]]; then
        symlink_problem="plugins links diverge: $personal_target vs $professional_target"
    elif [[ ! -d "$personal_target" ]]; then
        symlink_problem="shared target $personal_target is not a real directory"
    elif git -C "$personal_target" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
        symlink_problem="shared target $personal_target is inside a git working tree"
    fi

    if [[ -n "$symlink_problem" ]]; then
        overall_ok=0
        detail_parts+=("shared plugins dir: $symlink_problem")
    else
        detail_parts+=("shared plugins dir: $personal_target (real, outside any git working tree, both profiles agree)")
    fi

    local joined="" part
    for part in "${detail_parts[@]}"; do
        [[ -z "$joined" ]] && joined="$part" || joined="$joined; $part"
    done

    if [[ "$py_rc" -eq 0 && "$overall_ok" -eq 1 ]]; then
        report PASS "$name" "$joined"
    else
        report FAIL "$name" "$joined"
    fi
}

# ---------------------------------------------------------------------------
# Probe 8: rules-claude-md-integrity (new — SKILL.md's second declared
# growth-rule exception. Not an incident either: the thin-layer rules/
# CLAUDE.md move is itself the map-ruled justification, the same footing
# probe 7 stands on — a HITL-approved ticket's own Done When named this
# probe before it existed, which is what licenses an eighth probe without a
# prior silent-misconfiguration bite.)
#
# Proves both always-on-rule and global-CLAUDE.md artifacts, in both
# profiles, are real installed files matching their declared source — not
# merely present. Two failure classes this closes: (a) either file reverting
# to a symlink/`@`-import (the exact live-checkout-dependency this move
# retired — an older or mid-rebase dotty/dotty-private checkout would again
# silently change what a session loads), and (b) either file drifting from
# its declared source without anyone noticing (the blueprint's `capture`
# verb already reports this per-slice; this probe is the same check folded
# into the one place a session actually runs before trusting its own inputs).
# ---------------------------------------------------------------------------
PY_RULES_CLAUDE_MD_CHECK="$(cat <<'PYEOF'
import hashlib
import json
import os
import subprocess
import sys


def sha256_of(path):
    try:
        with open(path, "rb") as f:
            return hashlib.sha256(f.read()).hexdigest()
    except Exception:
        return None


def main():
    profiles_root, dotty_repo, blueprint_dir = sys.argv[1], sys.argv[2], sys.argv[3]

    pin_path = f"{blueprint_dir}/ways-of-working.json"
    try:
        with open(pin_path, "r", encoding="utf-8") as f:
            pin = json.load(f)
    except Exception as e:
        print(f"ERROR\tways-of-working.json unreadable at {pin_path}: {e}")
        sys.exit(1)

    tag, rel_path, want_sha = pin.get("tag"), pin.get("path"), pin.get("sha256")
    try:
        pinned_content = subprocess.run(
            ["git", "-C", dotty_repo, "show", f"{tag}:{rel_path}"],
            capture_output=True, check=True,
        ).stdout
    except Exception as e:
        print(f"ERROR\tcould not resolve {tag}:{rel_path} in {dotty_repo}: {e}")
        sys.exit(1)
    pinned_sha = hashlib.sha256(pinned_content).hexdigest()
    if pinned_sha != want_sha:
        print(f"FAIL\tpinned tag content sha256 {pinned_sha} does not match declared {want_sha} in {pin_path}")

    claude_md_declared = f"{blueprint_dir}/../CLAUDE.md"
    claude_md_sha = sha256_of(claude_md_declared)
    if claude_md_sha is None:
        print(f"ERROR\tdeclared CLAUDE.md unreadable at {claude_md_declared}")
        sys.exit(1)

    checked = 0
    for profile in ("personal", "professional"):
        for label, installed_path, want in (
            ("rules/ways-of-working.md", f"{profiles_root}/.claude-{profile}/rules/ways-of-working.md", want_sha),
            ("CLAUDE.md", f"{profiles_root}/.claude-{profile}/CLAUDE.md", claude_md_sha),
        ):
            checked += 1
            if os.path.islink(installed_path):
                print(f"FAIL\t{profile}/{label} is a symlink (readlink {os.readlink(installed_path)}), not a real file")
                continue
            have = sha256_of(installed_path)
            if have is None:
                print(f"FAIL\t{profile}/{label} missing or unreadable at {installed_path}")
            elif have != want:
                print(f"FAIL\t{profile}/{label} sha256 {have} does not match declared {want}")

    if checked == 0:
        print("ERROR\t0 files checked (never a clean pass)")
        sys.exit(1)
    sys.exit(0)


main()
PYEOF
)"

probe_rules_claude_md_integrity() {
    local name="rules-claude-md-integrity"
    local profiles_root="${SMOKE_PROFILES_ROOT_OVERRIDE:-$HOME}"
    local dotty_repo="${SMOKE_DOTTY_REPO_OVERRIDE:-$HOME/bin/dotty}"
    local blueprint_dir="${SMOKE_BLUEPRINT_DIR_OVERRIDE:-$HOME/bin/dotty-private/.claude/blueprint}"

    if [[ ! -f "$blueprint_dir/ways-of-working.json" ]]; then
        report FAIL "$name" \
            "ways-of-working.json missing at $blueprint_dir (staleness — the blueprint slice moved)"
        return
    fi

    local py_out
    py_out="$(python3 -c "$PY_RULES_CLAUDE_MD_CHECK" "$profiles_root" "$dotty_repo" "$blueprint_dir" 2>&1)"
    local py_rc=$?

    local detail_parts=() overall_ok=1 line_status rest
    while IFS=$'\t' read -r line_status rest; do
        [[ -z "$line_status" ]] && continue
        if [[ "$line_status" == "OK" ]]; then
            detail_parts+=("$rest")
        else
            overall_ok=0
            detail_parts+=("$line_status $rest")
        fi
    done <<<"$py_out"

    local joined="" part
    for part in "${detail_parts[@]}"; do
        [[ -z "$joined" ]] && joined="$part" || joined="$joined; $part"
    done
    [[ -z "$joined" ]] && joined="4 files checked in each of 2 profiles, all matched declared source"

    if [[ "$py_rc" -eq 0 && "$overall_ok" -eq 1 ]]; then
        report PASS "$name" "$joined"
    else
        report FAIL "$name" "$joined"
    fi
}

# ---------------------------------------------------------------------------
# Run all probes, print results, summarize, exit.
# ---------------------------------------------------------------------------
probe_hook_tilde_expansion
probe_lint_suite
probe_hook_registration_integrity
probe_core_symlink_integrity
probe_plugin_shadow_integrity
probe_plugin_hook_serving
probe_plugin_enablement_integrity
probe_rules_claude_md_integrity

for line in "${RESULT_LINES[@]}"; do
    printf '%s\n' "$line"
done

TOTAL="${#RESULT_LINES[@]}"
PASS_COUNT=$((TOTAL - FAIL_COUNT))
if [[ "$FAIL_COUNT" -eq 0 ]]; then
    printf 'SUMMARY: %d/%d probes passed\n' "$PASS_COUNT" "$TOTAL"
else
    printf 'SUMMARY: %d/%d probes passed, %d failed\n' "$PASS_COUNT" "$TOTAL" "$FAIL_COUNT"
fi

[[ "$FAIL_COUNT" -eq 0 ]]
