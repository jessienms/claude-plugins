export type TodoRow = { id: string; title: string; lines: number }

declare module 'claude-code' {
  interface PluginState {
    todo: {
      rows: TodoRow[]
      opened: string
      detail: string
      message: string
    }
  }
}
