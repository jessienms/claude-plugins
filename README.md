# claude-plugins

[jessienms](https://github.com/jessienms)의 Claude Code 플러그인 마켓플레이스입니다.

## 설치

```
/plugin marketplace add jessienms/claude-plugins
/plugin install unity-worktree@jessienms-plugins
```

## 플러그인

### unity-worktree

Unity 프로젝트를 위한 **영속적이고 재사용 가능한 git worktree 폴더** 풀(예: `DevA`, `DevB`)을 관리합니다.

새로 만든 `git worktree`에서는 git이 추적하지 않는 모든 것 — `Library/`, `Temp/`, `obj/`, 아티팩트 데이터베이스 — 을 Unity가 다시 생성해야 하므로, 에디터를 처음 열 때 수 분이 걸릴 수 있습니다. 이 플러그인은 디스크에 물리적인 worktree 폴더를 캐시가 쌓인 상태 그대로 유지한 채, 각 폴더 안에서 체크아웃되는 브랜치만 교체합니다.

설치 후에는 Claude Code에게 자연스럽게 말하면 됩니다:

- "이 프로젝트에 재사용할 워크트리 두 개 만들어줘" → `init`
- "DevA에서 feature/inventory 작업 시작할게" → `start`
- "DevA 작업 끝났어, 브랜치는 원격까지 지워줘" → `finish`
- "워크트리 상태 보여줘" → `status`

요구 사항: git 저장소 안의 Unity 프로젝트, 그리고 bash(Git for Windows에 포함, macOS/Linux는 기본 제공).
