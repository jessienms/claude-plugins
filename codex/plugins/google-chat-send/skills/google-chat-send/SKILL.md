---
name: google-chat-send
description: 임의의 메시지·공지·공유 알림을 팀 Google Chat Space 로 전송한다. 공용 webhook 설정을 쓰는 단일 전송 지점이며, "팀 채널에 보내줘", "구글챗에 공유해줘", "같은 채널로 알려줘", "팀에 전송" 등 자유 형식 메시지를 팀 채팅방에 보내야 할 때 사용한다. 용도별 named webhook 을 등록해 골라 보낼 수 있고, 호출자가 언급하지 않으면 항상 default webhook 을 사용한다. 메시지 본문은 호출자가 완성해서 넘긴다(내용 작성·판단은 이 스킬의 몫이 아니다).
---

# google-chat-send — 팀 Google Chat 전송 스킬 (Codex판)

팀이 공유하는 단일 Google Chat Space 로 **임의의 메시지를 전송**하는 범용 스킬이다.
전송 **코드**(`send.ps1` 등)는 이 스킬 폴더(플러그인 설치 경로)에 있고, **비밀·런타임 상태**
(webhook.url, sent.log)는 **현재 프로젝트**의 데이터 폴더 `.claude/google-chat/` 에 둔다.
이 스킬을 쓰는 모든 프롬프트가 같은 채널·같은 방식으로 전송한다.

> 아래 명령 예시의 `<skill-dir>` 은 이 SKILL.md 가 있는 폴더(플러그인 설치 경로)를 뜻한다.
> 실행 시 실제 절대 경로로 치환해서 호출한다.

> **데이터 폴더 이름이 `.claude/` 인 이유**: 같은 프로젝트를 Claude Code 와 Codex 양쪽에서
> 쓸 때 webhook 을 두 번 등록하지 않도록 **동일한 데이터 폴더를 공유**한다. Codex 전용
> 프로젝트라도 경로는 그대로 `.claude/google-chat/` 이다(이름만 그럴 뿐 Codex 에서 정상 동작한다).

## 이 스킬이 하는 일 / 하지 않는 일

- **한다**: 완성된 메시지 본문(파일 또는 문자열)을 받아 Google Chat Space 로 POST 하고
  `sent.log` 에 기록한다.
- **하지 않는다**: 메시지 내용 작성·수신자 필터·전송 여부 판단을 하지 않는다. 그건 호출자(메인
  대화)의 몫이다. 이 스킬은 어떤 호출자가 쓰는지에 대해 독립적이다.

## 구성

코드(스킬 폴더)와 비밀·상태(프로젝트 데이터 폴더)를 분리한다.

| 위치 | 파일 | 설명 |
|------|------|------|
| `<skill-dir>/` | `send.ps1`  | 전송 어댑터(코드). webhook 파일을 읽어 Google Chat 으로 POST. |
| `<skill-dir>/` | `init.ps1`  | 초기 설정·상태 점검. default webhook 설정(`-Url`), 등록 webhook 목록 출력. |
| `<skill-dir>/` | `add.ps1`   | named webhook 등록(`-Name`/`-Purpose`/`-Url`). |
| `<skill-dir>/` | `clearall.ps1` | 모든 webhook 설정 삭제(초기화). 기본 dry-run, `-Yes` 로 실제 삭제. |
| `<skill-dir>/` | `_datadir.ps1` | 데이터 폴더 위치 결정 공통 로직. 위 스크립트들이 읽어 쓴다(직접 실행하지 않는다). |
| `<프로젝트>/.claude/google-chat/` | `webhook.url`        | **(비밀)** default webhook. 절대 출력/로그/커밋 금지. |
| `<프로젝트>/.claude/google-chat/` | `webhook.<이름>.url` | **(비밀)** named webhook (add.ps1 로 등록). 동일하게 출력 금지. |
| `<프로젝트>/.claude/google-chat/` | `webhooks.meta.tsv`  | named webhook 의 용도 메타(`이름 \t 용도`). URL 은 없음. |
| `<프로젝트>/.claude/google-chat/` | `sent.log`           | 전송 이력(`시각 \t Tag \t sent \t webhook이름`). 중복 전송 추적용. |

