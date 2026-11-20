# run-codex.ps1 - run Codex non-interactively for a task, then commit and check ownership.
#   run-codex.ps1 -Id 001 -Mode impl   implement from plan.md  -> commit "impl(001): ..."
#   run-codex.ps1 -Id 001 -Mode fix    fix OPEN/REOPEN issues  -> commit "fix(001): rN"
# NOT VERIFIED YET - see .harness/WORKFLOW.md section 7 (Codex checklist).
# The prompt is passed on stdin from a UTF-8 (no BOM) file: PowerShell 5.1 breaks arguments that
# contain double quotes, and its pipeline to native programs prepends a BOM.
param(
    [Parameter(Mandatory = $true)][string]$Id,
    [Parameter(Mandatory = $true)][ValidateSet('impl', 'fix')][string]$Mode,
    [string]$Model,
    [ValidateSet('read-only', 'workspace-write')][string]$Sandbox = 'workspace-write',
    [switch]$NoCommit
)
. (Join-Path $PSScriptRoot '_lib.ps1')
$ErrorActionPreference = 'Stop'

$root = Find-HarnessRoot $PSScriptRoot
$cfg = Get-HarnessConfig $root
Set-Location $root

$planRel = ".harness/tasks/$Id/plan.md"
$reviewRel = ".harness/tasks/$Id/review.md"
if (-not (Test-Path -LiteralPath $planRel)) { throw "plan not found: $planRel" }
if ((Invoke-Git status --porcelain) | Where-Object { $_ -and $_ -notmatch '^\?\? \.harness/runs/' }) {
    throw "working tree is not clean. Commit or stash first so the Codex commit contains only Codex changes."
}

# --- codex executable ---
$codex = [string]$cfg.codexPath
if (-not $codex) {
    $cmd = Get-Command codex -ErrorAction SilentlyContinue
    if ($cmd) { $codex = $cmd.Source }
    else { $codex = Join-Path $env:USERPROFILE '.codex\.sandbox-bin\codex.exe' }
}
if (-not (Test-Path -LiteralPath $codex) -and -not (Get-Command $codex -ErrorAction SilentlyContinue)) { throw "codex not found: $codex (set codexPath in .harness/config.json)" }

# --- round & prompt (never mention the private root here) ---
$fixCount = @(Find-TaskCommits 'fix' $Id).Count
if ($Mode -eq 'impl') {
    $round = 0
    $prompt = @"
AGENTS.md 규칙을 따른다. 과제 id: $Id
$planRel 을 읽고 "할 일"을 구현하라. "참고 문서"에 적힌 .docs 문서는 읽고 따른다(수정하지 않는다).
"완료 기준"의 확인 방법이 통과하도록 하고, "범위 밖"과 "잠금 테스트"는 건드리지 않는다.
git 커밋은 하지 않는다. 끝나면 변경 요약과 plan이 모호했던 점을 보고하라.
"@
} else {
    if (-not (Test-Path -LiteralPath $reviewRel)) { throw "review not found: $reviewRel" }
    $round = $fixCount + 1
    $prompt = @"
AGENTS.md 규칙을 따른다. 과제 id: $Id, 수정 회차 r$round
$reviewRel 에서 상태가 OPEN 또는 REOPEN인 이슈를 $planRel 기준으로 수정하라.
review.md에서는 해당 이슈 제목 줄의 상태를 FIXED로 바꾸고 "- 수정(r$round): <내용>" 줄을 추가하는 것만 허용된다. 다른 줄은 바꾸지 않는다.
git 커밋은 하지 않는다. 끝나면 이슈별 수정 요약을 보고하라.
"@
}

$runDir = Join-Path $root ".harness\runs\$Id"
New-Item -ItemType Directory -Force -Path $runDir | Out-Null
$stem = "r{0}-{1}" -f $round, $Mode
$log = Join-Path $runDir "$stem.jsonl"
$errLog = Join-Path $runDir "$stem.stderr.txt"
$last = Join-Path $runDir "$stem.last.txt"
$promptFile = Join-Path $runDir "$stem.prompt.txt"
Write-Utf8 $promptFile $prompt

# no PROMPT argument -> codex exec reads the instructions from stdin
$codexArgs = @('exec', '-s', $Sandbox, '-C', $root, '--json', '-o', $last)
if ($Model) { $codexArgs += @('-m', $Model) } elseif ($cfg.codexModel) { $codexArgs += @('-m', [string]$cfg.codexModel) }
# TODO(verify): codex exec has no -a flag. Approval policy via config override - key name not verified yet.
# $codexArgs += @('-c', 'approval_policy="never"')
$argLine = ($codexArgs | ForEach-Object { ConvertTo-WinArg ([string]$_) }) -join ' '

Write-Output "[run-codex] $Mode r$round -> $log"
$p = Start-Process -FilePath $codex -ArgumentList $argLine -WorkingDirectory $root -NoNewWindow -Wait -PassThru `
    -RedirectStandardInput $promptFile -RedirectStandardOutput $log -RedirectStandardError $errLog
$code = $p.ExitCode
Write-Output "[run-codex] codex exit code: $code"
if (Test-Path $last) { Write-Output '--- codex last message ---'; Get-Content $last -Encoding UTF8 }
if ($code -ne 0) { throw "codex failed (exit $code). Nothing committed. stderr: $errLog" }

if ($NoCommit) { Write-Output '[run-codex] -NoCommit: skipping commit and ownership check.'; exit 0 }

Invoke-Git add -A | Out-Null
if (-not (Invoke-Git diff --cached --name-only)) { Write-Output '[run-codex] no changes from codex.'; exit 0 }
$msg = if ($Mode -eq 'impl') { "impl(${Id}): codex implementation" } else { "fix(${Id}): r$round" }
Invoke-Git commit -m $msg | Out-Null
Write-Output "[run-codex] committed: $msg"

& powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $PSScriptRoot 'check-ownership.ps1') -Id $Id
if ($LASTEXITCODE -ne 0) { Write-Output '[run-codex] OWNERSHIP VIOLATION - review and git revert HEAD if needed.'; exit 1 }
