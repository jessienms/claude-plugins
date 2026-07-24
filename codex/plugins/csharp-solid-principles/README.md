# C# SOLID 원칙 (csharp-solid-principles)

C# 코드에서 **SOLID 원칙**을 점검하고 적용하기 위한 스킬 플러그인입니다.
각 원칙(SRP, OCP, LSP, ISP, DIP)마다 **위반 예시 → 리팩터링 결과 → 감지 패턴**을
C# 관용구(속성, LINQ, EF Core, ASP.NET Core DI 등)로 제공합니다.

> 원본: [decebals/claude-code-java `solid-principles`](https://github.com/decebals/claude-code-java) (Java)
> 이 플러그인은 이를 **C#** 예제 + **한국어**로 옮긴 버전입니다.

---

## 설명

SOLID 원칙 체크리스트와 상세한 C# 예제. 각 원칙은 위반 예시, 리팩터링 해법,
감지 패턴을 포함합니다. 아키텍처 결정을 대신 내리는 도구가 아니라, 코드가 배포되기
전에 설계 냄새(design smell)를 잡아내고 리팩터링의 근거를 뒷받침하는 검증 도구입니다.

---

## 사용 시나리오

- "이 클래스에서 SOLID 위반 찾아줘"
- "이 클래스가 너무 많은 일을 하나?" (SRP)
- "코드 수정 없이 새 타입을 추가하려면?" (OCP)
- "왜 Square 가 Rectangle 을 상속하면 안 돼?" (LSP)
- "이 인터페이스가 너무 커" (ISP)
- "이걸 테스트 가능하게 만들려면?" (DIP)

---

## 다루는 원칙

| 원칙 | 핵심 질문 |
|-----------|--------------|
| **S**ingle Responsibility | 변경할 이유가 하나뿐인가? |
| **O**pen/Closed | 수정 없이 확장할 수 있는가? |
| **L**iskov Substitution | 하위 타입이 상위 타입을 대체할 수 있는가? |
| **I**nterface Segregation | 클라이언트가 쓰지 않는 메서드를 구현하도록 강요받는가? |
| **D**ependency Inversion | 추상화에 의존하는가? |

---

## 설치

터미널에서 이 마켓을 추가한 뒤 설치합니다 (`codex` 서브커맨드):

```bash
codex plugin marketplace add jessienms/claude-plugins
codex plugin add csharp-solid-principles@jessienms-codex-plugins
```

설치 후 **새 Codex 스레드**를 시작하면 로드됩니다. TUI에서는 `/plugins` 브라우저로도 설치할 수 있습니다.

---

## 동작 방식

설치 후에는 SOLID 관련 리뷰·리팩터링 요청 시 스킬의 `description` 매칭으로 **자동 로드**되며,
`$csharp-solid-principles` 로 **수동 호출**할 수도 있습니다.

두 가지 모드로 동작합니다:

- **리뷰 모드** — 기존 코드를 SOLID로 점검할 때. 작성자=리뷰어 편향을 억제하기 위해
  **독립 리뷰어 규율**(작성 맥락·애착을 버리고 코드 자체만 판단, 대상 파일 재독)로 리뷰하고,
  다섯 원칙 각각을 **별점 5점 만점**으로 평가한 리포트를 반환합니다.
  최대 객관성이 필요하면 **작성 이력이 없는 새 Codex 세션**에서 실행하세요.
- **참고 모드** — 코드를 작성·리팩터링하는 도중 원칙·예시를 물을 때. 인라인으로 바로 답합니다.

```
> "이 OrderService 를 SOLID 원칙으로 리뷰해줘"
→ SRP 위반을 식별하고, 검증·알림 로직 추출을 제안
→ 다섯 원칙 별점 요약 + 위반 상세 + 종합 평가 리포트 반환
```

---

## 관련 스킬

- `design-patterns` - 구현 패턴 (Factory, Strategy, Observer 등)
- `clean-code` - DRY, KISS, YAGNI
- `csharp-code-review` - 전체 리뷰 체크리스트

---

## 참고 자료

- [SOLID (Wikipedia)](https://en.wikipedia.org/wiki/SOLID)
- [Clean Code — Robert C. Martin](https://www.oreilly.com/library/view/clean-code-a/9780136083238/)
- [.NET 애플리케이션 아키텍처 가이드 (Microsoft)](https://learn.microsoft.com/dotnet/architecture/)

---

## 라이선스

MIT
