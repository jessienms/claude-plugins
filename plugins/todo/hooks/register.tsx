import { atom, read, update } from 'claude-code'
import type { EngineInterface, Register } from 'claude-code'

import type { TodoRow } from '../types'

// /todo-list 패널. 읽기 전용이다: 목록을 보고, 제목을 눌러 상세를 펼치고, 닫는 것만 한다.
// 추가·수정·완료는 모델의 판단이 필요하므로 todo 스킬이 맡는다.

const PANE = 'todo-list'
const rows = atom({ plugin: 'todo', key: 'rows' } as const, [] as TodoRow[])
const opened = atom({ plugin: 'todo', key: 'opened' } as const, '')
const detail = atom({ plugin: 'todo', key: 'detail' } as const, '')
const message = atom({ plugin: 'todo', key: 'message' } as const, '')

type $ = EngineInterface

// Windows 에서 PATH 의 bash 는 WSL 일 수 있어 Git Bash 를 먼저 찾는다.
const WINDOWS_BASH = [
  'C:/Program Files/Git/usr/bin/bash.exe',
  'C:/Program Files/Git/bin/bash.exe',
  'C:/Program Files (x86)/Git/usr/bin/bash.exe',
]

let runner: { bash: string; script: string } | undefined

async function resolveRunner($: $) {
  if (runner) return runner
  const env = await $.process.hookEnv()
  const root = (env.CLAUDE_PLUGIN_ROOT ?? '').replace(/\\/g, '/')
  let bash = 'bash'
  if ((await $.session.info()).platform === 'windows') {
    for (const candidate of WINDOWS_BASH) {
      if (await $.fs.exists(candidate)) {
        bash = candidate
        break
      }
    }
  }
  runner = { bash, script: `${root}/skills/todo/scripts/todo.sh` }
  return runner
}

async function todo($: $, args: string[]) {
  const { bash, script } = await resolveRunner($)
  // 엔진이 띄운 bash 는 Git Bash 의 /usr/bin 이 PATH 에 없어 basename·awk 를 못 찾는다.
  const ran = await $.process.run(
    [bash, '-c', 'export PATH="/usr/bin:/mingw64/bin:$PATH"; exec bash "$0" "$@"', script, ...args],
    { timeoutMs: 15000 },
  )
  return { ok: ran.exitCode === 0, out: ran.stdout.trim(), err: ran.stderr.trim(), code: ran.exitCode }
}

function parseList(out: string): TodoRow[] {
  const list: TodoRow[] = []
  for (const line of out.split(/\r?\n/)) {
    const m = line.match(/^(T\d+)\s+(.*?)(?:\s+\(상세 (\d+)줄\))?\s*$/)
    if (m) list.push({ id: m[1] ?? '', title: m[2] ?? '', lines: m[3] ? Number(m[3]) : 0 })
  }
  return list
}

async function refresh($: $) {
  const ran = await todo($, ['list'])
  await update($, message, () => (ran.ok ? '' : `todo.sh 실패(${ran.code}): ${ran.err}`))
  const list = parseList(ran.out)
  await update($, rows, () => list)
  const ids = new Set(list.map(r => r.id))
  if (!ids.has(await read($, opened))) {
    await update($, opened, () => '')
    await update($, detail, () => '')
  }
}

async function toggleDetail($: $, id: string) {
  if ((await read($, opened)) === id) {
    await update($, opened, () => '')
    await update($, detail, () => '')
    return
  }
  const ran = await todo($, ['show', id])
  const body = ran.out
    .split(/\r?\n/)
    .slice(1) // 첫 줄은 제목 줄이라 목록과 겹친다
    .map(l => l.replace(/^ {2}/, ''))
    .join('\n')
  await update($, opened, () => id)
  await update($, detail, () => (ran.ok ? body || '(상세 없음)' : `읽기 실패: ${ran.err}`))
}

export const register: Register = on => {
  on('session.start', async ($, e, next) => {
    await $.command.register({
      name: 'todo-list',
      description: '할 일 목록을 패널로 띄웁니다 (제목을 누르면 상세, Esc·q 로 닫기)',
    })
    return next(e)
  })

  on('command.run', { command: 'todo-list' }, async $ => {
    await refresh($)
    await $.ui.open({ id: PANE, title: '할 일', focus: true, closeOnEscape: true })
    return { text: `할 일 ${(await read($, rows)).length}개` }
  })

  // Claude 가 대화 중에 todo.sh 를 부르면 패널도 새로 읽는다.
  on('tool.call', { tool: 'Bash' }, async ($, e, next) => {
    const ran = await next(e)
    if (e.command.includes('todo.sh')) await refresh($)
    return ran
  })

  on('ui.render', { component: 'Pane', requestId: PANE }, async ($, e) => {
    const { Box, Text, Button } = $.ui.resolve(e)
    const list = await read($, rows)
    const openId = await read($, opened)
    const body = await read($, detail)
    const note = await read($, message)

    return (
      <Box flexDirection="column">
        {list.length === 0 && <Text dimColor>할 일이 없습니다.</Text>}
        {list.map(row => (
          <Box key={`box-${row.id}`} flexDirection="column">
            <Button
              key={`row-${row.id}`}
              label={`${row.id} ${row.title}`}
              plain
              onPress={() => toggleDetail($, row.id)}
            >
              <Text bold={row.id === openId}>
                {row.id === openId ? '▾ ' : '▸ '}
                {row.id} {row.title}
              </Text>
              <Text dimColor>{row.lines > 0 ? `  (${row.lines}줄)` : ''}</Text>
            </Button>
            {row.id === openId && (
              <Box paddingLeft={4}>
                <Text>{body}</Text>
              </Box>
            )}
          </Box>
        ))}
        {note !== '' && <Text dimColor>{note}</Text>}
        <Text> </Text>
        <Box flexDirection="row">
          <Button key="close" label="닫기" hotkey="q" plain onPress={() => $.ui.close({ id: PANE })}>
            닫기
          </Button>
          <Text dimColor>
            {e.props.isFocused
              ? '  Tab 으로 이동 · Enter 로 펼치기 · Esc 닫기'
              : '  클릭하거나 ctrl+x tab 으로 들어오기'}
          </Text>
        </Box>
      </Box>
    )
  })
}
