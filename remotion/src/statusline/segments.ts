import {colors, ctxColor, paceColor, pctColor} from '../theme';
import type {
  AgentRow,
  GitState,
  LimitWindow,
  Part,
  Segment,
  SegmentId,
  StatuslineState,
} from './types';

/** now / 45m / 7h9m / 3d10h — mirrors fmt_reset in statusline.sh. */
export const fmtReset = (seconds: number): string => {
  const diff = Math.round(seconds);
  if (diff <= 60) return 'now';
  if (diff < 3600) return `${Math.floor(diff / 60)}m`;
  if (diff < 86400)
    return `${Math.floor(diff / 3600)}h${Math.floor((diff % 3600) / 60)}m`;
  return `${Math.floor(diff / 86400)}d${Math.floor((diff % 86400) / 3600)}h`;
};

/** Width of a part in terminal cells. */
export const partCells = (part: Part): number =>
  part.kind === 'text' ? [...part.text].length : part.width;

const segment = (id: Segment['id'], parts: Part[]): Segment => ({
  id,
  parts,
  cells: parts.reduce((sum, part) => sum + partCells(part), 0),
});

/** Bar width in cells — the script hardcodes 10. */
export const BAR_CELLS = 10;

/** Percentages are shown as integers — the script rounds before printing. */
const pctText = (pct: number): string => `${Math.round(pct)}%`;

/** fmt_tokens in statusline.sh — context tokens in thousands, 1k … 999k. */
export const fmtTokens = (tokens: number): string =>
  `${Math.min(999, Math.max(1, Math.round(tokens / 1000)))}k`;

/**
 * Every value on the line changes while a loop plays, so each variable-width
 * field is padded to the widest string it can ever hold. Without this the cell
 * grid re-flows the moment `9%` becomes `100%` and the whole line shuffles
 * sideways mid-animation — the padding is what keeps segment x-positions
 * identical from frame to frame.
 */
const PCT_CELLS = 4; // '100%'
const RESET_CELLS = 7; // '↻6d23h' — the widest a 7-day countdown gets
const TOKENS_CELLS = 4; // '999k'

/** Right-aligned, so the digits grow leftward into the gap and the `%` never moves. */
const pctField = (pct: number): string => pctText(pct).padStart(PCT_CELLS);

/** Right-aligned too, which keeps the `k` in one column as the count grows. */
const tokensField = (tokens: number): string =>
  fmtTokens(tokens).padStart(TOKENS_CELLS);

/** Left-aligned: the `↻` is the anchor, so it stays put as the duration shortens. */
const resetField = (seconds: number): string =>
  `↻${fmtReset(seconds)}`.padEnd(RESET_CELLS);

const limitSegment = (
  id: 'five' | 'week' | 'fable',
  label: string,
  window: LimitWindow,
  showReset = true
): Segment => {
  const pct = Math.round(window.pct);
  const color = pctColor(pct);
  const parts: Part[] = [
    {kind: 'text', text: `${label} `, color: colors.dim},
    window.elapsed === undefined
      ? {kind: 'bar', pct, width: BAR_CELLS, color}
      : id === 'fable'
        ? {
            // The Fable window is secondary, so it gets the two-column
            // vertical meter instead of a 10-cell bar — statusline.sh's
            // vert_meter(). barColumns skips it: two cells hold no race.
            kind: 'vmeter',
            usage: pct,
            elapsed: window.elapsed,
            width: 2,
            color: paceColor(pct, window.elapsed),
          }
        : {
            kind: 'stacked',
            usage: pct,
            elapsed: window.elapsed,
            width: BAR_CELLS,
            // The bar's top row reads pace against the blue row; the % text
            // keeps the absolute thresholds.
            color: paceColor(pct, window.elapsed),
          },
    {kind: 'text', text: ` ${pctField(pct)}`, color},
  ];
  if (showReset && window.resetsIn !== undefined) {
    parts.push({
      kind: 'text',
      text: ` ${resetField(window.resetsIn)}`,
      color: colors.dim,
    });
  }
  return segment(id, parts);
};

/**
 * The working-tree segment: files by kind, then lines against the last commit.
 * The count carries the weight and the colour and the label stays dim, so a row
 * of counts reads as numbers first. Two spaces divide one kind from the next
 * against the one inside each, which is what binds a count to its label.
 *
 * A kind at zero is left out, so the common case — a few edits and nothing else
 * — draws `3 mod` rather than a row of zeroes. Untracked files carry no line
 * counts, so a tree holding nothing but new files draws the kinds alone.
 */
const KIND_GAP = '  ';

