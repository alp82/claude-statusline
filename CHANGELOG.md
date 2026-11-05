# Changelog

Notable changes, newest first. Dates instead of versions: the install one-liner
always serves `main`, so a date names a state of `main` better than a version
number would.

## 2026-11-05

### Fixed

- Calculate budget percentages after converting each amount's currency scale,
  so spending 50 of a 100 cap shows 50% even when the exponents differ.
- Reject non-integer currency exponents or values outside 0–12 before scaling,
  allowing malformed budgets to fall back without stalling the statusline.
- Show the assumed UTC monthly pace and reset countdown for `.spend` budgets
  even when the older `.extra_usage` object is absent.

### Changed

- Drop the budget's monthly flag: every budget is now taken to run by calendar
  month, so the flag was always set and its check did nothing.

## 2026-10-31

### Added

- **A usage budget replaces the 5h/7d bars on pay-per-token orgs.** Where the
  usage payload has no 5h or 7d window but does carry a spend cap, the second
  row shows a budget segment instead: the currency symbol (`$`, `€`, `£`, or
  the ISO code), a bar, the percentage, spend against the cap in whole units,
  and a `↻` countdown. The numbers come from `.spend`, falling back to the
  older `.extra_usage`; a source whose numbers are missing or out of range
  falls through to the next instead of breaking the row. A personal plan's
  disabled, uncapped budget stays hidden, and so does a plan's own overage
  cap. The payload carries no reset time, so a monthly budget is taken to run
  by calendar month in UTC, which gives it the same pace row and countdown as
  the 5h/7d bars.

## 2026-09-02

### Added