> **데이터 폴더 위치 결정** (모든 스크립트 공통, `_datadir.ps1`). "프로젝트 폴더" 는
> `$env:CLAUDE_PROJECT_DIR` 이 있으면 그 아래, 없으면 **현재 작업 폴더**다 — Codex 에는 보통
> 그 환경변수가 없으므로 현재 작업 폴더가 기준이 된다. 아래 순서로 결정한다.
>
> 1. `-DataDir <경로>` 를 주면 그대로 쓴다. (항상 최우선)
> 2. 프로젝트 폴더에 `.claude/google-chat` 이 **이미 있으면** 그대로 쓴다.
> 3. git 저장소면 **메인 체크아웃**의 `.claude/google-chat` 을 쓴다.
> 4. 그 외(비 git 폴더, git 미설치)는 프로젝트 폴더 아래 `.claude/google-chat`.
>
> 3번 덕분에 **저장소 하위 폴더에서 실행하거나 git worktree 안에서 작업해도 메인 체크아웃에
> 등록해 둔 webhook 을 그대로 본다.** 예전처럼 `-DataDir` 을 손으로 붙일 필요는 없다.
>
> 어느 폴더가 왜 선택됐는지는 `init.ps1` 이 `경로 결정 규칙` 줄로 함께 출력한다.
> 위치가 예상과 다르면 **`-DataDir` 을 붙이기 전에 그 줄을 먼저 확인한다.** (worktree/하위
> 폴더에 실수로 만들어진 빈 데이터 폴더가 2번 규칙에 걸려 메인을 가리고 있을 수 있다 —
> 그 폴더를 지우면 3번 규칙이 적용된다.)
>
> **커밋 금지**: 데이터 폴더에는 비밀(webhook URL)이 들어 있으므로, 프로젝트가 git 저장소라면
> `.gitignore` 에 `.claude/google-chat/` 이 있는지 확인하고 없으면 추가한다.

## 초기 설정 (init) — 스킬 설치 직후 / 처음 사용 시

이 스킬을 **처음 사용하기 전(또는 전송이 webhook 부재로 실패하면)** 아래 절차로 default webhook
존재를 판단하고, 없으면 설정을 받는다.

1. `pwsh "<skill-dir>/init.ps1"` 실행 — 상태를 출력하고, default webhook 이
   없으면 **exit 1** 로 끝난다.
2. exit 1 이면 사용자에게 Google Chat incoming webhook URL 을 요청한다.
   (URL 은 비밀이므로 받은 값을 응답·로그에 되풀이해 출력하지 않는다.)
3. `pwsh "<skill-dir>/init.ps1" -Url "<받은 URL>"` 로 저장한 뒤,
   다시 init.ps1 을 실행해 "설정됨"을 확인한다.
4. 이미 설정된 default 를 교체할 때만 `-Force` 를 쓴다(사용자 요청이 있을 때만).

## webhook 추가 (add) — 여러 채널 운용

default 외에 용도별 webhook 을 이름을 붙여 등록할 수 있다.

```powershell
pwsh "<skill-dir>/add.ps1" -Name qa-team -Purpose "QA 팀 채널 — 버그 리포트 공유용" -Url "<webhook URL>"
```

- 이름은 영문 소문자/숫자/하이픈/언더스코어만. `default` 는 예약어(= `webhook.url`, init 으로 관리).
- 용도(`-Purpose`)는 `webhooks.meta.tsv` 에 기록되어 init.ps1 상태 출력에서 확인할 수 있다.
- 같은 이름 교체는 `-Force`. 제거는 데이터 폴더의 `webhook.<이름>.url` 파일과
  `webhooks.meta.tsv` 의 해당 줄을 지우면 된다.
- 사용자가 이름 없이 용도만 말하면(예: "이 웹훅 QA 버그 공유용으로 추가해줘") 용도에서 유추한
  이름을 제안하고(예: `qa-team`) 확인을 받은 뒤 등록한다.

**webhook 선택 정책**: 호출자가 특정 webhook 을 명시하면 `send.ps1 -Webhook <이름>` 으로
전송하고, **아무 언급이 없으면 항상 default 를 사용한다.** 어느 채널로 보낼지 애매하면
등록된 webhook 목록(이름·용도)을 보여주고 사용자에게 확인받은 뒤 전송한다.

## 전체 초기화 (clearall)

모든 webhook 설정(default + named + 용도 메타)을 지우고 초기 상태로 되돌린다.
**되돌릴 수 없는 파괴적 작업**이므로 아래 절차를 반드시 지킨다.

1. `pwsh "<skill-dir>/clearall.ps1"` (dry-run) 로 삭제 대상 목록을 먼저 확인한다.
2. 그 목록을 사용자에게 보여주고 **초기화 여부를 명시적으로 확인**받는다.
3. 승인 시에만 `clearall.ps1 -Yes` 로 실제 삭제한다.

- 전송 이력(`sent.log`)은 webhook 설정이 아니므로 기본 보존된다. 사용자가 이력까지 지우길
  원할 때만 `-IncludeLog` 를 함께 지정한다.
