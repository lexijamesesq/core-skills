Operator-owned Claude Code plugin marketplace for the estate's harness: `work-lifecycle` (skills and the agent) and `estate-hooks` (lifecycle hooks). Both plugins install from this one marketplace; dotty (the public dotfiles repo this replaces the harness portion of) points here rather than carrying the content itself. Plugins live under `plugins/`; the marketplace manifest is `.claude-plugin/marketplace.json`.

## Installation

Add the marketplace, then install and enable the plugins in the profile that should run them:

```
claude plugin marketplace add lexijamesesq/work-lifecycle
claude plugin install work-lifecycle@work-lifecycle
claude plugin enable work-lifecycle@work-lifecycle
claude plugin install estate-hooks@work-lifecycle
claude plugin enable estate-hooks@work-lifecycle
```

Plugin install state is shared across Claude Code profiles on one machine; each profile opts in with `plugin enable`. This is normally driven by the estate's own blueprint (`dotty-private`'s `plugins` slice), not run by hand.

## What's Included

### Skills (`work-lifecycle` plugin)

#### Session orchestration

Bracket a working session — load state at the start, write it back at the end.

| Artifact | Type | What it does |
|----------|------|--------------|
| `/session-start` | Skill | Loads project state, recent progress, and the pending backlog |
| `/session-closeout` | Skill | Writes state back, records what changed |
| `/project-state` | Skill | Reads and writes the Project State section of a project's CLAUDE.md |

#### Projects and backlog

| Artifact | Type | What it does |
|----------|------|--------------|
| `/linear` | Skill | Protocol reference for Linear operations — ticket creation, claiming, state transitions, and structured comment formats |

#### Publishing and quality

Checks that run before anything leaves the machine.

| Artifact | Type | What it does |
|----------|------|--------------|
| `/publish` | Skill | Runs every check a repo must pass before it ships — scans, conformance, review |
| `/house-qa` | Skill + Script | Judges whether a new file reads like it belongs beside the ones already there |
| `/github-readme` | Skill | Writes or refreshes a README for a skill, agent, rule, or project |
| `/release-dotty` | Skill + Script | Cuts dotty's own calendar-versioned release and bumps every consumer's pin to it, as one local, operator-invoked act |
| `/sample-universe` | Skill | Supplies the fictional company that public examples borrow their names from |

#### Authoring and machine state

| Artifact | Type | What it does |
|----------|------|--------------|
| `/grilling` | Skill | Interviews the operator one question at a time to stress-test a plan or decision — looks up facts instead of asking, puts decisions to them with a recommendation, and holds off acting until they agree |
| `/domain-modeling` | Skill | Builds and sharpens a project's domain model — challenges fuzzy terminology, stress-tests edge cases, and records architectural decisions |
| `/smoke` | Skill | Makes each layer of local config prove it's still wired — hooks fire, lint runs, registered paths exist |

#### Research and delegation

| Artifact | Type | What it does |
|----------|------|--------------|
| `/research` | Skill | Classifies a search task (exploratory vs lookup), runs the right retrieval strategy, and knows when to stop |
| `/dispatch` | Skill | Pre-spawn gate — decides whether to delegate, what shape the execution takes, and equips each delegate's brief. Enforces a depth model: L0 orchestrators, L1 discipline teammates, L2 leaf subagents |
| `/wayfinder` | Skill | Charts a loose idea as a map of decision tickets on Linear, resolves them with the operator, then builds from the operator-confirmed Destination and Done When through validated slices |
| `/prototype` | Skill | Builds a throwaway prototype to answer a design question — the decision lands on the ticket; the code stays disposable |

### Agents (`work-lifecycle` plugin)

Domain-specific agents — spawned by skills, never invoked directly. Each owns a narrow surface and carries its own tools, model tier, and refusal walls.

Lifecycle transitions (claim, park, block, un-park, cancel, mark_done, resolve, close-map) are not an agent: they are the `/traffic-cone` skill and the `traffic-cone` script, run in-process by the caller. The `@traffic-cone` name in skill text refers to that transition law, not to a spawnable agent.

| Artifact | Type | What it does |
|----------|------|--------------|
| `@attack-kitty` | Agent | Non-author verification — receives a typed mandate, fetches its own evidence, judges independently, and posts or returns a verdict. Twelve mandate types covering gate checks, formal verification, and thinking aids. Mandate authority enforcement: gate mandates require L0 callers; thinking-aid mandates are available at any depth |

### Hooks (`estate-hooks` plugin)

Claude Code lifecycle hooks.

| Hook | Event | What it does |
|------|-------|--------------|
| `session-init.sh` | SessionStart | Runs session initialization tasks |
| `fix-obsidian-claude-sync.sh` | SessionStart | Works around Obsidian Sync skipping dot-prefixed directories |
| `vault-mcp-redirect.sh` | PreToolUse | Sends vault file edits through the Obsidian MCP tools |
| `gh-pr-body-guard.sh` | PreToolUse | Scans a PR title and body for secrets, and fails closed |
| `git-hook-bypass-guard.sh` | PreToolUse | Blocks `--no-verify` and other attempts to skip the git hooks |
| `pr-cache.sh` | SessionStart, PostToolUse | Caches PR metadata to cut redundant API calls |

## CI and releases

See [`.github/CI.md`](.github/CI.md) for this repo's CI shape and the decisions specific to it — including the release job that tags and publishes each plugin.

## Security

Review skills before installing. They load into Claude's context and execute with your permissions. Audit the contents of `plugins/work-lifecycle/skills/`, `plugins/work-lifecycle/agents/`, and `plugins/estate-hooks/hooks/` before use.

Every hook here is a guard or a session bootstrap that runs on tool calls and session start. The guards are tool-scoped and porous to a plain shell, defense-in-depth rather than a boundary.

## License

MIT. See [LICENSE](LICENSE).
