Operator-owned Claude Code plugin marketplace for the estate's harness, currently a spike: `estate-hooks` packages the eight hook scripts that dotty registers in its settings file, to prove or refute that plugins can carry the harness before anything is packaged for real. Plugins live under `plugins/`; the marketplace manifest is `.claude-plugin/marketplace.json`.

## Installation

Add the marketplace, then install and enable the plugin in the profile that should run it:

```
claude plugin marketplace add lexijamesesq/work-lifecycle
claude plugin install estate-hooks@work-lifecycle
claude plugin enable estate-hooks@work-lifecycle
```

The plugin ships `defaultEnabled: false` on purpose: plugin install state is shared across Claude Code profiles on one machine, and each profile opts in with `plugin enable`.

## What's Included

| Artifact | What it does |
|---|---|
| `estate-hooks` | Eight hook scripts plus a shared gitleaks helper, registered through `hooks/hooks.json`. |
| `spike-probe` | Throwaway probe for the spike: one SessionStart hook that records its environment and stdin, one marker skill. Removed when the spike closes. |

## Security

Review skills before installing. They load into Claude's context and execute with your permissions. Audit the contents of `plugins/*/hooks/` and `plugins/*/skills/` before use.

Every hook here is a guard or a session bootstrap that runs on tool calls and session start. The guards are tool-scoped and porous to a plain shell, defense-in-depth rather than a boundary.

## License

MIT. See [LICENSE](LICENSE).
