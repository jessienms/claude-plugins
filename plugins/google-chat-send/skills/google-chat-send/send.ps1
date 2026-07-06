#requires -Version 7
<#
.SYNOPSIS
  팀 Google Chat Space 전송 어댑터 (범용).
  메시지 본문을 받아 webhook.url 의 Google Chat Space 로 POST 한다.
  여러 에이전트/프롬프트가 공유하는 단일 전송 지점이며, 호출자가 누구인지에 독립적이다.

.DESCRIPTION
  이 스크립트(코드)는 google-chat-send 스킬 폴더(플러그인 설치 경로)에 있고,
  비밀(webhook.url)과 전송 로그(sent.log)는 프로젝트의 데이터 폴더
  `.claude/google-chat/` 에 둔다. webhook URL 은 화면/로그/응답 어디에도 출력하지 않는다.

.PARAMETER MessageFile
  전송할 메시지 본문이 담긴 텍스트 파일 경로. (-Message 와 택1)

.PARAMETER Message
  전송할 메시지 본문 문자열. (-MessageFile 와 택1)

.PARAMETER Tag
  sent.log 에 남길 식별 태그(커밋 rev, 작업명 등). 중복 전송 추적용.
  같은 Tag 가 이미 sent.log 에 있으면 전송을 중단한다(-Force 로 무시 가능).
  탭·개행 문자는 로그 형식 보호를 위해 공백으로 치환된다.

.PARAMETER Force
  같은 Tag 가 sent.log 에 이미 있어도 강제로 재전송한다.

.PARAMETER Webhook
  전송에 사용할 named webhook 이름 (add.ps1 로 등록한 것). 생략하면 default webhook
  (webhook.url)을 사용한다 — 호출자가 특별히 지정하지 않는 한 항상 default 가 정책.

.PARAMETER WebhookFile
  사용할 webhook url 파일 경로를 직접 지정 (테스트용). 지정 시 -Webhook 보다 우선한다.

.PARAMETER DataDir
  비밀·로그가 위치한 데이터 폴더. 기본값은 `$env:CLAUDE_PROJECT_DIR`
  (없으면 현재 작업 폴더) 아래 `.claude/google-chat`.

.EXAMPLE
  pwsh send.ps1 -MessageFile draft.txt -Tag "r65019"

.EXAMPLE
  pwsh send.ps1 -Message "공유폴더에 빌드 X 를 올렸습니다." -Tag "build-x"
#>
[CmdletBinding(DefaultParameterSetName = 'File')]
param(
    [Parameter(Mandatory, ParameterSetName = 'File')][string]$MessageFile,
    [Parameter(Mandatory, ParameterSetName = 'Text')][string]$Message,
    [string]$Tag = "",
    [switch]$Force,
    [string]$Webhook = "",
    [string]$WebhookFile = "",
    [string]$DataDir = ""
)

# Google Chat incoming webhook 의 text 메시지 최대 길이.
$MaxMessageLength = 4096

$ErrorActionPreference = 'Stop'

# 데이터 폴더(비밀·로그) 위치 결정: 프로젝트의 .claude/google-chat 가 기본.
# (스킬 폴더는 플러그인 설치 캐시라 업데이트 시 갈리므로 비밀·상태를 두지 않는다)
if ([string]::IsNullOrWhiteSpace($DataDir)) {
    $projectRoot = [string]::IsNullOrWhiteSpace($env:CLAUDE_PROJECT_DIR) ? (Get-Location).Path : $env:CLAUDE_PROJECT_DIR
    $DataDir = Join-Path $projectRoot '.claude' 'google-chat'
}
# 사용할 webhook 결정: -WebhookFile(직접 경로) > -Webhook(이름) > default.
if (-not [string]::IsNullOrWhiteSpace($WebhookFile)) {
    $webhookName = [System.IO.Path]::GetFileNameWithoutExtension($WebhookFile)
} else {
    if ([string]::IsNullOrWhiteSpace($Webhook)) { $Webhook = 'default' }
    if ($Webhook -ne 'default' -and $Webhook -notmatch '^[a-z0-9][a-z0-9_-]*$') {
        Write-Error "webhook 이름이 올바르지 않습니다: '$Webhook' (영문 소문자/숫자/하이픈/언더스코어)"
        exit 1
    }
    $webhookName = $Webhook
    $WebhookFile = ($Webhook -eq 'default') ?
        (Join-Path $DataDir 'webhook.url') :
        (Join-Path $DataDir "webhook.$Webhook.url")
}

