#requires -Version 7
<#
.SYNOPSIS
  google-chat-send 초기 설정(default webhook) + 상태 점검.

.DESCRIPTION
  프로젝트 데이터 폴더(.claude/google-chat)와 default webhook(webhook.url)의 존재를 점검한다.
  -Url 을 주면 default webhook 을 설정(생성)한다. webhook URL 은 어디에도 출력하지 않는다.
  인자 없이 실행하면 상태만 출력하며, default webhook 이 없으면 종료 코드 1 로 끝난다
  (스킬 설치 직후 "설정 필요 여부" 판단용).

.PARAMETER Url
  default webhook 으로 저장할 Google Chat incoming webhook URL.

.PARAMETER Force
  이미 default webhook 이 설정돼 있어도 덮어쓴다.

.PARAMETER DataDir
  비밀·로그가 위치한 데이터 폴더. 기본값은 `$env:CLAUDE_PROJECT_DIR`
  (없으면 현재 작업 폴더) 아래 `.claude/google-chat`.

.EXAMPLE
  pwsh init.ps1
  # 상태 점검. default webhook 미설정이면 exit 1.

.EXAMPLE
  pwsh init.ps1 -Url "https://chat.googleapis.com/v1/spaces/..."
#>
[CmdletBinding()]
param(
    [string]$Url = "",
    [switch]$Force,
    [string]$DataDir = ""
)

$ErrorActionPreference = 'Stop'

# 데이터 폴더(비밀·로그) 위치 결정: 프로젝트의 .claude/google-chat 가 기본.
# (스킬 폴더는 플러그인 설치 캐시라 업데이트 시 갈리므로 비밀·상태를 두지 않는다)
if ([string]::IsNullOrWhiteSpace($DataDir)) {
    $projectRoot = [string]::IsNullOrWhiteSpace($env:CLAUDE_PROJECT_DIR) ? (Get-Location).Path : $env:CLAUDE_PROJECT_DIR
    $DataDir = Join-Path $projectRoot '.claude' 'google-chat'
}
$defaultFile = Join-Path $DataDir 'webhook.url'
$metaFile    = Join-Path $DataDir 'webhooks.meta.tsv'

# ---- 설정 모드: -Url 지정 시 default webhook 저장 ----
if (-not [string]::IsNullOrWhiteSpace($Url)) {
    $existing = (Test-Path $defaultFile) ? (Get-Content -Raw -Path $defaultFile) : ''
    if (-not [string]::IsNullOrWhiteSpace($existing) -and -not $Force) {
        Write-Error 'default webhook 이 이미 설정돼 있습니다. 교체하려면 -Force 를 지정하세요.'
        exit 1
    }
    if ($Url -notmatch '^https://chat\.googleapis\.com/') {
        Write-Warning 'URL 이 Google Chat webhook 형식(https://chat.googleapis.com/...)이 아닙니다. 그대로 저장합니다.'
    }
    New-Item -ItemType Directory -Force $DataDir | Out-Null
    Set-Content -Path $defaultFile -Value $Url.Trim() -NoNewline -Encoding UTF8
    Write-Output 'default webhook 설정 완료. (URL 은 출력하지 않습니다)'
}

# ---- 상태 리포트 (URL 은 절대 출력하지 않는다) ----
$hasDefault = (Test-Path $defaultFile) -and
              -not [string]::IsNullOrWhiteSpace((Get-Content -Raw -Path $defaultFile -ErrorAction SilentlyContinue))

$purposes = @{}
if (Test-Path $metaFile) {
    foreach ($line in Get-Content -Path $metaFile) {
        $cols = $line -split "`t"
        if ($cols.Count -ge 2) { $purposes[$cols[0]] = $cols[1] }
    }
}

$named = @()
if (Test-Path $DataDir) {
    $named = Get-ChildItem -Path $DataDir -File -Filter 'webhook*.url' |
        ForEach-Object { if ($_.Name -match '^webhook\.(.+)\.url$') { $Matches[1] } } |
        Where-Object { $_ } | Sort-Object
}

Write-Output "데이터 폴더    : $DataDir $((Test-Path $DataDir) ? '' : '(없음)')"
Write-Output "default webhook: $($hasDefault ? '설정됨' : '없음 — init.ps1 -Url <webhook주소> 로 설정하세요')"
if ($named.Count -gt 0) {
    Write-Output "named webhook  : $($named.Count)개"
    foreach ($n in $named) {
        $p = $purposes.ContainsKey($n) ? $purposes[$n] : '(용도 미기재)'
        Write-Output "  - $n : $p"
    }
} else {
    Write-Output 'named webhook  : 없음 (add.ps1 로 추가 가능)'
}

if (-not $hasDefault) { exit 1 }