- 초기화 후에는 default webhook 이 없으므로, 다음 사용 시 "초기 설정 (init)" 절차가 다시 적용된다.

## 전송 방법

### 1) 짧은 메시지 — 문자열 직접 전달
```powershell
pwsh "<skill-dir>/send.ps1" -Message "공유폴더 \\share\build 에 빌드 X 를 올렸습니다." -Tag "build-x"
```

### 2) 긴 메시지 — 본문 파일 전달 (멀티라인·서식 보존에 권장)
```powershell
# 본문을 임시 파일로 저장한 뒤 파일 경로를 넘긴다.
pwsh "<skill-dir>/send.ps1" -MessageFile <본문파일경로> -Tag "<식별태그>"
```

### 3) named webhook 으로 전송 — `-Webhook <이름>`
```powershell
pwsh "<skill-dir>/send.ps1" -Message "빌드 완료" -Tag "build-x" -Webhook qa-team
```
- `-Tag` 는 `sent.log` 에 남길 식별자(커밋 rev, 작업명 등). 생략 가능하지만 권장.
- 성공 시 `전송 완료 (Tag: ...)` 를 출력한다. webhook URL 은 출력되지 않는다(실패 시에도
  상태 코드만 정제해 출력).
- 같은 `-Tag` 가 이미 `sent.log` 에 있으면 중복 전송으로 보고 **자동 중단**한다. 의도적인
  재전송이면 `-Force` 를 붙인다.
- 본문은 최대 **4,096자**(Google Chat text 메시지 제한). 초과 시 전송 전에 에러로 중단되므로
  본문을 줄이거나 나눠 보낸다.

## 운영 원칙 (반드시 지킬 것)

1. **사용자 승인 전 전송 금지.** 외부로 나가는 메시지이므로, 메시지 전문을 사용자에게 먼저 보여주고
   명시적 승인을 받은 뒤에만 `send.ps1` 을 실행한다.

   Codex 에는 선택지 UI 도구(예: Claude Code 의 AskUserQuestion)가 없다. 대신 아래 **승인 규율**을
   지킨다 — 이것이 외부 전송을 막는 **유일한 안전장치**이므로 어떤 경우에도 건너뛰지 않는다.

   - **순서**: ① 전송될 본문을 **한 글자도 빠짐없이 그대로** 보여준다(요약·발췌 금지) →
     ② 어느 webhook 으로 보내는지(default / named 이름)와 `-Tag` 를 함께 명시한다 →
     ③ "이대로 전송할까요? (전송 / 수정 / 취소)" 로 묻고 **턴을 끝내 사용자 답변을 기다린다** →
     ④ 사용자가 전송을 선택한 그 다음 턴에만 `send.ps1` 을 실행한다.
   - **같은 턴에 '보여주고 바로 전송'하지 않는다.** 승인 질문을 출력한 뒤 이어서 명령을 실행하는
     것은 승인이 아니다. 반드시 사용자 응답을 받은 뒤 실행한다.
   - **Codex 의 승인 정책이 자동 실행(full-auto / 샌드박스 우회 등)으로 설정돼 있어도 마찬가지다.**
     쉘 명령이 자동 승인된다는 것은 "사용자가 전송에 동의했다"는 뜻이 아니다. 승인은 항상
     대화에서 명시적으로 받는다.
   - **승인은 한 번이면 된다.** 호출자 절차가 **전송될 본문 전문 그대로**에 대해 이미 명시적
     승인을 받았다면 그 승인이 유효하다 — 다시 묻지 않고 바로 전송한다. 단, 승인 후 본문이
     한 글자라도 바뀌었다면 승인은 무효이며 수정된 전문으로 다시 받는다.
   - 중복 Tag 로 차단되어 재전송 여부를 물어야 할 때도 같은 방식으로 묻고, 승인 시 `-Force` 를
     붙여 실행한다.
2. **webhook 비밀 보호.** `webhook.url` 의 내용을 화면·로그·커밋·응답 어디에도 출력하지 않는다.
   전송은 항상 `send.ps1` 을 경유한다(스크립트가 URL 을 자체적으로 읽으므로 노출되지 않는다).
   사용자가 대화에 붙여넣은 URL 도 되풀이해 출력하지 않는다.
3. **중복 전송 확인.** 같은 `Tag` 재전송은 `send.ps1` 이 자동으로 막는다. 사용자가 재전송을
   명시적으로 원할 때만 `-Force` 를 사용한다.
4. **AI 작성 고지(권장).** 사람이 검토하기 전 AI 가 작성한 본문이라면, 메시지 말미에 AI 작성 안내
   문구를 포함하는 것을 권장한다.
