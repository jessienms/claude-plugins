---
description: 게이지형 status line을 설치합니다 (스크립트 복사 + settings.json 등록)
---

# Statusline Gauges 설치

이 플러그인에 동봉된 status line 스크립트를 사용자 환경에 설치한다. 다음 단계를 순서대로 수행할 것:

1. **스크립트 복사**: `${CLAUDE_PLUGIN_ROOT}/scripts/statusline.sh`를 `~/.claude/statusline.sh`로 복사한다. macOS/Linux에서는 `chmod +x ~/.claude/statusline.sh`로 실행 권한을 준다.

2. **settings.json 등록**: `~/.claude/settings.json`을 읽는다.
   - 파일이 없으면 새로 만든다.
   - 이미 `statusLine` 항목이 있고 `~/.claude/statusline.sh`를 가리키는 것이 아니면, 기존 설정을 보여주고 덮어쓸지 사용자에게 확인한다.
   - 기존의 다른 설정은 모두 보존한 채 `statusLine`만 다음 값으로 설정한다:
     ```json
     {
       "statusLine": {
         "type": "command",
         "command": "bash ~/.claude/statusline.sh"
       }
     }
     ```

3. **JSON 파서 확인**: `command -v jq`로 jq 설치 여부를 확인한다.
   - jq가 있으면: 추가 조치 불필요.
   - jq가 없고 Windows이면: PowerShell 폴백으로 동작하므로 그대로 사용 가능하다고 안내하되, jq를 설치하면(`winget install jqlang.jq`) 더 빠르다고 알려준다.
   - jq가 없고 macOS/Linux이면: jq 설치가 필요하다고 안내한다 (`brew install jq` 또는 `sudo apt install jq`).

4. **완료 안내**: 설치가 끝나면 status line은 새 세션 또는 다음 응답부터 표시된다고 안내한다. 표시 내용도 간단히 설명한다:
   - 1줄: 모델 이름 | git 브랜치 (worktree 이름, dirty ●/clean ✓) | 현재 시각
   - 2줄: Context — 컨텍스트 윈도우 사용률 게이지
   - 3줄: Usage — 5시간 rate limit 사용률 게이지와 리셋 시각
