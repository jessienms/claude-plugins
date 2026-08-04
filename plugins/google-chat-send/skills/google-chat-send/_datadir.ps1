#requires -Version 7
<#
.SYNOPSIS
  google-chat-send 의 데이터 폴더(비밀·상태) 위치를 결정하는 공통 로직.

.DESCRIPTION
  init/add/send/clearall 이 dot-source 해서 쓰는 헬퍼다. 단독 실행용이 아니다.

  `Resolve-GoogleChatDataDir` 은 아래 우선순위로 데이터 폴더를 정한다.

    1. `-DataDir` 이 지정되면 그대로 쓴다. (항상 최우선)
    2. 프로젝트 폴더에 `.claude/google-chat` 이 **이미 있으면** 그대로 쓴다.
       (이미 쓰고 있던 데이터 폴더를 말없이 옮기지 않는다)
    3. git 저장소면 **메인 체크아웃**의 `.claude/google-chat` 을 쓴다.
       worktree 나 하위 폴더에서 실행해도 메인에 등록해 둔 webhook 을 그대로 본다.
    4. 그 외(비 git 폴더, git 미설치)는 프로젝트 폴더 아래 `.claude/google-chat`.

  여기서 "프로젝트 폴더"는 `$env:CLAUDE_PROJECT_DIR`, 없으면 현재 작업 폴더다.

  3번이 있는 이유: `$env:CLAUDE_PROJECT_DIR` 는 worktree 안에서 작업하면 worktree 경로가
  된다. 상위 탐색이 없으면 메인에 등록해 둔 webhook 을 전혀 보지 못하고 worktree 밑에
  빈 데이터 폴더를 새로 만들어, 비밀이 흩어지거나 "설정이 있는데 없다고 나오는" 혼란이 생긴다.
#>

function Get-GitMainWorktreeRoot {
    <#
    .SYNOPSIS
      $StartDir 이 속한 git 저장소의 메인 체크아웃 루트를 돌려준다. 아니면 $null.
    #>
    [CmdletBinding()]
    param([Parameter(Mandatory)][string]$StartDir)

    # git 호출은 "실패하면 폴백" 이 정상 경로다. 호출 스크립트의 Stop 설정과
    # PowerShell 7.4+ 의 네이티브 명령 오류 승격을 이 함수 안에서만 꺼 둔다.
    $ErrorActionPreference = 'SilentlyContinue'
    $PSNativeCommandUseErrorActionPreference = $false

    if ([string]::IsNullOrWhiteSpace($StartDir)) { return $null }
    if (-not (Test-Path -LiteralPath $StartDir -PathType Container)) { return $null }
    if (-not (Get-Command git -CommandType Application -ErrorAction SilentlyContinue)) { return $null }

    # --git-common-dir 은 main / worktree 어디서 실행하든 "메인 저장소의 .git" 을 가리킨다.
    #   메인 루트에서   → `.git`      (상대)
    #   저장소 하위폴더 → `../.git`   (상대)
    #   worktree 에서   → 절대경로
    #   비 git 폴더     → exit 128
    # 절대경로를 강제하는 --path-format=absolute 는 git 2.31+ 전용인데, 미지원 버전은
    # 오류 대신 그 인자를 출력에 그대로 얹고 exit 0 을 내서 결과를 오염시킨다.
    # 상대경로는 어차피 -C 로 넘긴 $StartDir 기준이라 아래에서 정확히 풀 수 있으므로 쓰지 않는다.
    $commonDir = (& git -C $StartDir rev-parse --git-common-dir 2>$null | Select-Object -Last 1)
    if ($LASTEXITCODE -ne 0 -or [string]::IsNullOrWhiteSpace($commonDir)) { return $null }

    $commonDir = $commonDir.Trim()
    if (-not [System.IO.Path]::IsPathRooted($commonDir)) {
        $commonDir = Join-Path $StartDir $commonDir
    }
    try { $commonDir = [System.IO.Path]::GetFullPath($commonDir) } catch { return $null }

    # 메인 체크아웃 루트 = 그 `.git` 의 부모. 여기서 걸러지는 것들:
    #   bare 저장소(`repo.git`)     — 작업 트리가 없다
    #   서브모듈(`.git/modules/x`)  — 부모가 작업 트리가 아니다
    # 둘 다 $null 을 돌려 호출부가 기존 동작으로 폴백하게 한다.
    if ((Split-Path -Leaf $commonDir) -ne '.git') { return $null }
    $root = Split-Path -Parent $commonDir
    if ([string]::IsNullOrWhiteSpace($root)) { return $null }
    if (-not (Test-Path -LiteralPath $root -PathType Container)) { return $null }
    return $root
}

function Resolve-GoogleChatDataDir {
    <#
    .SYNOPSIS
      데이터 폴더 경로와 "어느 규칙으로 결정됐는지"를 함께 돌려준다.

    .OUTPUTS
      Path (string), Rule (string) 을 가진 객체.
    #>
    [CmdletBinding()]
    param([string]$DataDir = "")

    # 1. 명시 지정 — 항상 최우선.
    if (-not [string]::IsNullOrWhiteSpace($DataDir)) {
        return [pscustomobject]@{
            Path = $DataDir
            Rule = '-DataDir 로 직접 지정한 경로'
        }
    }

    $projectRoot = [string]::IsNullOrWhiteSpace($env:CLAUDE_PROJECT_DIR) ? (Get-Location).Path : $env:CLAUDE_PROJECT_DIR
    try { $projectRoot = [System.IO.Path]::GetFullPath($projectRoot) } catch { }
    $localDir = Join-Path $projectRoot '.claude' 'google-chat'

    # 2. 기존 설치 하위호환 — 이미 쓰고 있는 폴더는 옮기지 않는다.
    if (Test-Path -LiteralPath $localDir -PathType Container) {
        return [pscustomobject]@{
            Path = $localDir
            Rule = "프로젝트 폴더에 이미 있는 데이터 폴더 ($projectRoot)"
        }
    }

    # 3. git 저장소면 메인 체크아웃 — worktree/하위 폴더에서도 같은 설정을 공유한다.
    $mainRoot = Get-GitMainWorktreeRoot -StartDir $projectRoot
    if ($mainRoot) {
        $sameRoot = $projectRoot.TrimEnd('\', '/') -ieq $mainRoot.TrimEnd('\', '/')
        return [pscustomobject]@{
            Path = Join-Path $mainRoot '.claude' 'google-chat'
            Rule = $sameRoot ?
                "git 저장소 루트 ($mainRoot)" :
                "git 메인 체크아웃 ($mainRoot) — worktree/하위 폴더에서 실행 중이라 메인의 설정을 공유한다"
        }
    }

    # 4. 폴백 — 비 git 폴더이거나 git 이 없다. 기존 동작 그대로.
    return [pscustomobject]@{
        Path = $localDir
        Rule = "프로젝트 폴더 기본값 ($projectRoot) — git 저장소가 아니다"
    }
}
