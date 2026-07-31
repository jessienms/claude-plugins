# Google Chat 전송 (google-chat-send)

임의의 메시지·공지·알림을 **팀 Google Chat Space**로 전송하는 스킬 플러그인입니다.
"팀 채널에 보내줘", "구글챗에 공유해줘" 같은 요청을 받으면 Codex가 이 스킬을 통해
incoming webhook으로 메시지를 POST합니다.

- **단일 전송 지점**: 모든 프롬프트가 같은 방식으로 같은 채널에 전송
- **named webhook**: 용도별 채널(QA, 디자인 등)을 이름 붙여 등록하고 골라 전송 — 지정 없으면 항상 default
- **중복 전송 방지**: `-Tag` 기반 전송 이력(`sent.log`)으로 같은 내용의 재전송을 자동 차단
- **비밀 보호**: webhook URL은 화면·로그·응답 어디에도 출력하지 않음
- **전송 전 승인**: 메시지 전문을 보여주고 사용자 승인을 받은 **다음 턴**에만 전송
- **길이 검증**: Google Chat text 제한(4,096자) 초과 시 전송 전에 중단

---

## 설치

터미널에서 이 마켓을 추가한 뒤 설치합니다 (`codex` 서브커맨드):

```bash
codex plugin marketplace add jessienms/claude-plugins
codex plugin add google-chat-send@jessienms-codex-plugins
```

설치 후 **새 Codex 스레드**를 시작하면 로드됩니다. TUI에서는 `/plugins` 브라우저로도 설치할 수 있습니다.

---

## 초기 설정

설치 후 처음 사용할 때 Codex가 default webhook 설정을 안내합니다.
Google Chat에서 발급받은 incoming webhook URL을 전달하면 됩니다.

- webhook URL 발급: Google Chat Space → 설정 → **앱 및 통합** → **웹훅 관리**
- 설정(비밀)과 전송 이력은 **현재 프로젝트**의 `.claude/google-chat/`에 저장됩니다
  (Claude Code판과 **같은 폴더를 공유**하므로, 양쪽을 다 쓰더라도 webhook은 한 번만 등록하면 됩니다)
- 프로젝트가 git 저장소라면 `.gitignore`에 `.claude/google-chat/`을 추가하세요 (webhook URL은 비밀입니다)

---

## 사용법 — 이렇게 말하면 됩니다

스킬은 요청 내용으로 **자동 로드**되며, `$google-chat-send` 로 **수동 호출**할 수도 있습니다.

### 1) 처음 설정하기

```
> 구글챗 webhook 설정해줘
→ 아직 설정된 게 없으니 incoming webhook URL을 요청합니다
→ URL을 붙여넣으면 저장하고 "설정됨"을 확인해줍니다

> 구글챗 설정 상태 확인해줘
→ default webhook 설정 여부 + 등록된 named webhook 목록(이름·용도)을 보여줍니다
```

### 2) 용도별 채널(named webhook) 추가하기

```
> 이 웹훅을 QA팀 버그 리포트 공유용으로 추가해줘
  https://chat.googleapis.com/v1/spaces/...
→ 용도에서 이름(qa-team)을 제안하고, 확인 후 등록합니다

> 이 웹훅을 디자인팀에 시안 공유하는 용도로 등록해줘. 이름은 design 으로.
→ -Name design -Purpose "디자인팀 시안 공유용" 으로 등록합니다

> 지금 등록된 구글챗 채널 뭐뭐 있어?
→ 이름과 용도만 보여줍니다 (URL은 절대 출력하지 않습니다)

> qa-team 웹훅 주소 바뀌었어. 이 URL로 교체해줘: https://chat.googleapis.com/...
→ -Force 로 덮어씁니다
```

### 3) 메시지 보내기

```
> 방금 커밋한 내용 요약해서 팀 채널에 공유해줘
> 빌드 올렸다고 구글챗으로 알려줘. 공유폴더 경로도 같이.
> 이번 스프린트 회고 정리해서 팀에 전송해줘

> qa-team 채널로 이 버그 리포트 보내줘
> 디자인 채널에 시안 링크 공유해줘
→ 채널을 지정하지 않으면 항상 default 로 보냅니다
```

### 4) 재전송 / 초기화

```
> 아까 보낸 빌드 공지 다시 보내줘
→ 같은 태그는 중복 전송으로 차단되므로, 재전송 여부를 확인한 뒤 -Force 로 보냅니다

> 구글챗 웹훅 설정 전부 지워줘
→ 먼저 삭제 대상 목록(dry-run)을 보여주고, 확인받은 뒤에만 실제로 삭제합니다
→ 전송 이력까지 지우려면 "이력도 같이 지워줘"라고 덧붙이세요
```

---

## Codex에서 쓸 때 알아둘 점

- **전송은 항상 두 턴에 걸쳐 일어납니다.** Codex에는 Claude Code의 선택지 UI(AskUserQuestion)가
  없으므로, 스킬은 ① 보낼 본문 전문 + 대상 채널 + 태그를 보여주고 턴을 끝낸 뒤
  ② 사용자가 "전송"이라고 답한 다음 턴에만 실제로 POST합니다. 같은 턴에 보여주고 바로 보내지 않습니다.
- **승인 정책을 full-auto로 두어도 전송은 자동으로 되지 않습니다.** 쉘 명령이 자동 승인되는 것과
  "메시지를 보내도 좋다"는 승인은 별개이며, 스킬은 후자를 항상 대화에서 명시적으로 받습니다.
- **프로젝트 루트에서 실행하세요.** Codex에는 `CLAUDE_PROJECT_DIR` 같은 프로젝트 루트 변수가 없어
  스크립트는 **현재 작업 폴더** 아래 `.claude/google-chat/`을 데이터 폴더로 봅니다. 하위 폴더에서
  작업 중이라면 "데이터 폴더는 `<프로젝트루트>/.claude/google-chat` 이야"라고 알려주면
  `-DataDir`로 지정해 실행합니다.
- **webhook URL을 대화에 붙여넣으면 세션 기록에는 남습니다.** 스킬은 URL을 응답에 되풀이해
  출력하지 않지만, 입력 자체는 Codex 세션 로그에 저장된다는 점을 감안하세요.

---

## 요구 사항

- PowerShell 7+ (`pwsh`) — Windows/macOS/Linux 모두 지원
- Google Chat Space의 incoming webhook URL

---

## 라이선스

MIT
