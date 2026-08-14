# statusline

Claude Code 하단에 **게이지형 status line**을 표시합니다.

```
Fable 5 | main ● | 15:07
Context    ████████░░░░░░░░░░░░ 42%
Usage      ███████░░░░░░░░░░░░░ 37% (리셋 17:13)
```

- **1줄**: 모델 이름 | git 브랜치 (linked worktree 이름, dirty ●/clean ✓ 표시) | 현재 시각
  - 워크트리에 색을 지정하면 이름 앞에 색 네모가 붙습니다 → `main (█ DevA) ✓`
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

## 워크트리 색상

워크트리를 여러 개 띄워놓고 작업할 때, 워크트리마다 색을 지정해두면 이름 앞에 그 색의 네모가 표시되어 지금 어디에 있는지 한눈에 구분됩니다.

```
/statusline:color                    # 현재 워크트리와 지정된 색 목록 조회
/statusline:color DevA #8AADF4       # hex 로 지정
/statusline:color DevA blue          # 프리셋 이름으로 지정
/statusline:color DevA --global      # 모든 프로젝트에 적용
/statusline:color DevA --clear       # 해제
```

색을 지정하지 않은 워크트리는 네모 없이 이름만 표시됩니다. 지정 후 **재설치 없이** 다음 렌더부터 바로 반영됩니다.

### 설정 파일

`statusline-worktree-colors` 파일을 직접 편집해도 됩니다. 두 위치를 **키 단위로 병합**하며, 프로젝트 값이 전역 값을 덮어씁니다.

| 우선순위 | 경로 |
|---|---|
| 1 | `<메인 체크아웃 루트>/.claude/statusline-worktree-colors` |
| 2 | `~/.claude/statusline-worktree-colors` |

```
# 주석은 이렇게
DevA=#8AADF4
DevB=green
hotfix=237;135;150
```

- 키는 **워크트리 폴더명**(브랜치명이 아님), 대소문자 구분 없음
- 값은 `#RRGGBB` / `#RGB` / `R;G;B` / 프리셋 이름
- 프리셋: `blue` `green` `red` `yellow` `mauve` `peach`(`orange`) `teal` `pink` `sky` `flamingo` `gray`
- 잘못된 값은 조용히 무시되어 네모만 생략됩니다

메인 체크아웃(linked worktree가 아닌 곳)에서는 워크트리 이름 자체가 표시되지 않으므로 네모도 나오지 않습니다.

## 요구 사항

- bash (Git for Windows에 포함, macOS/Linux는 기본 제공)
- JSON 파서: jq 권장 — jq가 없는 Windows에서는 PowerShell로 자동 폴백합니다
  - Windows: `winget install jqlang.jq` (선택)
  - macOS: `brew install jq`
  - Linux: `sudo apt install jq`
