# codex-plugins

[jessienms](https://github.com/jessienms)의 Codex CLI 플러그인 마켓플레이스입니다.

> 명령은 TUI 슬래시 명령이 아니라 터미널의 `codex` 서브커맨드입니다.
> TUI 안에서는 `/plugins` 브라우저로 설치·토글할 수도 있습니다.

## 마켓플레이스 등록

이 레포의 Git 마켓을 추가하세요 (레포 루트의 `.agents/plugins/marketplace.json`을 읽습니다):

```bash
codex plugin marketplace add jessienms/claude-plugins
# 특정 브랜치/태그로 고정하려면
codex plugin marketplace add jessienms/claude-plugins --ref main
```

등록된 마켓 확인:

```bash
codex plugin marketplace list
```

## 플러그인 설치

마켓 이름(`jessienms-codex-plugins`)을 붙여 설치합니다:

```bash
codex plugin add csharp-solid-principles@jessienms-codex-plugins
```

설치 후 **새 Codex 스레드**를 시작하면 스킬·도구가 로드됩니다.
설치된 플러그인은 `codex plugin list` 로 확인합니다.

## 플러그인

| 플러그인 | 설명 |
|----------|------|
| [csharp-solid-principles](plugins/csharp-solid-principles/README.md) | C# 예제로 SOLID 원칙(SRP/OCP/LSP/ISP/DIP)을 점검하는 체크리스트 스킬 — 원칙별 위반 예시·리팩터링·감지 패턴 (한국어) |

## 라이선스

MIT
