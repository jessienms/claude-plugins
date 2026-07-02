# claude-plugins

Claude Code plugin marketplace by [jessienms](https://github.com/jessienms).

## Installation

```
/plugin marketplace add jessienms/claude-plugins
/plugin install unity-worktree@jessienms-plugins
```

## Plugins

### unity-worktree

Manage a small pool of **persistent, reusable git worktree folders** (e.g. `DevA`, `DevB`) for a Unity project.

A fresh `git worktree` forces Unity to regenerate everything git does not track — `Library/`, `Temp/`, `obj/`, the artifact database — which can take many minutes on first editor open. This plugin keeps a fixed set of worktree folders alive with their warm caches, and only swaps which branch is checked out inside each folder.

Once installed, just talk to Claude Code naturally:

- "이 프로젝트에 재사용할 워크트리 두 개 만들어줘" → `init`
- "DevA에서 feature/inventory 작업 시작할게" → `start`
- "DevA 작업 끝났어, 브랜치는 원격까지 지워줘" → `finish`
- "워크트리 상태 보여줘" → `status`

Requirements: a Unity project in a git repository, and bash (ships with Git for Windows; native on macOS/Linux).