const gitSegment = (git: GitState): Segment | null => {
  const kinds: Array<[number | undefined, string, string]> = [
    [git.add, 'add', colors.green],
    [git.mod, 'mod', colors.yellow],
    [git.del, 'del', colors.red],
    [git.untracked, '?', colors.dim],
  ];
  const parts: Part[] = [];
  for (const [count, label, color] of kinds) {
    if (!count) continue;
    if (parts.length) parts.push({kind: 'text', text: KIND_GAP, color: colors.dim});
    parts.push({kind: 'text', text: String(count), color, bold: true});
    parts.push({kind: 'text', text: ` ${label}`, color: colors.dim});
  }
  const lines: Part[] = [];
  if (git.insertions)
    lines.push({kind: 'text', text: `+${git.insertions}`, color: colors.green, bold: true});
  if (git.deletions) {
    if (lines.length) lines.push({kind: 'text', text: ' ', color: colors.dim});
    lines.push({kind: 'text', text: `-${git.deletions}`, color: colors.red, bold: true});
  }
  if (parts.length && lines.length)
    parts.push({kind: 'text', text: ' │ ', color: colors.sep});
  parts.push(...lines);
  return parts.length ? segment('git', parts) : null;
};

/**
 * statusline.sh's location budget: the folder and the branch share a column
 * count. While both fit, neither is shortened. When they do not fit, the branch
 * loses its namespace first, then its tail, then the folder is cut. The same
 * ladder runs in `fitLocation()` on the landing page — change one, change the
 * other. The script counts terminal columns; these names are ASCII, where
 * characters and columns agree.
 */
const LOC_MAX = 34;
const LOC_GLUE = 3; // the " ⎇ " between the two
const BRANCH_FLOOR = 12;
const FOLDER_FLOOR = 10;

/** Cut at the word boundary nearest the limit, unless it costs more than 3. */
const wordTrim = (text: string, cells: number): string => {
  if (text.length <= cells) return text;
  const cut = text.slice(0, cells - 1);
  const at = Math.max(
    cut.lastIndexOf('-'),
    cut.lastIndexOf('_'),
    cut.lastIndexOf('.'),
    cut.lastIndexOf('/')
  );
  return (at >= 4 && at >= cut.length - 3 ? cut.slice(0, at) : cut) + '…';
};

export const fitLocation = (dir: string, branch: string): [string, string] => {
  const glue = branch ? LOC_GLUE : 0;
  if (dir.length + branch.length + glue <= LOC_MAX) return [dir, branch];
  const short = branch.includes('/')
    ? `${branch[0]}/${branch.split('/').pop()}`
    : branch;
  const room = LOC_MAX - dir.length - glue;
  if (room >= short.length || room >= BRANCH_FLOOR) {
    return [dir, wordTrim(short, room)];
  }
  const branchCells = Math.min(short.length, BRANCH_FLOOR);
  return [
    wordTrim(dir, Math.max(LOC_MAX - glue - branchCells, FOLDER_FLOOR)),
    wordTrim(short, branchCells),
  ];
};

/**
 * Build the segment list in the same order, colours and thresholds as
 * statusline.sh. Callers animate by passing a different state per frame.
 * Omitting a field drops its segment (separators included) — the script's own
 * conditionals, except that it always prints a model, defaulting to `?`.
 */
export const buildSegments = (state: StatuslineState): Segment[] => {
  const segments: Segment[] = [];

  if (state.dir) {
    const [dir, branch] = fitLocation(state.dir, state.branch ?? '');
    const parts: Part[] = [{kind: 'text', text: dir, color: colors.dir}];
    if (branch) {
      if (state.worktree) {
        parts.push({kind: 'text', text: ' ⎇+', color: colors.amber});
        parts.push({kind: 'text', text: ` ${branch}`, color: colors.dim});
      } else {
        parts.push({kind: 'text', text: ` ⎇ ${branch}`, color: colors.dim});
      }
    }
    segments.push(segment('dir', parts));
  }

  if (state.git) {
    const git = gitSegment(state.git);
    if (git) segments.push(git);
  }

  if (state.model) {
    const parts: Part[] = [
      {kind: 'text', text: `★ ${state.model}`, color: colors.green},
    ];
    if (state.effort) {
      parts.push({kind: 'text', text: ' · ', color: colors.sep});
      parts.push({kind: 'text', text: state.effort, color: colors.dim});
    }
    segments.push(segment('model', parts));
  }

  if (state.ctx !== undefined) {
    const pct = Math.round(state.ctx);
    const color = ctxColor(pct);
    const parts: Part[] = [
      {kind: 'text', text: 'Ctx ', color: colors.dim},
      {kind: 'bar', pct, width: BAR_CELLS, color},
      {kind: 'text', text: ` ${pctField(pct)}`, color},
    ];
    if (state.ctxTokens !== undefined && state.ctxTokens > 0) {
      parts.push({
        kind: 'text',
        text: ` ${tokensField(state.ctxTokens)}`,
        color: colors.dim,
      });
    }
    segments.push(segment('ctx', parts));
  }

  if (state.five) segments.push(limitSegment('five', '5h', state.five));
  if (state.week) segments.push(limitSegment('week', '7d', state.week));
  // Fable drops the ↻ countdown: its window resets with the 7-day one, so the
  // segment before it already shows that time.
  if (state.fable)
    segments.push(limitSegment('fable', 'Fable', state.fable, false));

  return segments;
};

