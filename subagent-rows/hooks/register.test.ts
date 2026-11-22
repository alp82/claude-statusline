import { expect, test } from 'claude-code/testing'
import { drawRows, shortModel } from './register'

const strip = (s: string) => s.replace(/\x1b\[[0-9;]*m/g, '')
const agent = (o: object) => ({ id: 'a', name: 'x', description: '', tokenCount: 0, ...o }) as any

test('model ids read as short names', async () => {
  expect(shortModel('claude-opus-5[1m]')).toBe('Opus 5 1M')
  expect(shortModel('claude-sonnet-4-6-20260401')).toBe('Sonnet 4.6')
  expect(shortModel('claude-3-7-sonnet-20250219')).toBe('Sonnet 3.7')
  expect(shortModel('claude-opus-4-20250514')).toBe('Opus 4')
  expect(shortModel('claude-3-opus-20240229')).toBe('Opus 3')
  expect(shortModel('gpt-4')).toBe('')
})

test('rows align on one grid and fit the width', async () => {
  const rows = drawRows([
    agent({ id: 'a', name: 'explorer', model: 'claude-opus-5', effort: 'high', tokenCount: 50000, contextWindowSize: 200000, description: 'find the thing' }),
    agent({ id: 'b', name: 'p', description: 'a much longer description that must be cut short here because it is long' }),
  ], 100)
  const a = strip(rows.get('a')!), b = strip(rows.get('b')!)
  expect(a.startsWith('explorer ')).toBe(true)
  expect(a.includes(' 25%  50k · Opus 5 · high · find the thing')).toBe(true)
  expect(b.indexOf('0k')).toBe(a.indexOf('50k') + 1)
  expect(b.indexOf(' · a much')).toBe(a.indexOf(' · find'))
  expect(b.endsWith('…')).toBe(true)
  expect([...b].length).toBeLessThanOrEqual(100)
})

test('narrow panel drops effort first, then model, for every row', async () => {
  const two = [
    agent({ id: 'a', model: 'claude-opus-5', effort: 'high', description: 'find the thing' }),
    agent({ id: 'b', model: 'claude-opus-5', effort: 'high', description: 'read the docs' }),
  ]
  const at55 = drawRows(two, 55), at50 = drawRows(two, 50)
  for (const id of ['a', 'b']) {
    const mid = strip(at55.get(id)!), narrow = strip(at50.get(id)!)
    expect(mid.includes('Opus 5')).toBe(true)
    expect(mid.includes('high')).toBe(false)
    expect(narrow.includes('Opus')).toBe(false)
    expect(narrow.includes('high')).toBe(false)
  }
})

test('control characters in a name or description become single spaces', async () => {
  const a = strip(drawRows([agent({ name: 'a\tb', description: 'x\ny\r\u0001z\u007fw' })], 80).get('a')!)
  expect(/[\x00-\x1f\x7f]/.test(a)).toBe(false)
  expect(a.startsWith('a b ')).toBe(true)
  expect(a.endsWith(' · x y  z w')).toBe(true)
})

test('an agent without a name is labelled by its type', async () => {
  const a = strip(drawRows([agent({ name: undefined, type: 'Explore' })], 80).get('a')!)
  expect(a.startsWith('Explore ')).toBe(true)
})
