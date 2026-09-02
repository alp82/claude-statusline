# claude-statusline

A single-file Bash statusline for Claude Code (`statusline.sh`).

Settings live in `~/.statuslinerc` (override the path with `$STATUSLINE_RC`), sourced by both scripts before anything else; a variable already set in the environment wins, which the scripts do by saving the known keys with `declare -p` and re-applying them after the source. `COMPACT` is the comma-separated list of gauges drawn as the vertical meter rather than a 10-cell bar — `ctx`, `5h`, `7d`, `fable`, default `fable` — and `meter()` in `statusline.sh` is the single place that choice is made. The mockups have no rc to read: `docs/index.html` and `remotion/` draw the default, so a change to what the default looks like still has to be mirrored there.

`subagent-statusline.sh` renders the per-subagent rows in the agent panel (the `subagentStatusLine` setting). It copies the palette, the context thresholds, the bar geometry, the effort labels, `vglyph`, and the display-width helpers (`vis_len`, `vis_cut`, `wide`) from `statusline.sh` — change one, change the other. It reads `COMPACT` too: `ctx` in the list folds its context bar to one glyph, and `CTX_CELLS` carries that width through the grid. It shortens model names too, but from the model id the panel sends rather than from a display name. The agent panel is drawn three times: by the script, by `agentPanel()` in `docs/index.html` (story 03), and by `remotion/src/statusline/AgentPanel.tsx` (the `agents` story renders `docs/assets/loop-agents.gif`). All three draw the rows on one grid: every variable-width column — name, model, effort — is measured across all the rows and padded to that width. The story's ramps and turnover live in both `docs/index.html` and `remotion/src/stories.ts` — change one, change the other.

`remotion/` is a separate npm sub-project (React + Remotion, `node_modules` gitignored) that rebuilds the statusline as an animatable terminal mockup for the landing page and README. `statusline.sh` is the source of truth for its palette, thresholds and bar geometry — change one, change the other.

The location budget - how a long folder or branch name is shortened - is implemented three times: `statusline.sh`, `fitLocation()` in `docs/index.html`, and `fitLocation()` in `remotion/src/statusline/segments.ts`. The ladder is the same in all three - change one, change the others - but the budget it spends is not. The script derives it from the terminal, sizing the first row against `COLUMNS` minus the file and line groups. The two mockups draw on a fixed canvas with no terminal to ask, so both hold `LOC_MAX` at 34, which is what the elision loop was authored against.

The first row is space-between: the folder and the branch on the left, what changed in the tree pushed right so that its edge lands on the second row's last column. The script pads with spaces to that column, `docs/index.html` gives the two rows one width and lets flex do it, and `remotion/src/statusline/segments.ts` spreads over a fixed cell count (`spreadTo`). What the row shows - the file kinds, their colours, the two-space gap between them - is written in all three. Change one, change the others.

The docked line's working-tree state (`DEFAULTS` in `docs/index.html`) and the `line-start` loop's opening state (`OWN_TREE` in `remotion/src/stories.ts`) are the same numbers on purpose. Change one, change the other.

The annotation over a bar — the racers named, the gap read out, the effort row — is drawn twice: by `annotate()` in `docs/index.html` and by `remotion/src/statusline/Annotation.tsx`. The page measures the painted bar, the render computes it from `theme.ts`, and both carry the same pixel constants. Change one, change the other.

## Update guide

For every day where changes are made, update CHANGELOG.md.

## Agent skills

### Issue tracker

Issues live in this repo's GitHub Issues (`alp82/claude-statusline`), via the `gh` CLI. See `docs/agents/issue-tracker.md`.

### Triage labels

The five canonical triage roles, each label string equal to its name. See `docs/agents/triage-labels.md`.

### Domain docs

Single-context — `CONTEXT.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
