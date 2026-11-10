export type Row = {
  id: string
  model: string
  label: string
  startedAt: number
  endedAt?: number
  steps: number
}

export type Advisor = { calls: number; ms: number }

declare module 'claude-code' {
  interface PluginState {
    'model-band': {
      lead: Row | null
      workers: Row[]
      advisor: Advisor
      isHidden: boolean
      branch: string | null
    }
  }
}
