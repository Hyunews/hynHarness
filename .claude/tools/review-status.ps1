# review-status.ps1 - summarize review.md and decide the next step.
#   review-status.ps1 -Id 001
# Output RESULT: DONE | HUMAN | ESCALATE | CONTINUE  (rules: .harness/WORKFLOW.md section 3)
# Exit code: 0 DONE, 10 CONTINUE, 20 HUMAN, 30 ESCALATE, 1 error
param([Parameter(Mandatory = $true)][string]$Id)
. (Join-Path $PSScriptRoot '_lib.ps1')
$ErrorActionPreference = 'Stop'

$root = Find-HarnessRoot $PSScriptRoot
Set-Location $root
$reviewPath = Join-Path $root ".harness\tasks\$Id\review.md"
if (-not (Test-Path -LiteralPath $reviewPath)) { Write-Output "review.md not found: $reviewPath"; exit 1 }

$UNKNOWN = '확인불가'
$criteria = @()
$issues = @()
$cur = $null
$inFence = $false
$section = ''
foreach ($line in (Read-Utf8 $reviewPath) -split "`r?`n") {
    if ($line -match '^\s*```') { $inFence = -not $inFence; continue }
    if ($inFence) { continue }
    if ($line -match '^## ') { $section = $line; $cur = $null }
    if ($section -match '③' -and $line -match '^\|\s*([CK]\d+)\s*\|\s*([^|]*?)\s*\|') {
        $criteria += New-Object psobject -Property @{ Id = $Matches[1]; Verdict = $Matches[2] }
        continue
    }
    if ($line -match '^### (I-\d+) \[(BLOCKER|MAJOR|MINOR)\] (OPEN|FIXED|VERIFIED|REOPEN)\s*$') {
        $cur = New-Object psobject -Property @{ Id = $Matches[1]; Sev = $Matches[2]; Status = $Matches[3]; Reopens = 0; ReopenRounds = @() }
        $issues += $cur
        continue
    }
    if ($cur -and $line -match '^- 확인(?:\(r(\d+)\))?.*REOPEN') {
        $n = 0; if ($Matches[1]) { $n = [int]$Matches[1] }
        $cur.ReopenRounds += $n
    }
}

# Rounds are counted only since the LATEST plan(<id>) commit, so a plan revision after ESCALATE resets the counters.
$plans = @(Find-TaskCommits 'plan' $Id)
if ($plans.Count -eq 0) { Write-Output "no plan($Id) commit"; exit 1 }
$latestPlan = $plans[0].Hash
$since = "$latestPlan..HEAD"
$fixAll = @(Find-TaskCommits 'fix' $Id).Count
$fixRounds = @(Find-TaskCommits 'fix' $Id $since).Count
$baseRound = $fixAll - $fixRounds          # rounds before the latest plan revision
foreach ($i in $issues) { $i.Reopens = @($i.ReopenRounds | Where-Object { $_ -eq 0 -or $_ -gt $baseRound }).Count }
$implCount = @(Find-TaskCommits 'impl' $Id).Count
$reviewsSince = @(Find-TaskCommits 'review' $Id $since).Count

Write-Output "task: $Id   fix rounds since latest plan: $fixRounds (total $fixAll)"
Write-Output 'criteria:'
if ($criteria.Count -eq 0) { Write-Output '  (none filled)' }
foreach ($c in $criteria) { $v = $c.Verdict; if (-not $v) { $v = '(empty)' }; Write-Output ("  {0,-4} {1}" -f $c.Id, $v) }
Write-Output 'issues:'
if ($issues.Count -eq 0) { Write-Output '  (none)' }
foreach ($i in $issues) { Write-Output ("  {0} [{1}] {2}  reopen x{3}" -f $i.Id, $i.Sev, $i.Status, $i.Reopens) }

$unknown = @($criteria | Where-Object { $_.Verdict -eq $UNKNOWN })
$allPass = ($criteria.Count -gt 0) -and (@($criteria | Where-Object { $_.Verdict -ne 'PASS' }).Count -eq 0)
$majorOpen = @($issues | Where-Object { $_.Sev -ne 'MINOR' -and $_.Status -ne 'VERIFIED' })
$tooMany = @($issues | Where-Object { $_.Reopens -gt 2 })
$needFix = @($issues | Where-Object { $_.Status -eq 'OPEN' -or $_.Status -eq 'REOPEN' })
$needVerify = @($issues | Where-Object { $_.Status -eq 'FIXED' })

if ($implCount -eq 0) {
    Write-Output 'RESULT: CONTINUE  - next: run-codex.ps1 -Mode impl (no implementation yet)'; exit 10
}
if ($reviewsSince -eq 0) {
    Write-Output 'RESULT: CONTINUE  - next: /review (no review since the latest plan commit; re-judge criteria against the current plan)'; exit 10
}
if ($unknown.Count -gt 0) {
    Write-Output ("RESULT: HUMAN  - {0} criterion/criteria '{1}': {2}" -f $unknown.Count, $UNKNOWN, (($unknown | ForEach-Object { $_.Id }) -join ', ')); exit 20
}
if ($allPass -and $majorOpen.Count -eq 0) {
    Write-Output 'RESULT: DONE  - all criteria PASS, BLOCKER/MAJOR all VERIFIED -> /finalize'; exit 0
}
if ($tooMany.Count -gt 0 -or $fixRounds -ge 3) {
    Write-Output ("RESULT: ESCALATE  - reopen>2: [{0}], fix rounds: {1} -> plan.md likely ambiguous, back to Opus (revise plan.md + plan commit resets the counters)" -f (($tooMany | ForEach-Object { $_.Id }) -join ', '), $fixRounds); exit 30
}
$filled = @($criteria | Where-Object { $_.Verdict })
$next = if ($filled.Count -eq 0) { '/review' } elseif ($needVerify.Count -gt 0) { '/verify' } elseif ($needFix.Count -gt 0) { 'run-codex.ps1 -Mode fix' } else { 'reviewer: criteria not all PASS but no open issue - register issues for FAIL items' }
Write-Output "RESULT: CONTINUE  - next: $next"
exit 10
