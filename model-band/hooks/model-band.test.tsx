import { expect, test } from 'claude-code/testing'

import { shortHint } from './register'

// turn.step streams: its hooks run as the stream is read, so drain it.
async function drain(stream: AsyncIterable<unknown>): Promise<void> {
  for await (const chunk of stream) void chunk
}

type Written = { path: string; text: string }

test('the mod publishes the lead, workers and advisor to a per-session state file', async ($, on) => {
  const writes: Written[] = []
  on('session.model', async () => ({ value: 'claude-sonnet-5-5' }))
  on('session.id', async () => ({ value: 'sess-1' }))
  on('env.get', async () => ({ value: '/home/test' }) as never)
  on('clock.now', async () => ({ value: 1_700_000_000_000 }))
  on('fs.write', async (_$, e) => {
    writes.push({ path: e.path, text: e.text })
    return { value: undefined } as never
  })
  on('session.start', async () => ({ cwd: '/work' }))
  on('command.register', async () => ({ value: { command: 'model-band' } }))
  on('agent.spawn', async () => ({ model: 'claude-haiku-5-5', agentId: 'agent-1' }))
  on('turn.step', async function* (_$, e) {
    return {
      turnId: e.turnId,
      index: e.index,
      answer: '',
      toolUses: [],
      stopReason: 'end_turn',
      usage: { model: e.agentId === undefined ? 'claude-sonnet-5-5' : 'claude-haiku-5-5', input_tokens: 10, output_tokens: 10 },
      serverToolUses:
        e.index === 1 ? [{ id: 's1', name: 'advisor', input: {}, startedAt: 1000, endedAt: 4000 }] : undefined,
    } as never
  })
  on('turn.complete', async (_$, e) => ({ text: 'done', usage: e.usage }) as never)

  const last = () => JSON.parse(writes[writes.length - 1]?.text ?? '{}')

  await $.session.start({ cwd: '/work', surface: 'terminal', isInteractive: true })
  expect(writes[0]?.path).toBe('/home/test/.claude/model-band/sess-1.json')
  expect(last().lead.model).toBe('claude-sonnet-5-5')
  expect(last().sessionId).toBe('sess-1')
  expect(last().updatedAt).toBe(1_700_000_000_000)

  await $.agent.spawn({ tool_use_id: 't1', prompt: 'p', description: 'fix filters', subagentType: 'worker' } as never)
  expect(last().workers[0].label).toBe('fix filters')
  expect(last().workers[0].endedAt).toBeUndefined()

  await drain($.turn.step({ turnId: 'a', index: 0, model: 'claude-sonnet-5-5', messageCount: 1 } as never))
  expect(last().lead.steps).toBe(1)
  await drain($.turn.step({ turnId: 'b', index: 1, model: 'claude-haiku-5-5', messageCount: 1, agentId: 'agent-1' } as never))
  expect(last().workers[0].steps).toBe(1)
  expect(last().advisor).toEqual({ calls: 1, ms: 3000 })

  await $.turn.complete({ turnId: 'b', reason: 'answer', answer: 'done', agentId: 'agent-1' } as never)
  expect(last().workers[0].endedAt).toBe(1_700_000_000_000)

  // /model-band off hides it in the state file, on brings it back
  const run = (args: string) =>
    $.command.run({ command: 'model-band', args, origin: 'user', presentation: 'text' } as never)
  await run('off')
  expect(last().hidden).toBe(true)
  await run('on')
  expect(last().hidden).toBe(false)
})

test('the hint line drops the shift+tab note, shortens the agents hint, and ends with the branch', async () => {
  // as the engine hands it (2.1.296): the mode pill is not in the text
  expect(shortHint('(shift+tab to cycle) · ← 1 agent', 'main')).toBe('← 1 agent · ⎇ main')
  expect(shortHint('(shift+tab to cycle) · ← for agents', 'main')).toBe('← agents · ⎇ main')
  expect(shortHint('(shift+tab to cycle)', 'main')).toBe('⎇ main')
  expect(shortHint('esc to interrupt', 'feat/x')).toBe('esc to interrupt · ⎇ feat/x')
  expect(shortHint('? for shortcuts', null)).toBe('? for shortcuts')
})

test('the hint line hook draws the short line with the branch git reports', async ($, on) => {
  on('session.model', async () => ({ value: 'claude-sonnet-5-5' }))
  on('session.id', async () => ({ value: 'sess-3' }))
  on('env.get', async () => ({ value: undefined }) as never)
  on('clock.now', async () => ({ value: 1 }))
  on('session.start', async () => ({ cwd: '/work' }))
  on('command.register', async () => ({ value: { command: 'model-band' } }))
  on('process.run', async (_$, e) => ({
    value: { exitCode: 0, stdout: e.argv.includes('--show-current') ? 'docs/x\n' : '', stderr: '', isStdoutTruncated: false, isStderrTruncated: false },
  }) as never)

  // stands in for the engine: draws the hint it is handed
  on('ui.render', { component: 'PromptHint' }, async ($, e) => {
    const { Text } = $.ui.resolve(e)

    return <Text dimColor>{(e.props as { hint: string }).hint}</Text>
  })

  await $.session.start({ cwd: '/work', surface: 'terminal', isInteractive: true })
  const tree = await $.ui.render({
    surface: 'terminal', component: 'PromptHint', requestId: 'h',
    props: { hint: '(shift+tab to cycle) · ← 1 agent', isDraft: false, isWorking: false },
  } as never)
  const text = JSON.stringify(tree)
  expect(text).toContain('← 1 agent · ⎇ docs/x')
  expect(text).not.toContain('shift+tab')
})
