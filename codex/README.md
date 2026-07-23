# codex-plugins

[jessienms](https://github.com/jessienms)의 Codex CLI 플러그인 마켓플레이스입니다.

## 마켓플레이스 등록

마켓플레이스를 추가하세요 (레포 루트의 `.agents/plugins/marketplace.json`을 읽습니다):

```
/plugin marketplace add jessienms/claude-plugins
```

특정 브랜치·태그로 고정하려면:

```
/plugin marketplace add jessienms/claude-plugins@main     # 브랜치
/plugin marketplace add jessienms/claude-plugins#v1.0.0    # 태그
```

## 플러그인 설치

등록한 마켓(`jessienms-codex-plugins`)에서 이름으로 설치한 뒤 리로드하세요:

```
/plugin install csharp-solid-principles@jessienms-codex-plugins
/reload-plugins
```

또는 `/plugins` 를 실행해 브라우저 UI에서 설치할 수도 있습니다.

## 플러그인

| 플러그인 | 설명 |
|----------|------|
| [csharp-solid-principles](plugins/csharp-solid-principles/README.md) | C# 예제로 SOLID 원칙(SRP/OCP/LSP/ISP/DIP)을 점검하는 체크리스트 스킬 — 원칙별 위반 예시·리팩터링·감지 패턴 (한국어) |

## 라이선스

MIT
