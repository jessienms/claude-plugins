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
- 프로젝트가 git 저장소라면 `.gitignore`에 `.claude/google-chat/`을 추가하세요 (webhook URL은 비밀입니다)

## 사용 예

```
> 방금 커밋한 내용 요약해서 팀 채널에 공유해줘
> 빌드 올렸다고 구글챗으로 알려줘
> qa-team 채널로 버그 리포트 보내줘
```

전송 전에 항상 메시지 전문을 보여주고 승인을 받은 뒤에만 전송합니다.

## 요구 사항

- PowerShell 7+ (`pwsh`) — Windows/macOS/Linux 모두 지원
- Google Chat Space의 incoming webhook URL
