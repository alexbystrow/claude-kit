import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { Row } from '../types'

const lead = atom({ plugin: 'model-band', key: 'lead' } as const, null)
const workers = atom({ plugin: 'model-band', key: 'workers' } as const, [])
const advisor = atom({ plugin: 'model-band', key: 'advisor' } as const, { calls: 0, ms: 0 })
const isHidden = atom({ plugin: 'model-band', key: 'isHidden' } as const, false)
const branch = atom({ plugin: 'model-band', key: 'branch' } as const, null)

// The hint line under the prompt, shorter: no "(shift+tab to cycle)", "← for agents" is "← agents", and
// the git branch closes the line (the status line no longer shows it). The mode pill ("auto mode on") is
// drawn by the engine outside this text and no mod can read the mode, so it stays as it is.
export function shortHint(hint: string, name: string | null): string {
  const line = hint
    .replace(/\s*\(shift\+tab to cycle\)/g, '')
    .replace(/← for agents/g, '← agents')
    .trim()
    .replace(/^·\s*/, '')
  if (!name) return line

  return line ? `${line} · ⎇ ${name}` : `⎇ ${name}`
}

// The branch of the session's directory, or the short commit when detached; null outside a repo.
async function readBranch($: EngineInterface): Promise<string | null> {
  try {
    const cur = await $.process.run(['git', 'branch', '--show-current'], { timeoutMs: 3000 })
    if (cur.exitCode === 0 && cur.stdout.trim()) return cur.stdout.trim()
    const sha = await $.process.run(['git', 'rev-parse', '--short', 'HEAD'], { timeoutMs: 3000 })

    return sha.exitCode === 0 && sha.stdout.trim() ? sha.stdout.trim() : null
  } catch {
    return null
  }
}

async function refreshBranch($: EngineInterface) {
  const name = await readBranch($)
  if (name !== (await read($, branch))) await update($, branch, () => name)
}

function shortModel(model: string): string {
  const m = /(opus|sonnet|haiku|fable)-(\d+)-(\d+)/.exec(model)

  return m ? `${m[1]} ${m[2]}.${m[3]}` : model
}

// The band is drawn by the status line (bin/statusline.sh), which cannot see the session's
// workers. So the mod writes what it knows to a small file per session, whenever it changes.
async function publish($: EngineInterface) {
  const home = await $.env.get('HOME')
  if (!home) return
  const sid = await $.session.id()
  const state = {
    v: 1,
    sessionId: sid,
    updatedAt: await $.clock.now(),
    hidden: await read($, isHidden),
    lead: await read($, lead),
    workers: await read($, workers),
    advisor: await read($, advisor),
  }
  try {
    await $.fs.write(`${home}/.claude/model-band/${sid}.json`, JSON.stringify(state))
  } catch {
    // no state file: the status line then shows no team, only its own segments
  }
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'model-band',
      description: 'Show or hide the model band in the status line',
      argumentHint: '[on|off]',
    })
    const model = await $.session.model()
    const t = await $.clock.now()
    // A reload runs session.start again: keep what the lead has already done.
    await update($, lead, row =>
      row ? { ...row, model } : { id: 'lead', model, label: 'lead', startedAt: t, steps: 0 },
    )
    await publish($)
    await refreshBranch($)

    return next(e)
  })

  // The hint line under the prompt, shortened, with the branch at its end. With the band off, the engine's line stays.
  on('ui.render', { component: 'PromptHint' }, async ($, e, next) => {
    if (await read($, isHidden)) return next(e)
    const hint = shortHint(e.props.hint, await read($, branch))

    return hint === e.props.hint ? next(e) : next({ ...e, props: { ...e.props, hint } })
  })

  on('command.run', { command: 'model-band' }, async ($, e) => {
    const arg = e.args.trim().toLowerCase()
    const wasHidden = await read($, isHidden)
    const hide = arg === 'on' ? false : arg === 'off' ? true : !wasHidden
    await update($, isHidden, () => hide)
    await publish($)

    if (hide) {
      return { text: 'Model band is OFF (the status line keeps its own segments). /model-band on shows it again.' }
    }
    const l = await read($, lead)
    const running = (await read($, workers)).filter(w => w.endedAt === undefined).length
    const adv = await read($, advisor)
    const bits = [
      l === null ? 'no lead yet' : `lead ${shortModel(l.model)}`,
      `${running} worker${running === 1 ? '' : 's'} running`,
      `advisor ×${adv.calls}`,
    ]

    return { text: `Model band is ON, drawn by the status line. Now: ${bits.join(', ')}. /model-band off hides it.` }
  })

  on('agent.spawn', async ($, e, next) => {
    const started = await next(e)
    if (started.deny === undefined && started.agentId) {
      const id = started.agentId
      const t = await $.clock.now()
      const row: Row = {
        id,
        model: started.model,
        label: e.description || e.subagentType,
        startedAt: t,
        steps: 0,
      }
      await update($, workers, list => [...list.filter(w => w.id !== id), row])
      await publish($)
    }

    return started
  }).catch(async ($, e, next) => next(e))

  on('turn.step', async function* ($, e, next) {
    const result = yield* next(e)
    const u = result.usage

    if (u) {
      if (e.agentId === undefined) {
        await update($, lead, row => (row ? { ...row, model: u.model, steps: row.steps + 1 } : row))
      } else {
        const id = e.agentId
        const t = await $.clock.now()
        await update($, workers, list => {
          const known = list.some(w => w.id === id)
          const base = known ? list : [...list, { id, model: u.model, label: id.slice(0, 6), startedAt: t, steps: 0 }]

          return base.map(w => (w.id === id ? { ...w, model: u.model, steps: w.steps + 1 } : w))
        })
      }
    }

    const calls = (result.serverToolUses ?? []).filter(s => s.name === 'advisor')
    if (calls.length > 0) {
      const ms = calls.reduce((sum, s) => sum + Math.max(0, (s.endedAt ?? s.startedAt) - s.startedAt), 0)
      await update($, advisor, a => ({ calls: a.calls + calls.length, ms: a.ms + ms }))
    }
    if (u || calls.length > 0) await publish($)

    return result
  })

  on('turn.complete', async ($, e, next) => {
    const done = await next(e)
    if (e.agentId !== undefined) {
      const id = e.agentId
      const t = await $.clock.now()
      await update($, workers, list => list.map(w => (w.id === id && w.endedAt === undefined ? { ...w, endedAt: t } : w)))
    } else {
      // the lead's turn may have switched branches (git checkout, a new branch)
      await refreshBranch($)
    }
    await publish($)

    return done
  })
}
