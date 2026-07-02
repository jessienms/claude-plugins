# statusline

Claude Code 하단에 **게이지형 status line**을 표시합니다.

```
Fable 5 | main ● | 15:07
Context    ████████░░░░░░░░░░░░ 42%
Usage      ███████░░░░░░░░░░░░░ 37% (리셋 17:13)
```

- **1줄**: 모델 이름 | git 브랜치 (linked worktree 이름, dirty ●/clean ✓ 표시) | 현재 시각
- **2줄**: Context — 컨텍스트 윈도우 사용률 (라벤더 그라데이션 게이지)
- **3줄**: Usage — 5시간 rate limit 사용률과 리셋 시각 (코럴 그라데이션 게이지)

## 설치

마켓플레이스를 아직 추가하지 않았다면 [메인 README](../../README.md)를 참고하세요.

```
/plugin install statusline@jessienms-plugins
/statusline:install
```

Claude Code는 플러그인이 status line 설정을 직접 주입하는 것을 지원하지 않으므로, 설치 후 `/statusline:install` 커맨드를 한 번 실행해야 합니다. 이 커맨드는:

1. 스크립트를 `~/.claude/statusline.sh`로 복사하고
2. `~/.claude/settings.json`에 `statusLine` 설정을 등록하며
3. jq가 없으면 OS별 설치 방법을 안내합니다

## 요구 사항

- bash (Git for Windows에 포함, macOS/Linux는 기본 제공)
- JSON 파서: jq 권장 — jq가 없는 Windows에서는 PowerShell로 자동 폴백합니다
  - Windows: `winget install jqlang.jq` (선택)
  - macOS: `brew install jq`
  - Linux: `sudo apt install jq`
