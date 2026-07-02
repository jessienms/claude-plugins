# unity-worktree

Unity 프로젝트를 위한 **영속적이고 재사용 가능한 git worktree 폴더** 풀(예: `DevA`, `DevB`)을 관리합니다.

새로 만든 `git worktree`에서는 git이 추적하지 않는 모든 것 — `Library/`, `Temp/`, `obj/`, 아티팩트 데이터베이스 — 을 Unity가 다시 생성해야 하므로, 에디터를 처음 열 때 수 분이 걸릴 수 있습니다. 이 플러그인은 디스크에 물리적인 worktree 폴더를 캐시가 쌓인 상태 그대로 유지한 채, 각 폴더 안에서 체크아웃되는 브랜치만 교체합니다.

## 설치

마켓플레이스를 아직 추가하지 않았다면 [메인 README](../../README.md)를 참고하세요.

```
/plugin install unity-worktree@jessienms-plugins
```

## 사용법

설치 후에는 Claude Code에게 자연스럽게 말하면 됩니다:

- "이 프로젝트에 재사용할 워크트리 두 개 만들어줘" → `init`
- "DevA에서 feature/inventory 작업 시작할게" → `start`
- "DevA 작업 끝났어, 브랜치는 원격까지 지워줘" → `finish`
- "워크트리 상태 보여줘" → `status`

### 시나리오: 기능 개발 중 긴급 수정 끼어들기

인벤토리 기능을 개발하던 중 라이브 버그 제보가 들어온 상황입니다. 워크트리 풀이 있으면 진행 중인 작업을 건드리지 않고 다른 폴더에서 바로 수정 작업을 시작할 수 있습니다 — Unity 재임포트 없이.

1. **기능 개발 시작**

   > "DevA에서 feature/inventory 브랜치로 작업 시작할게"

   DevA가 `feature/inventory`를 체크아웃하고, 세션이 DevA 폴더로 이동합니다.

2. **긴급 버그 제보 — 하던 작업은 그대로 두고 끼어들기**

   > "라이브에서 상점 결제 버그가 터졌대. DevB에서 hotfix/shop-purchase 브랜치로 작업하자"

   DevA는 작업 중인 상태 그대로 남아 있고, DevB가 `hotfix/shop-purchase`를 체크아웃합니다. DevB의 `Library/` 캐시가 살아 있으므로 Unity 에디터를 바로 열어 확인할 수 있습니다.

3. **핫픽스 마무리**

   > "핫픽스 머지됐어. DevB 정리하고 브랜치는 원격까지 지워줘"

   DevB는 임시 브랜치로 돌아가 유휴 상태가 되고(폴더와 캐시는 유지), `hotfix/shop-purchase`는 로컬과 원격에서 삭제됩니다.

4. **원래 작업으로 복귀**

   > "다시 DevA에서 인벤토리 작업 이어서 하자"

   DevA는 그동안 아무것도 바뀌지 않았으므로, 중단했던 지점에서 그대로 이어집니다.

중간에 현황이 궁금하면 언제든지:

> "워크트리 상태 보여줘"

```
DevA  busy  feature/inventory
DevB  idle  temp/b
```

## 요구 사항

- git 저장소 안의 Unity 프로젝트
- bash (Git for Windows에 포함, macOS/Linux는 기본 제공)
