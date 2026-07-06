#requires -Version 7
<#
.SYNOPSIS
  google-chat-send 에 named webhook 을 등록한다.

.DESCRIPTION
  이름·용도를 지정해 추가 webhook 을 등록한다. URL 은 프로젝트 데이터 폴더의
  `webhook.<이름>.url` 에 저장되고(비밀), 용도는 `webhooks.meta.tsv` 에 기록된다.
  default webhook(webhook.url)은 init.ps1 로 관리한다 — 이름 'default' 는 예약어.
  webhook URL 은 어디에도 출력하지 않는다.

.PARAMETER Name
  webhook 이름. 영문 소문자/숫자/하이픈/언더스코어만 허용 (예: qa-team, design).

.PARAMETER Purpose
  이 webhook 의 용도 설명 (예: "QA 팀 채널 — 버그 리포트 공유용").

.PARAMETER Url
  Google Chat incoming webhook URL.

.PARAMETER Force
  같은 이름이 이미 등록돼 있어도 덮어쓴다.

.PARAMETER DataDir
  비밀·로그가 위치한 데이터 폴더. 기본값은 `$env:CLAUDE_PROJECT_DIR`
  (없으면 현재 작업 폴더) 아래 `.claude/google-chat`.

.EXAMPLE
  pwsh add.ps1 -Name qa-team -Purpose "QA 팀 채널 — 버그 리포트 공유용" -Url "https://chat.googleapis.com/v1/spaces/..."
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)][string]$Purpose,
    [Parameter(Mandatory)][string]$Url,
    [switch]$Force,
    [string]$DataDir = ""
)

$ErrorActionPreference = 'Stop'

if ($Name -notmatch '^[a-z0-9][a-z0-9_-]*$') {
    Write-Error "webhook 이름은 영문 소문자/숫자/하이픈/언더스코어만 허용합니다: '$Name'"
    exit 1
}
if ($Name -eq 'default') {
    Write-Error "'default' 는 예약된 이름입니다. default webhook 은 init.ps1 로 설정하세요."
    exit 1
}
if ([string]::IsNullOrWhiteSpace($Url)) {
    Write-Error 'URL 이 비어 있습니다.'
    exit 1
}
if ($Url -notmatch '^https://chat\.googleapis\.com/') {
    Write-Warning 'URL 이 Google Chat webhook 형식(https://chat.googleapis.com/...)이 아닙니다. 그대로 저장합니다.'
}

# 데이터 폴더(비밀·로그) 위치 결정: 프로젝트의 .claude/google-chat 가 기본.
# (스킬 폴더는 플러그인 설치 캐시라 업데이트 시 갈리므로 비밀·상태를 두지 않는다)
if ([string]::IsNullOrWhiteSpace($DataDir)) {
    $projectRoot = [string]::IsNullOrWhiteSpace($env:CLAUDE_PROJECT_DIR) ? (Get-Location).Path : $env:CLAUDE_PROJECT_DIR
    $DataDir = Join-Path $projectRoot '.claude' 'google-chat'
}
$urlFile  = Join-Path $DataDir "webhook.$Name.url"
$metaFile = Join-Path $DataDir 'webhooks.meta.tsv'

if ((Test-Path $urlFile) -and -not $Force) {
    Write-Error "webhook '$Name' 이 이미 등록돼 있습니다. 교체하려면 -Force 를 지정하세요."
    exit 1
}

$defaultFile = Join-Path $DataDir 'webhook.url'
if (-not (Test-Path $defaultFile)) {
    Write-Warning 'default webhook 이 아직 없습니다. 정책상 default 는 항상 존재해야 하니 init.ps1 -Url 로 먼저 설정하세요.'
}

New-Item -ItemType Directory -Force $DataDir | Out-Null
Set-Content -Path $urlFile -Value $Url.Trim() -NoNewline -Encoding UTF8

# 용도 메타 갱신: 같은 이름의 기존 줄은 제거 후 추가. 탭·개행은 형식 보호를 위해 공백 치환.
$Purpose = ($Purpose -replace "[`t`r`n]", ' ').Trim()
$metaLines = @()
if (Test-Path $metaFile) {
    $metaLines = Get-Content -Path $metaFile | Where-Object { ($_ -split "`t")[0] -ne $Name }
}
$metaLines += "{0}`t{1}" -f $Name, $Purpose
Set-Content -Path $metaFile -Value $metaLines -Encoding UTF8

Write-Output "webhook '$Name' 등록 완료 (용도: $Purpose). 전송 시 send.ps1 -Webhook $Name 으로 사용합니다."
