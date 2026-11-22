export type SegmentId = 'dir' | 'git' | 'model' | 'ctx' | 'five' | 'week' | 'fable';

export type Part =
  /** `bold` is the weight the git counts carry — their labels stay regular. */
  | {kind: 'text'; text: string; color: string; bold?: boolean}
  | {kind: 'bar'; pct: number; width: number; color: string}
  | {kind: 'stacked'; usage: number; elapsed: number; width: number; color: string}
  /** The stacked bar folded into two columns of block-glyph heights. */
  | {kind: 'vmeter'; usage: number; elapsed: number; width: number; color: string};

export type Segment = {
  id: SegmentId;
  parts: Part[];
  /** Total width in terminal cells. */
  cells: number;
};

/** A limit window: usage, how far into the window we are, and the countdown. */
export type LimitWindow = {
  pct: number;
  /** 0–100, how much of the window has elapsed. Omit for a plain (unstacked) bar. */
  elapsed?: number;
  /** Seconds until the window resets. Omit to hide the ↻ countdown. */
  resetsIn?: number;
};

/**
 * What changed in the working tree. Files by kind, then lines against the last
 * commit. A kind at zero is left out, the way the script leaves it out, so a
 * state with only `mod` set draws `3 mod` and nothing else.
 */
export type GitState = {
  add?: number;
  mod?: number;
  del?: number;
  /** Untracked. Drawn with git's own `?` rather than a word. */
  untracked?: number;
  /** Lines added and removed against the last commit. */
  insertions?: number;
  deletions?: number;
};

/** One row of the agent panel, as the subagent-rows plugin draws it. */
export type AgentRow = {
  name: string;
  /** The agent's own context usage, 0–100. Tokens are derived from it. */
  ctx: number;
  desc: string;
  /** The agent's model, already shortened. Omit to hide it and the effort. */
  model?: string;
  /** The agent's effort level. Omit to hide. */
  effort?: string;
};

/**
 * Everything the statusline can show. Every field is optional the same way the
 * script's segments are conditional — omit one and the segment disappears,
 * separators included.
 */
export type StatuslineState = {
  dir?: string;
  branch?: string;
  /** True in a linked git worktree — the branch glyph becomes an amber ⎇+. */
  worktree?: boolean;
  /** The working tree, as `git status` and `git diff HEAD` report it. */
  git?: GitState;
  model?: string;
  /** Reasoning effort, printed after the model as `· high`. Omit to hide. */
  effort?: string;
  ctx?: number;
  /** Raw context tokens. The segment prints them in thousands. Omit to hide. */
  ctxTokens?: number;
  five?: LimitWindow;
  week?: LimitWindow;
  fable?: LimitWindow;
  /** Agent-panel rows. A state with rows renders the panel, not the line. */
  agents?: AgentRow[];
};
