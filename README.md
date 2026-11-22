<div align="center">

# claude-statusline

## Are you spending faster than the clock?

[![Stars, Forks, Open Issues and License](https://shieldcn.dev/group/github/stars/alp82/claude-statusline+github/forks/alp82/claude-statusline+github/open-issues/alp82/claude-statusline+github/license/alp82/claude-statusline.svg?variant=secondary)](https://github.com/alp82/claude-statusline)

[![Claude Code](https://shieldcn.dev/badge/Claude-Code-D97757.svg?logo=anthropic&variant=branded&size=lg)](https://claude.com/claude-code)
[![Statusline](https://shieldcn.dev/badge/statusline-bash-D97757.svg?variant=outline&size=lg)](https://code.claude.com/docs/en/statusline.md)
[![Dependencies](https://shieldcn.dev/badge/needs-jq%20·%20curl-D97757.svg?variant=outline&size=lg)](#requirements)

<br>

One bash script. Each limit bar shows two things: how much you have used, and
how much time has passed. If usage is ahead of time, drop an effort level. If it
is behind, you can raise it. Your folder, branch, model, effort and context
window sit on the same line, under the prompt.

<br>

![The whole statusline from Ctx rightward, every window moving at once.](docs/assets/loop-whole-line.gif)

**[See it in motion → alp82.github.io/claude-statusline](https://alp82.github.io/claude-statusline/)**

</div>

---

## Install or update

One prompt does both. Paste it into Claude Code the first time to install the
statusline, and paste the same prompt again any time you want the latest
version. Claude installs or replaces the script and the plugin, updates the settings, and
checks the result.

```text
Install or update the statusline from https://github.com/alp82/claude-statusline for me.
Run: curl -fsSL https://alp82.github.io/claude-statusline/install.sh | bash
Then check that bash, jq and curl are present, confirm ~/.claude/settings.json
points statusLine at ~/.claude/statusline.sh, confirm that claude plugin list
shows subagent-rows@claude-statusline, and tell me what to do next.
```

Claude reads the installer before it runs it and tells you what changed.

<details>
<summary>Or run the installer yourself</summary>

<br>

The same script without the agent. It installs the statusline, and updates it
if you already have it:

```sh
curl -fsSL https://alp82.github.io/claude-statusline/install.sh | bash
```

It puts `statusline.sh` into `~/.claude/`, makes it executable, points
`settings.json` at it, and installs the `subagent-rows` plugin for the agent
panel. If `claude` is not on your PATH, it prints the two plugin commands
instead. It copies anything it replaces to `<file>.bak` first, and it removes
an older install's `subagent-statusline.sh` and `subagentStatusLine` entry.
Run it again to upgrade. `--no-settings` installs the script only and prints
the rest. `--help` lists all options.

</details>

<details>
<summary>Or install it by hand</summary>

<br>

One file and one plugin:

```sh
curl -fsSL https://raw.githubusercontent.com/alp82/claude-statusline/main/statusline.sh \
  -o ~/.claude/statusline.sh
chmod +x ~/.claude/statusline.sh
claude plugin marketplace add alp82/claude-statusline
claude plugin install subagent-rows@claude-statusline
```

Then add this to `~/.claude/settings.json`:

```json
{
  "statusLine": {
    "type": "command",
    "command": "~/.claude/statusline.sh",
    "refreshInterval": 5
  }
}
```

`refreshInterval` re-runs the line every five seconds on top of the usual
event-driven updates. Without it the file and line counts go stale whenever a
subagent writes to the tree while the session is idle, and the `↻` countdowns
only move when something else happens. Raise it on a large repository, where
`git status` is the slowest part of a render.

</details>

## Uninstall

The same prompt in reverse:

```text
Uninstall the statusline from https://github.com/alp82/claude-statusline for me.
Run: curl -fsSL https://alp82.github.io/claude-statusline/install.sh | bash -s -- --uninstall
Then confirm ~/.claude/statusline.sh is gone, confirm ~/.claude/settings.json
has no statusLine or subagentStatusLine entry, confirm that claude plugin list
no longer shows subagent-rows, and show me which .bak files it left behind.
```

<details>
<summary>Or run it yourself</summary>

<br>

```sh
curl -fsSL https://alp82.github.io/claude-statusline/install.sh | bash -s -- --uninstall
```

It removes `statusline.sh` (and an older install's `subagent-statusline.sh`)
from `~/.claude/`, the `statusLine` and `subagentStatusLine` entries in
`settings.json`, the `subagent-rows` plugin and its marketplace, and the cache
under `~/.claude/cache/`. It backs up the scripts and `settings.json` as
`.bak` first. It changes nothing else, and it leaves an entry alone if it
points at another statusline. `--no-settings` removes the scripts only.

</details>

## What it shows

Two rows, with a blank row between them. The first is the checkout and what
has changed in it. The second is the model and the bars.

The first row is laid out space-between: the checkout on the left, what changed
pushed right so that its edge lines up with the end of the second row.

```text
claude-statusline ⎇ main                             3 mod │ +182 -47

★ Opus 5 1M · max │ Ctx ███░░░░░░░ 28% 90k │ 5h … │ 7d … │ Fable ▀▀░░░░░░░░ 8%
```

### The first row

- **dir ⎇ branch** — the directory name and the git branch. In a linked
  [git worktree](https://git-scm.com/docs/git-worktree) the glyph is an amber
  `⎇+`:

  ```text
  claude-statusline ⎇ main          ← the main checkout
  claude-statusline-fix ⎇+ fix/bar  ← a linked worktree
  ```

  The two share whatever the first row has left after the file and line
  groups, which on a normal terminal is most of the width. While both fit,
  neither is shortened. When they do not fit, the branch loses its namespace
  first, then its tail, then the directory is cut:

  ```text
  claude-statusline ⎇ f/context-win…   ← feature/context-window-bar-redesign
  acme-platform-web… ⎇ a/issue-214…    ← alp82/issue-214-truncate-long-names
  ```

  Claude Code passes the terminal width in `COLUMNS`, which requires v2.1.153
  or later. Without it the budget is a fixed 64 columns minus the groups. It
  never falls below 24 columns, however narrow the terminal. To pin it to a
  fixed number, set `STATUSLINE_LOC_MAX`, which overrides both. Widths are
  measured in terminal columns: a CJK or emoji glyph counts as two.
- **3 mod** — how many files changed, by kind: `add`, `mod`, `del`, and `?`
  for untracked. The count carries the weight and the color; the label stays
  gray, so a row of counts reads as numbers first. Staged and unstaged both
  count. A kind with no files is left out, so a few ordinary edits read
  `3 mod`, and a clean tree shows the directory alone. A new directory counts
  as one untracked entry, the way `git status` reports it.
- **+182 -47** — lines added and lines removed against the last commit.
  Untracked files have no line counts, so a tree holding nothing but new
  files shows the file kinds and no line counts.

### The second row

- **★ Model · effort** — the active model, shortened (`Opus 5 (1M context)`
  becomes `Opus 5 1M`), and the reasoning effort: `low`, `med`, `high`, `xhi`,
  or `max`. A model without an effort setting shows the name alone.
- **Ctx** — how full the context window is, 0–100%, and the token count in
  thousands
- **5h / 7d** — the 5-hour and 7-day rate-limit windows: usage, elapsed time,
  and `↻` the time until the reset
- **Fable** — the same for the Fable weekly quota. It resets with the 7-day
  window, so it shows no `↻` of its own

## How to read it

### Usage against time

![The 5h bar: usage climbs past the blue elapsed-time half at high effort and turns red, then flattens at low effort. The clock overtakes it and the bar turns yellow, then green. A row under the bar records the effort level for each tenth of the window.](docs/assets/loop-burn.gif)

The top half of each bar shows usage. The bottom half shows elapsed time. When
the bar turns red, lower the effort level.

At the reset, both halves drop to zero and the countdown restarts at 5h0m.

#### Colors

The bar color compares usage with elapsed time:

- 🟩 quota to spare: raise model or effort
- 🟨 on pace: keep as is
- 🟥 runs out early: lower model or effort

The number color shows usage: 🟩 under 50% · 🟨 50–80% · 🟥 over 80%

### Context window

![The Ctx bar filling to 78%, turning yellow then red, then compacting back down to the summary.](docs/assets/loop-context.gif)

The bar turns yellow at 25% and red at 50%. Start a new session at yellow.
Answers get worse as the window fills.

### The agent panel

Claude Code lists running subagents below the prompt. Each subagent shows its
own context bar, model, and effort.

![Three agent rows, each with its own context bar, model and effort: one holds at 34%, one climbs into red, one starts late and stays green.](docs/assets/loop-agents.gif)

On a narrow panel, the effort column drops first and the model column second.
Drawn by the `subagent-rows` plugin, which the installer adds. Requires Claude Code v2.1.326 or later.

### The Fable window

![The Fable meter: two columns, the red usage height at full while the blue week-elapsed column climbs to the reset, then both drop to the floor.](docs/assets/loop-fable.gif)

Fable has its own weekly quota. The limit is usually lower than for other
models, so it gets a glance instead of a track: two columns, your usage beside
the week's clock, and the exact number in the percentage. Fable resets with
the 7-day window, so it shows no `↻` of its own.

Claude Code does not send this value. The script reads it from `~/.claude.json`
and refreshes it from the API in the background, at most every ten minutes.

On macOS the refresh reads the OAuth token from the Keychain, because Claude
Code stores it there instead of in `~/.claude/.credentials.json`. The first
read can open a Keychain dialog. Click **Always Allow** once and it stops
asking. To skip the Keychain, set `CLAUDE_STATUSLINE_NO_KEYCHAIN=1`. The Fable
bar then uses only the CLI's own cache.

### Repo and git state

![The first row of the statusline: the folder and the branch hold still on the left while the working-tree counts fill up on the right — files modified, added, deleted and untracked, then the lines — until a commit empties them and the count starts again. The gap between the two never closes.](docs/assets/loop-line-start.gif)

The first row answers what you are working on and what you have done to it: the
folder and the branch on the left, then how many files changed by kind and how
many lines, pushed right so that its edge lands where the second row ends. Long
folder and branch names are cut to fit; the counts keep their room.

## Requirements

- Claude Code v2.1.326 or later for the agent panel (the `subagent-rows` plugin)
- `bash`
- [`jq`](https://jqlang.github.io/jq/) — parses the statusline JSON from stdin
- `curl` — only for refreshing the Fable weekly quota

## How it works

Claude Code sends JSON to the script on stdin
([docs](https://code.claude.com/docs/en/statusline.md)). Everything except the
Fable window comes from that payload. For the Fable quota the script reads the
CLI's cached copy in `~/.claude.json`. When that copy is stale, it calls
`/api/oauth/usage` in the background, at most every ten minutes.

The agent panel works differently: the `subagent-rows` plugin is a Claude Code
mod that hooks each row of the agent list, reads every running agent, and
draws all the rows' bodies on one grid.

The main line uses the model's display name from the payload. The panel
receives a model id and derives the short name from it. Effort also comes from
the payload, on the versions that send it and for the models that support it.
Without it, the line shows the model name alone.

Changes are listed in the [changelog](CHANGELOG.md).

## License

MIT
