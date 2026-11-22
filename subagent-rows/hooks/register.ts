import type { AgentInfo, Register } from 'claude-code'

// The agent list's rows, one per agent, each with its own context bar:
//   name ▓▓░░░ 12% 34k · Opus 5 · high · description
// Every field is a column measured across all rows, so rows stay aligned.
// Palette, thresholds, bar geometry and effort labels mirror statusline.sh —
// change one, change the other.

const RESET = '\x1b[0m'
const DIM = '\x1b[38;2;138;138;138m'
const SEP = '\x1b[38;2;55;55;55m'
const NAME = '\x1b[38;5;74m'
const TRACK = '48;2;55;55;55'
const PARTIALS = ['', '▏', '▎', '▍', '▌', '▋', '▊', '▉']
const DESC_FLOOR = 20
const PCT_CELLS = 4
const TOKENS_CELLS = 4
const SEP_CELLS = 3
const BAR_CELLS = 10
const EFFORT: Record<string, string> = { low: 'low', medium: 'med', high: 'high', xhigh: 'xhi', max: 'max' }

const ctxColor = (pct: number) =>
  pct >= 50 ? '38;2;220;60;60' : pct >= 25 ? '38;2;220;200;60' : '38;2;140;194;74'

function bar(pct: number, w: number) {
  pct = Math.max(0, Math.min(100, pct))
  const eighths = Math.floor((pct * w * 8) / 100)
  const full = Math.floor(eighths / 8), part = eighths % 8
  const used = full + (part > 0 ? 1 : 0)
  return `\x1b[${TRACK};${ctxColor(pct)}m${'█'.repeat(full)}${PARTIALS[part]}${' '.repeat(w - used)}${RESET}`
}

const isWide = (c: number) =>
  c >= 0x1100 &&
  (c <= 0x115f || c === 0x2329 || c === 0x232a ||
    (c >= 0x2e80 && c <= 0xa4cf && c !== 0x303f) || (c >= 0xac00 && c <= 0xd7a3) ||
    (c >= 0xf900 && c <= 0xfaff) || (c >= 0xfe30 && c <= 0xfe6f) || (c >= 0xff00 && c <= 0xff60) ||
    (c >= 0xffe0 && c <= 0xffe6) || (c >= 0x1f300 && c <= 0x1faff) || (c >= 0x20000 && c <= 0x3fffd))

const visLen = (s: string) => [...s].reduce((n, ch) => n + (isWide(ch.codePointAt(0)!) ? 2 : 1), 0)

function visCut(s: string, max: number) {
  let n = 0, out = ''
  for (const ch of s) {
    const w = isWide(ch.codePointAt(0)!) ? 2 : 1
    if (n + w > max) break
    out += ch; n += w
  }
  return out
}

const pad = (s: string, w: number) => s + ' '.repeat(Math.max(0, w - visLen(s)))
const padL = (s: string, w: number) => ' '.repeat(Math.max(0, w - s.length)) + s
const fmtTokens = (t: number) => `${Math.min(999, Math.max(1, Math.floor((t + 500) / 1000)))}k`

// claude-opus-5[1m] -> Opus 5 1M, claude-sonnet-4-6-2026… -> Sonnet 4.6, claude-3-7-sonnet-… -> Sonnet 3.7,
// claude-3-opus-… -> Opus 3. The pre-4 ids put the version before the family, so both of their
// forms are matched first: read the other way round, their date stamp becomes the version. A
// minor version also counts only when a separator follows it, for the same reason.
export function shortModel(id: string): string {
  const onem = id.includes('[1m]') ? ' 1M' : ''
  let fam: string, ver: string, m: RegExpMatchArray | null
  if ((m = id.match(/(\d+)-(\d+)-(opus|sonnet|haiku)/))) { fam = m[3]!; ver = `${m[1]!}.${m[2]!}` }
  else if ((m = id.match(/(\d+)-(opus|sonnet|haiku)/))) { fam = m[2]!; ver = m[1]! }
  else if ((m = id.match(/(opus|sonnet|haiku|fable)-(\d+)(-(\d{1,2})([-@]|$))?/))) {
    fam = m[1]!; ver = m[2]! + (m[4] ? `.${m[4]}` : '')
  } else return ''
  return `${fam.charAt(0).toUpperCase()}${fam.slice(1)} ${ver}${onem}`
}

/** Every row's body, keyed by agent id, laid out on one shared grid. */
export function drawRows(agents: AgentInfo[], columns: number): Map<string, string> {
  const rows = agents.map(a => {
    const cws = a.contextWindowSize ?? 0
    const tokens = a.tokenCount ?? 0
    return {
      id: a.id,
      // name is set only for an agent SendMessage can address; type always is
      name: a.name || a.type || 'agent',
      pct: cws > 0 ? Math.floor((tokens * 100) / cws) : -1,
      // not started really is 0, so no round-up to 1k without a window size
      tok: cws > 0 || tokens > 0 ? fmtTokens(tokens) : '0k',
      mdl: a.model ? shortModel(a.model) : '',
      eff: typeof a.effort === 'string' ? EFFORT[a.effort] ?? '' : '',
      desc: a.description ?? '',
    }
  })
  const namew = Math.max(0, ...rows.map(r => visLen(r.name)))
  const mdlw = Math.max(0, ...rows.map(r => r.mdl.length))
  const effw = Math.max(0, ...rows.map(r => r.eff.length))
  const rowStart = namew + 1 + BAR_CELLS + 1 + PCT_CELLS + 1 + TOKENS_CELLS

  // a column is dropped for every row or none; effort goes first, then model
  const floor = rows.some(r => r.desc) ? SEP_CELLS + DESC_FLOOR : 0
  const showMdl0 = mdlw > 0
  const showEff = effw > 0 && rowStart + (showMdl0 ? SEP_CELLS + mdlw : 0) + SEP_CELLS + effw + floor <= columns
  const showMdl = showMdl0 && rowStart + SEP_CELLS + mdlw + floor <= columns

  const out = new Map<string, string>()
  for (const r of rows) {
    let meter = r.pct >= 0
      ? `${bar(r.pct, BAR_CELLS)} \x1b[${ctxColor(r.pct)}m${padL(`${r.pct}%`, PCT_CELLS)}${RESET}`
      : ' '.repeat(BAR_CELLS + 1 + PCT_CELLS)
    meter += ` ${DIM}${padL(r.tok, TOKENS_CELLS)}${RESET}`
    let row = `${NAME}${pad(r.name, namew)}${RESET} ${meter}`
    let len = rowStart
    for (const [shown, text, width] of [[showMdl, r.mdl, mdlw], [showEff, r.eff, effw]] as const) {
      if (!shown) continue
      row += text ? ` ${SEP}·${RESET} ${DIM}${pad(text, width)}${RESET}` : ' '.repeat(SEP_CELLS + width)
      len += SEP_CELLS + width
    }
    let desc = r.desc
    const room = columns - len - SEP_CELLS
    if (desc && room > 4) {
      if (visLen(desc) > room) desc = `${visCut(desc, room - 1)}…`
      row += ` ${SEP}·${RESET} ${DIM}${desc}${RESET}`
    }
    out.set(r.id, row)
  }
  return out
}

export const register: Register = on => {
  on('ui.render', { component: 'AgentRow' }, async ($, e, next) => {
    // the grid needs every row, not just this one
    const ids = new Set(e.props.rowIds)
    const agents = (await $.agent.list()).filter(a => ids.has(a.id))
    const body = drawRows(agents, e.props.columns ?? 80).get(e.props.id)
    return body === undefined ? next(e) : next({ ...e, props: { ...e.props, body } })
  })
}