if (-not (Test-Path $WebhookFile)) {
    $available = @()
    if (Test-Path (Join-Path $DataDir 'webhook.url')) { $available += 'default' }
    if (Test-Path $DataDir) {
        $available += Get-ChildItem -Path $DataDir -File -Filter 'webhook*.url' |
            ForEach-Object { if ($_.Name -match '^webhook\.(.+)\.url$') { $Matches[1] } } |
            Where-Object { $_ }
    }
    $hint = ($available.Count -gt 0) ? "등록된 webhook: $($available -join ', ')." : 'init.ps1 로 default 를 먼저 설정하세요.'
    Write-Error "webhook '$webhookName' 파일이 없습니다: $WebhookFile — $hint (추가 등록은 add.ps1)"
    exit 1
}
$url = (Get-Content -Raw -Path $WebhookFile).Trim()
if ([string]::IsNullOrWhiteSpace($url)) {
    Write-Error 'webhook URL 이 비어 있습니다.'
    exit 1
}

if ($PSCmdlet.ParameterSetName -eq 'File') {
    if (-not (Test-Path $MessageFile)) {
        Write-Error "메시지 파일이 없습니다: $MessageFile"
        exit 1
    }
    $text = Get-Content -Raw -Path $MessageFile
} else {
    $text = $Message
}
if ([string]::IsNullOrWhiteSpace($text)) {
    Write-Error '전송할 메시지 본문이 비어 있습니다.'
    exit 1
}
if ($text.Length -gt $MaxMessageLength) {
    Write-Error ("메시지가 너무 깁니다: {0}자 (최대 {1}자). 본문을 줄이거나 나눠서 전송하세요." -f $text.Length, $MaxMessageLength)
    exit 1
}

# Tag 의 탭·개행은 sent.log 의 탭 구분 형식을 깨뜨리므로 공백으로 치환.
$Tag = ($Tag -replace "[`t`r`n]", ' ').Trim()

# 같은 (Tag, webhook) 조합으로 이미 보낸 기록이 있으면 중복 전송 방지 (-Force 로 무시).
# 로그 형식: 시각 \t Tag \t sent \t webhook이름 — 4번째 열이 없는 과거 기록은 default 로 간주.
$logPath = Join-Path $DataDir 'sent.log'
if (-not [string]::IsNullOrWhiteSpace($Tag) -and -not $Force -and (Test-Path $logPath)) {
    $dup = Get-Content -Path $logPath | Where-Object {
        $cols = $_ -split "`t"
        $cols.Count -ge 2 -and $cols[1] -eq $Tag -and
        ((($cols.Count -ge 4) ? $cols[3] : 'default') -eq $webhookName)
    } | Select-Object -First 1
    if ($dup) {
        Write-Error "이미 전송된 Tag 입니다: '$Tag' (webhook '$webhookName', sent.log 에 기록 있음). 재전송하려면 -Force 를 지정하세요."
        exit 1
    }
}

$payload = @{ text = $text } | ConvertTo-Json -Depth 5
$bytes   = [System.Text.Encoding]::UTF8.GetBytes($payload)

# Google Chat incoming webhook: { "text": "..." } 형식, 200 응답이면 성공.
# 예외를 그대로 흘리면 ErrorRecord 에 webhook URL 이 포함될 수 있어 정제해 다시 던진다.
try {
    Invoke-RestMethod -Uri $url -Method Post `
        -ContentType 'application/json; charset=UTF-8' -Body $bytes | Out-Null
} catch {
    $status = $_.Exception.Response ? [int]$_.Exception.Response.StatusCode : $null
    if ($status) {
        Write-Error "전송 실패: HTTP $status 응답을 받았습니다."
    } else {
        Write-Error ("전송 실패: {0}" -f $_.Exception.GetType().Name)
    }
    exit 1
}

$logLine = "{0}`t{1}`tsent`t{2}" -f (Get-Date -Format o), $Tag, $webhookName
Add-Content -Path $logPath -Value $logLine -Encoding UTF8

Write-Output "전송 완료 (Tag: $Tag, Webhook: $webhookName)"