/**
 * One agent-panel row, as the subagent-rows plugin draws it: name in the
 * directory blue, the agent's own context bar and percentage on ctx
 * thresholds, the token count, then ` · ` and the description in dim. The
 * name is padded to a fixed column so the rows' bars align, and the tokens
 * are the same reading as the percentage, derived against a 1M window.
 */
export const buildAgentRow = (row: AgentRow, widths: AgentColumns): Part[] => {
  const pct = Math.round(row.ctx);
  const color = ctxColor(pct);
  const parts: Part[] = [
    {kind: 'text', text: row.name.padEnd(widths.name), color: colors.dir},
    {kind: 'text', text: ' ', color: colors.dim},
    {kind: 'bar', pct, width: BAR_CELLS, color},
    {kind: 'text', text: ` ${pctField(pct)}`, color},
    {kind: 'text', text: ` ${tokensField((pct / 100) * 1000000)}`, color: colors.dim},
  ];
  // The plugin prints the model and the effort between the meter and the
  // description, each behind its own dot and padded to its column, so a row
  // missing one still starts its description where the others do.
  for (const [field, cells] of [
    [row.model, widths.model],
    [row.effort, widths.effort],
  ] as const) {
    if (!cells) continue;
    if (field) {
      parts.push({kind: 'text', text: ' · ', color: colors.sep});
      parts.push({kind: 'text', text: field.padEnd(cells), color: colors.dim});
    } else {
      parts.push({kind: 'text', text: ' '.repeat(SEPARATOR_CELLS + cells), color: colors.dim});
    }
  }
  parts.push({kind: 'text', text: ' · ', color: colors.sep});
  parts.push({kind: 'text', text: row.desc, color: colors.dim});
  return parts;
};

/**
 * The panel's column widths, measured across every row — the plugin does the
 * same across every row before it draws any.
 */
export type AgentColumns = {name: number; model: number; effort: number};

export const agentColumns = (rows: AgentRow[]): AgentColumns => {
  const widest = (pick: (row: AgentRow) => string | undefined): number =>
    Math.max(0, ...rows.map((row) => [...(pick(row) ?? '')].length));
  return {
    name: widest((row) => row.name),
    model: widest((row) => row.model),
    effort: widest((row) => row.effort),
  };
};

/** ` │ ` — the separator the script puts between segments. */
export const SEPARATOR_CELLS = 3;

export type SegmentBox = {
  id: Segment['id'];
  start: number;
  cells: number;
  /** Whether a ` │ ` is drawn before this segment. False across a spread gap. */
  separator: boolean;
};

/**
 * Column offset of every segment, separators included. Frame-exact and DOM-free,
 * so the camera can target a segment by id at any zoom.
 *
 * `spreadTo` lays the row out space-between over that many cells, the way the
 * script lays out its first row: the first segment stays at column 0 and the
 * rest are pushed right to end on the last column. The gap does the separating,
 * so no ` │ ` is drawn across it. A row too wide to spread falls back to packing
 * left, which is the script's own behaviour when the gap would close.
 */
export const layout = (
  segments: Segment[],
  spreadTo?: number
): {boxes: SegmentBox[]; cells: number} => {
  const boxes: SegmentBox[] = [];
  let column = 0;
  segments.forEach((seg, index) => {
    if (index > 0) column += SEPARATOR_CELLS;
    boxes.push({id: seg.id, start: column, cells: seg.cells, separator: index > 0});
    column += seg.cells;
  });
  if (spreadTo === undefined || segments.length < 2) return {boxes, cells: column};

  const tail = boxes.slice(1);
  const tailCells = column - tail[0].start;
  const gap = spreadTo - boxes[0].cells - tailCells;
  if (gap < 1) return {boxes, cells: column};
  const shift = gap - SEPARATOR_CELLS;
  tail.forEach((box) => {
    box.start += shift;
  });
  tail[0].separator = false;
  return {boxes, cells: spreadTo};
};

/**
 * Column offset and width of one segment's bar. The landing page measures the
 * painted `.bar` with `getBoundingClientRect`; here the geometry is already
 * known, so the annotation is placed against this instead of against the DOM.
 *
 * Every variable-width field is padded (see `pctField` and friends), so this
 * answer is the same on every frame of a loop — the marks cannot slide while
 * `9%` grows into `100%`.
 */
export const barColumns = (
  segments: Segment[],
  id: SegmentId
): {start: number; cells: number} | null => {
  const index = segments.findIndex((seg) => seg.id === id);
  if (index < 0) return null;
  const {boxes} = layout(segments);
  let column = boxes[index].start;
  for (const part of segments[index].parts) {
    if (part.kind === 'bar' || part.kind === 'stacked')
      return {start: column, cells: part.width};
    column += partCells(part);
  }
  return null;
};