- **The landing page is built by Jekyll, so a fork serves its own URLs.**
  `docs/.nojekyll` is gone and `docs/index.html` has front matter: GitHub Pages
  now renders the page instead of copying it, and every repository reference in
  it — the links, the two install one-liners, the uninstall one, the by-hand
  `raw.githubusercontent` fetches — is derived from the one repository name the
  build knows, rather than a name written into the file. A fork's page
  therefore installs the fork's scripts: the commands carry `--repo <that
  fork>`, the raw URLs use `HEAD` so they follow whatever branch that
  repository calls default, and a line in the sidebar and the footer says which
  repository it is a fork of. `docs/Gemfile` pins the `github-pages` gem so a
  build that is not GitHub Pages resolves the same toolchain.

## 2026-08-31

### Changed

- **The Fable meter is two columns instead of a bar.** The 10-cell stacked bar
  gave way to a vertical meter: two block-glyph heights (`▁▂▃▄▅▆▇█`, in
  eighths), usage first, pace-colored like the stacked bar's top row, beside
  the window-time height in blue, both on the dark track. The Fable window is
  secondary, so it gets a glance instead of a track — and the second row gets
  eight cells back. The colored percentage still carries the exact number.
  Mirrored in `docs/index.html` and `remotion/`; a two-cell meter holds no
  race, so story 04 lost its annotation and its crop shrank to the plain
  height. `loop-fable` and `loop-whole-line` re-rendered; the landing page and
  README prose follow the meter.

## 2026-08-24

### Added

- **The statusline is two rows.** The first row is the checkout and what has
  changed in it. The second row is the model, the effort, and the four bars.
  Claude Code prints one row per line of output.
- **What changed in the working tree, on the first row.** How many files
  changed by kind — `1 add 3 mod 1 del 2 ?` — then the lines added and removed
  against the last commit, `+182 -47`. The count carries the weight and the
  color; the label stays gray. Staged and unstaged both count. A kind with no
  files is left out, so ordinary edits read `3 mod` and a clean tree shows the
  directory alone. The counts cost two `git` calls per render.
- **The first row is laid out space-between.** The checkout sits on the left
  and what changed is pushed right, so its edge lines up with the end of the
  second row. The script measures the second row to find that column, and
  stops at the terminal edge when the second row is wider than the terminal.
- **A blank row between the two.** One terminal row is the smallest unit of
  vertical space there is.
- **The line refreshes on a timer.** The installer sets
  `statusLine.refreshInterval` to 5 seconds. Events alone leave the file and
  line counts stale while a subagent writes to the tree during an idle
  session, and they keep the `↻` countdowns from moving.
- **The reasoning effort, next to the model.** The line now reads
  `★ Opus 5 1M · high`. The five levels the CLI reports are shortened to `low`,
  `med`, `high`, `xhi` and `max`, and a model with no effort setting shows the
  name alone.
- Each agent-panel row carries the same pair, between its token count and its
  description. On a narrow panel, the effort column drops first and the model
  column second, so the description keeps its room.

### Changed

- **The README and the landing page follow the two rows.** "The start of the
  line" is now "Repo and git state" and covers the folder, the branch, and what
  changed in the tree; "What is on the line" is now "Context and limits". The
  Fable window moves ahead of both. The landing page's docked mockup draws both
  rows, drops the typed narration above the prompt, and boxes the prompt the way
  Claude Code does.
- **The rendered loops follow too.** `loop-line-start` is now the whole first
  row: the folder and the branch hold still while the working-tree counts fill
  up on the right, until a commit empties them. The mockup grew a `git` segment
  and a space-between layout to draw it. Every other loop re-rendered
  byte-identical.
- **Model names are shortened.** A leading `Claude ` is dropped and
  ` (1M context)` becomes ` 1M`, so `Opus 5 (1M context)` reads `Opus 5 1M`.
  The panel derives the same name from the model id the CLI sends there.
- **Long directory and branch names are truncated.** The two share whatever
  the first row has left after the file and line groups. Claude Code passes
  the terminal width in `COLUMNS` (v2.1.153 or later); without it the budget
  is a fixed 64 columns minus the groups, and it never falls below 24.
  `STATUSLINE_LOC_MAX` overrides both. While both fit, neither is
  shortened. When they do not fit, the branch loses its namespace first, then
  its tail, then the directory is cut. Cuts land on word boundaries.
- **The agent panel is drawn on a grid.** Every field is a column. The script
  reads the whole payload first, measures the name, model, and effort columns
  across all the rows, and pads to them, so the bars, numbers, and descriptions
  line up whatever the agent names are. A column is dropped for every row at
  once, never for one row alone. Both mockups measure the same widths.
- The agent-panel loop is rendered wider (1680px) to hold the two new fields,
  and its crop on the landing page is wide for the same reason.
- **Story 05 has room for the whole first row.** The loop's checkout is now
  `statusline ⎇ main` rather than `claude-statusline ⎇ two-row-layout`, which
  halves the location to 17 cells, and the crop on the landing page is wide
  like the whole-line and agent-panel crops. The row no longer runs off the
  edge of its box. The rendered loop keeps its 1760px canvas and spends the
  cells the shorter names free on type size instead: 30px to 38px.
- **The walkthrough is re-cut.** The agent panel moves up to 03. A new 04,
  "The start of the line", shows the folder, branch, model, and effort as a
  loop: a branch name grows until it no longer fits, is cut, and then the
  folder is cut too as the model and effort change. "When a window resets" is
  gone. The Fable section shows the same turnover, and the fact that section
  carried - both halves drop to zero and the countdown restarts - now sits in
  01. Each section is down to a line or two, and the loops show the rest. The
  README follows the same order. `loop-reset` is no longer rendered. Its files
  stay in `docs/assets/`, where a frozen prototype still points at them.

### Fixed

- A non-object `effort` in the statusline JSON no longer takes the whole line
  down with it, and a model display name starting with `-` is no longer eaten
  as an `echo` flag.
- `STATUSLINE_LOC_MAX` is checked before it reaches an arithmetic context, so a
  typo can neither disable trimming with an error nor evaluate as an
  expression.
- The location budget is spent in full when the branch is short or absent, and
  it counts the worktree glyph `⎇+`, which is a column wider than `⎇`.
- The panel survives a non-integer `columns` (a failed arithmetic assignment
  used to abort the script and blank the panel), skips a task with no id
  instead of shifting every field by one, keeps the effort label for an agent
  whose model is unknown, and no longer reserves description room on a row that
  has no description.
- The model id parser reads `claude-3-opus-…` as `Opus 3` rather than
  `Opus 20240229`, and keeps a two-digit minor version.
- Widths are counted in terminal columns, not characters: a CJK or emoji name
  takes two columns per glyph, which the budget and the panel's columns now
  spend correctly. Under a non-UTF-8 locale, where bash counts bytes, a
  non-ASCII name is left whole rather than cut mid-sequence.
- An empty payload no longer writes a `jq` error to stderr.

## 2026-08-22

### Changed

- The install prompt now reads "Install or update the statusline …", and the
  README and landing page say plainly that the same prompt does both: paste it
  the first time to install, paste it again for the latest version. The
  installer's `--help` says the same.

## 2026-08-14

### Added

- **Per-agent context bars.** A second script, `subagent-statusline.sh`, renders
  the rows in the agent panel below the prompt. Each running subagent gets its
  own context bar, percentage, and token count in the same palette as the main
  line. Needs Claude Code v2.1.205 or later. The installer now ships both
  scripts and wires both settings entries.
- Section 06 on the landing page shows the panel as a live loop, and the
  `remotion/` sub-project renders the same loop to `docs/assets/loop-agents.gif`.

## 2026-07-30

### Added

- A linked git worktree shows an amber `⎇+` instead of `⎇`.

### Changed

- The top row of each stacked bar is colored by pace (usage against elapsed
  time), not by usage alone. Green means quota to spare, yellow means on pace,
  red means the window runs out early.

## 2026-07-28

### Added

- The rendered loops carry the race annotation: the racers named, the gap read
  out, and the effort row under the burn loop.

## 2026-07-27

### Changed

- The `Ctx` segment shows the token count in thousands next to the percentage.
- The Fable segment drops its `↻` countdown. It resets with the 7-day window,
  which already shows that time.

## 2026-07-26

### Added

- macOS support: BSD `stat`, BSD `date`, and the OAuth token from the Keychain.
- `--uninstall` for the installer, with backups for everything it removes.

## 2026-07-25

### Added

- The one-liner installer at `docs/install.sh`.
- The landing page at [alp82.github.io/claude-statusline](https://alp82.github.io/claude-statusline/).
- The `remotion/` sub-project that renders the animated loops.

## 2026-07-21

### Added

- `statusline.sh`: directory and branch, model, context bar, and the stacked
  5-hour, 7-day, and Fable limit bars.
