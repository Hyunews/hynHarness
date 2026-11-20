# new-task.ps1 - create .harness/tasks/<id>/ (plan.md, review.md) and the private checks.md.
#   new-task.ps1 -Id 001-login            create
#   new-task.ps1 -Id 001-login -PathsOnly print paths only (no changes)
param(
    [Parameter(Mandatory = $true)][ValidatePattern('^[A-Za-z0-9][A-Za-z0-9._-]*$')][string]$Id,
    [switch]$PathsOnly
)
. (Join-Path $PSScriptRoot '_lib.ps1')
$ErrorActionPreference = 'Stop'

$root = Find-HarnessRoot $PSScriptRoot
$cfg = Get-HarnessConfig $root
$taskDir = Join-Path $root ".harness\tasks\$Id"
$privDir = Get-PrivateDir $root $cfg $Id
$plan = Join-Path $taskDir 'plan.md'
$review = Join-Path $taskDir 'review.md'
$checks = Join-Path $privDir 'checks.md'

function Show-Paths {
    Write-Output "task   : $Id"
    Write-Output "plan   : $plan"
    Write-Output "review : $review"
    Write-Output "checks : $checks   (private, outside repo)"
}

if ($PathsOnly) { Show-Paths; exit 0 }

if (Test-Path -LiteralPath $taskDir) { [Console]::Error.WriteLine("task already exists: $taskDir (use -PathsOnly)"); exit 1 }
if (Test-Path -LiteralPath $checks) { [Console]::Error.WriteLine("private checks already exists: $checks"); exit 1 }

$tpl = Join-Path $root '.harness\templates'
foreach ($pair in @(@('plan.md', $plan), @('review.md', $review), @('checks.md', $checks))) {
    $text = (Read-Utf8 (Join-Path $tpl $pair[0])).Replace('{{id}}', $Id)
    Write-Utf8 $pair[1] $text
}
Write-Output "created:"
Show-Paths
