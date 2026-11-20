# check-ownership.ps1 - verify Codex commits (impl/fix) stayed inside their permissions.
#   check-ownership.ps1 -Id 001          latest impl/fix commit of task 001 (+ run log scan)
#   check-ownership.ps1 -Id 001 -All     every impl/fix commit of task 001
#   check-ownership.ps1 -Commit <rev>    one specific commit
# Checks: (1) protected paths / locked tests not touched
#         (2) review.md: only "### I-NN [SEV] OPEN|REOPEN -> FIXED" and added "- 수정..." lines
#         (3) Codex run logs (.harness/runs/<id>) mention the private root -> WARN
# Exit 1 on violation.
param(
    [string]$Id,
    [string]$Commit,
    [switch]$All
)
. (Join-Path $PSScriptRoot '_lib.ps1')
$ErrorActionPreference = 'Stop'

$root = Find-HarnessRoot $PSScriptRoot
$cfg = Get-HarnessConfig $root
Set-Location $root

$targets = @()
if ($Commit) {
    $h = (Invoke-Git rev-parse --verify "$Commit^{commit}")[0]
    $s = (Invoke-Git log -1 '--format=%s' $h)[0]
    $targets += New-Object psobject -Property @{ Hash = $h; Subject = $s }
} elseif ($Id) {
    $list = @(Find-TaskCommits '(impl|fix)' $Id)
    if ($list.Count -eq 0) { Write-Output "no impl/fix commits for $Id"; exit 0 }
    if ($All) { $targets = $list } else { $targets = @($list[0]) }
} else { throw 'give -Id or -Commit' }

$violations = New-Object System.Collections.ArrayList
$fixLine = '^- ' + [char]0xC218 + [char]0xC815   # "- 수정"

foreach ($t in $targets) {
    $short = $t.Hash.Substring(0, 8)
    if ($t.Subject -notmatch '^(impl|fix)\(') { Write-Output "[$short] not a Codex commit ($($t.Subject)) - skipped"; continue }
    Write-Output "[$short] $($t.Subject)"
    $files = @(Invoke-Git show '--format=' --name-only $t.Hash | Where-Object { $_ })
    foreach ($f in $files) {
        $g = Find-GlobMatch $f $cfg.protected
        if ($g) { [void]$violations.Add("[$short] protected path ($g): $f"); continue }
        $g = Find-GlobMatch $f $cfg.lockedTests
        if ($g) { [void]$violations.Add("[$short] locked test ($g): $f"); continue }
        if (Find-GlobMatch $f @('.harness/tasks/*/review.md')) {
            $diff = Invoke-Git show '--format=' -U0 $t.Hash -- $f
            $removed = New-Object System.Collections.ArrayList
            $added = New-Object System.Collections.ArrayList
            foreach ($d in $diff) {
                if ($d -match '^(\+\+\+|---) ' -or $d -match '^@@' -or $d -match '^(diff|index|new file|deleted file) ') { continue }
                if ($d.StartsWith('-')) { [void]$removed.Add($d.Substring(1)) }
                elseif ($d.StartsWith('+')) { [void]$added.Add($d.Substring(1)) }
            }
            foreach ($r in $removed) {
                if ($r -match '^### (I-\d+) \[(BLOCKER|MAJOR|MINOR)\] (OPEN|REOPEN)\s*$') {
                    $want = '^### ' + [regex]::Escape($Matches[1]) + ' \[' + $Matches[2] + '\] FIXED\s*$'
                    $hit = $null
                    foreach ($a in $added) { if ($a -match $want) { $hit = $a; break } }
                    if ($hit) { $added.Remove($hit); continue }
                }
                [void]$violations.Add("[$short] review.md line changed/removed: $r")
            }
            foreach ($a in $added) {
                if ($a -match $fixLine -or $a.Trim() -eq '') { continue }
                [void]$violations.Add("[$short] review.md line added (not allowed): $a")
            }
        }
    }
}

# run log scan (best effort)
$warn = 0
if ($Id) {
    $runDir = Join-Path $root ".harness\runs\$Id"
    if (Test-Path $runDir) {
        $needles = @($cfg.codexForbiddenTokens) + @((Get-PrivateBase $cfg))
        foreach ($log in Get-ChildItem $runDir -Filter *.jsonl) {
            $text = Read-Utf8 $log.FullName
            foreach ($n in $needles) {
                if ($n -and $text.IndexOf($n, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                    Write-Output "WARN: run log $($log.Name) mentions '$n' - check whether Codex tried to read private checks"
                    $warn++
                }
            }
        }
    }
}

if ($violations.Count -gt 0) {
    Write-Output "OWNERSHIP: FAIL ($($violations.Count))"
    $violations | ForEach-Object { Write-Output "  $_" }
    exit 1
}
Write-Output ("OWNERSHIP: OK ({0} commit(s), {1} log warning(s))" -f $targets.Count, $warn)
exit 0
