# google-chat-send

임의의 메시지·공지·알림을 **팀 Google Chat Space**로 전송하는 스킬입니다. "팀 채널에 보내줘", "구글챗에 공유해줘" 같은 요청을 받으면 Claude가 이 스킬을 통해 incoming webhook으로 메시지를 POST합니다.

- **단일 전송 지점**: 모든 에이전트/프롬프트가 같은 방식으로 같은 채널에 전송
- **named webhook**: 용도별 채널(QA, 디자인 등)을 이름 붙여 등록하고 골라 전송 — 지정 없으면 항상 default
- **중복 전송 방지**: `-Tag` 기반 전송 이력(`sent.log`)으로 같은 내용의 재전송을 자동 차단
- **비밀 보호**: webhook URL은 화면·로그·응답 어디에도 출력하지 않으며, 전송 전 항상 사용자 승인(AskUserQuestion)을 받도록 설계
- **길이 검증**: Google Chat text 제한(4,096자) 초과 시 전송 전에 중단

## 설치

마켓플레이스를 아직 추가하지 않았다면 [메인 README](../../README.md)를 참고하세요.

```
/plugin install google-chat-send@jessienms-plugins
```

## 초기 설정

설치 후 처음 사용할 때 Claude가 default webhook 설정을 안내합니다. 직접 설정하려면 Claude에게 "구글챗 webhook 설정해줘"라고 요청하고, Google Chat에서 발급받은 incoming webhook URL을 전달하면 됩니다.

- webhook URL 발급: Google Chat Space → 설정 → **앱 및 통합** → **웹훅 관리**
- 설정(비밀)과 전송 이력은 **현재 프로젝트**의 `.claude/google-chat/`에 저장됩니다
  (Codex판과 **같은 폴더를 공유**하므로, 양쪽을 다 쓰더라도 webhook은 한 번만 등록하면 됩니다)
- 프로젝트가 git 저장소라면 `.gitignore`에 `.claude/google-chat/`을 추가하세요 (webhook URL은 비밀입니다)

## 사용법 — 이렇게 말하면 됩니다

스킬은 요청 내용으로 **자동 로드**되며, `/google-chat-send:google-chat-send` 로 **수동 호출**할 수도 있습니다.

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
→ 같은 태그는 중복 전송으로 차단되므로, 재전송 여부를 물어본 뒤 -Force 로 보냅니다

> 구글챗 웹훅 설정 전부 지워줘
→ 먼저 삭제 대상 목록(dry-run)을 보여주고, 승인받은 뒤에만 실제로 삭제합니다
→ 전송 이력까지 지우려면 "이력도 같이 지워줘"라고 덧붙이세요
```

## 전송 승인 방식

전송 전에 항상 메시지 전문을 보여주고, **AskUserQuestion 선택지 UI**(`전송` / `수정하기` / `취소`)로 승인을 받은 뒤에만 전송합니다. 승인 후 본문이 한 글자라도 바뀌면 승인은 무효가 되어 다시 묻습니다.

> 데이터 폴더는 `$CLAUDE_PROJECT_DIR` 기준으로 잡히므로, 하위 폴더에서 작업 중이어도 프로젝트 루트의 설정을 그대로 사용합니다.

## 요구 사항

- PowerShell 7+ (`pwsh`) — Windows/macOS/Linux 모두 지원
- Google Chat Space의 incoming webhook URL
