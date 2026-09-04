# Developing a plugin in this repo

## The problem

`claude --plugin-dir <path>` loads a plugin from a local directory for one
session — the obvious way to iterate on a skill without publishing a
release first. But if the *same-named* plugin is also installed from the
marketplace and enabled, the installed copy wins. Editing your local
checkout does nothing visible: every session still resolves the skill body
from the cached, published copy.

Concretely, on this repo: `core@core` (marketplace,
installed+enabled) always shadows `--plugin-dir
plugins/core` pointed at the same content, even in the same
session that passes both.

## The loop

Two things have to both be true for `--plugin-dir` to actually serve your
local edits:

1. **Nothing else claims the plugin's name first.** No marketplace
   install of the same plugin (`core@core`) enabled in
   this profile. Uninstall or disable the marketplace copy for the
   profile you're testing in.
2. **The `--plugin-dir` copy is itself enabled.** `--plugin-dir` registers
   the plugin under a synthetic `<name>@inline` id — a *different* id than
   its marketplace one — and it is still subject to the plugin's own
   `defaultEnabled` (this repo's plugins default to `false`). Loading it
   with `--plugin-dir` alone is not enough; it shows up `disabled` until
   you enable that session id explicitly:

   ```
   claude --plugin-dir plugins/core plugin enable core@inline
   ```

   This writes `"core@inline": true` to the profile's
   `settings.json` `enabledPlugins` — a persistent, profile-scoped
   enable, not a one-shot session flag, and the same generic `@inline` key
   any `--plugin-dir` plugin uses regardless of which directory you point
   it at. Disable it the same way when you're done
   (`claude --plugin-dir <path> plugin disable <name>@inline`) and remove
   the leftover `enabledPlugins` key by hand if it lingers — nothing
   currently prunes it automatically.

With both conditions met, `claude --plugin-dir plugins/core -p
"..."` resolves skills from your local checkout, live — no reinstall, no
publish, no cache refresh.

## Proven

Verified end-to-end in a real profile (2026-09-03): a marker line added to
a local checkout of `smoke/SKILL.md`, never committed, was invisible to a
normal session (reading the installed cache) and to a `--plugin-dir`
session that hadn't been separately enabled (shadowed by the disabled
default state), and became visible only once the marketplace copy was
uninstalled *and* `<name>@inline` was explicitly enabled. Every step was
reverted after the check; the profile used for the proof was confirmed
byte-for-byte back to its starting `enabledPlugins`.
