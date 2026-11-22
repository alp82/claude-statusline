import React from 'react';
import {cellWidth as cellWidthFor, fontFamily, lineHeight} from '../theme';
import {Bar} from './Bar';
import {agentColumns, buildAgentRow, partCells} from './segments';
import {TextRun} from './Statusline';
import type {AgentRow, Part} from './types';

/**
 * Row gap as a fraction of the font size — the landing page's `.agents`
 * grid uses `row-gap: .85em` (docs/index.html). Change one, change the other.
 */
const ROW_GAP_RATIO = 0.85;

/**
 * The agent panel, as the subagent-rows plugin draws it: one row per running
 * subagent, each with its own context bar. The rows sit on the same cell grid
 * as the statusline, and every variable-width column — name, model, effort —
 * is padded to its widest row, so each field starts in one column down the
 * panel. The plugin measures the same widths across its rows, and the page
 * spends them as a min-width.
 */
export const AgentPanel: React.FC<{
  rows: AgentRow[];
  fontSize: number;
}> = ({rows, fontSize}) => {
  const cw = cellWidthFor(fontSize);
  const ch = lineHeight(fontSize);
  const gap = ROW_GAP_RATIO * fontSize;
  const widths = agentColumns(rows);

  const parts = rows.map((row) => buildAgentRow(row, widths));
  const rowCells = (row: Part[]): number =>
    row.reduce((sum, part) => sum + partCells(part), 0);
  const cells = Math.max(...parts.map(rowCells));

  return (
    <div
      style={{
        position: 'relative',
        width: cells * cw,
        height: rows.length * ch + (rows.length - 1) * gap,
        fontFamily,
        fontSize,
        lineHeight: `${ch}px`,
        whiteSpace: 'pre',
      }}
    >
      {parts.map((row, rowIndex) => {
        let column = 0;
        return (
          <div
            key={rowIndex}
            style={{
              position: 'absolute',
              left: 0,
              top: rowIndex * (ch + gap),
              height: ch,
            }}
          >
            {row.map((part, partIndex) => {
              const left = column * cw;
              column += partCells(part);
              return (
                <div
                  key={partIndex}
                  style={{position: 'absolute', left, top: 0, height: ch}}
                >
                  {part.kind === 'bar' ? (
                    <Bar
                      pct={part.pct}
                      width={part.width}
                      color={part.color}
                      cellWidth={cw}
                      cellHeight={ch}
                    />
                  ) : part.kind === 'text' ? (
                    <TextRun
                      text={part.text}
                      color={part.color}
                      cellWidth={cw}
                      cellHeight={ch}
                    />
                  ) : null}
                </div>
              );
            })}
          </div>
        );
      })}
    </div>
  );
};
