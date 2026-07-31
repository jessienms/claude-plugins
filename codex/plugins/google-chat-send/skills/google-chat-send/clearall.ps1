#requires -Version 7
<#
.SYNOPSIS
  google-chat-send 의 모든 webhook 설정을 지우고 초기 상태로 되돌린다.

.DESCRIPTION
  default webhook(webhook.url), 모든 named webhook(webhook.<이름>.url),
  용도 메타(webhooks.meta.tsv)를 삭제한다. 전송 이력(sent.log)은 webhook 설정이
  아니므로 기본 보존하며, -IncludeLog 지정 시에만 함께 삭제한다.
  -Yes 없이 실행하면 삭제하지 않고 대상만 출력한다(dry-run).

.PARAMETER Yes
  실제로 삭제한다. 생략하면 삭제 대상만 보여주는 dry-run.

.PARAMETER IncludeLog
  sent.log(전송 이력)도 함께 삭제한다.

.PARAMETER DataDir
  비밀·로그가 위치한 데이터 폴더. 기본값은 `$env:CLAUDE_PROJECT_DIR`
  (없으면 현재 작업 폴더) 아래 `.claude/google-chat`.

.EXAMPLE
  pwsh clearall.ps1
  # dry-run: 삭제될 파일 목록만 출력.

.EXAMPLE
  pwsh clearall.ps1 -Yes
  # webhook 설정 전체 삭제 (sent.log 는 보존).
#>
[CmdletBinding()]
param(
    [switch]$Yes,
    [switch]$IncludeLog,
    [string]$DataDir = ""
)

$ErrorActionPreference = 'Stop'

# 데이터 폴더(비밀·로그) 위치 결정: 프로젝트의 .claude/google-chat 가 기본.
# (스킬 폴더는 플러그인 설치 캐시라 업데이트 시 갈리므로 비밀·상태를 두지 않는다)
if ([string]::IsNullOrWhiteSpace($DataDir)) {
    $projectRoot = [string]::IsNullOrWhiteSpace($env:CLAUDE_PROJECT_DIR) ? (Get-Location).Path : $env:CLAUDE_PROJECT_DIR
    $DataDir = Join-Path $projectRoot '.claude' 'google-chat'
}

if (-not (Test-Path $DataDir)) {
    Write-Output "데이터 폴더가 없습니다: $DataDir — 이미 초기 상태입니다."
    exit 0
}

$targets = @()
$targets += Get-ChildItem -Path $DataDir -File -Filter 'webhook*.url' |
    Where-Object { $_.Name -eq 'webhook.url' -or $_.Name -match '^webhook\..+\.url$' }
$metaFile = Join-Path $DataDir 'webhooks.meta.tsv'
if (Test-Path $metaFile) { $targets += Get-Item $metaFile }
if ($IncludeLog) {
    $logFile = Join-Path $DataDir 'sent.log'
    if (Test-Path $logFile) { $targets += Get-Item $logFile }
}

if ($targets.Count -eq 0) {
    Write-Output '삭제할 webhook 설정이 없습니다 — 이미 초기 상태입니다.'
    exit 0
}

Write-Output "삭제 대상 ($($targets.Count)개):"
foreach ($t in $targets) { Write-Output "  - $($t.Name)" }

if (-not $Yes) {
    Write-Output ''
    Write-Output 'dry-run 입니다. 실제로 삭제하려면 -Yes 를 지정하세요.'
    exit 0
}

foreach ($t in $targets) { Remove-Item -Path $t.FullName -Force -Confirm:$false }
Write-Output ''
Write-Output "초기화 완료: webhook 설정 $($targets.Count)개 파일을 삭제했습니다. 다시 사용하려면 init.ps1 -Url 로 default 를 설정하세요."
