# check-harness.ps1 - self check of the harness skeleton. Exit 1 on any FAIL.
. (Join-Path $PSScriptRoot '_lib.ps1')
$ErrorActionPreference = 'Stop'

$root = Find-HarnessRoot $PSScriptRoot
$fails = 0
function Report([bool]$ok, [string]$msg) {
    if ($ok) { Write-Output "  OK    $msg" } else { Write-Output "  FAIL  $msg"; $script:fails++ }
}

Write-Output "harness root: $root"

Write-Output '[files]'
$required = @(
    'AGENTS.md', 'CLAUDE.md', 'README.md', '.gitignore',
    '.harness/WORKFLOW.md', '.harness/config.json',
    '.harness/templates/plan.md', '.harness/templates/checks.md', '.harness/templates/review.md',
    '.claude/settings.json', '.claude/agents/reviewer.md',
    '.claude/rules/10-workflow.md', '.claude/rules/20-review.md', '.claude/rules/30-ownership.md',
    '.claude/skills/plan/SKILL.md', '.claude/skills/review/SKILL.md', '.claude/skills/verify/SKILL.md', '.claude/skills/finalize/SKILL.md',
    '.claude/hooks/guard.ps1', '.claude/hooks/guard-tests.txt',
    '.claude/tools/_lib.ps1', '.claude/tools/new-task.ps1', '.claude/tools/run-codex.ps1',
    '.claude/tools/check-ownership.ps1', '.claude/tools/review-status.ps1', '.claude/tools/check-harness.ps1',
    '.codex/hooks.json', '.codex/rules/harness.rules',
    '.claude/rules/40-docs.md', '.harness/context.md', '.docs/00_INDEX.md'
)
foreach ($f in $required) { Report (Test-Path -LiteralPath (Join-Path $root $f)) $f }

Write-Output '[encoding] .ps1 must be UTF-8 with BOM (PowerShell 5.1)'
foreach ($p in Get-ChildItem (Join-Path $root '.claude') -Recurse -Filter *.ps1) {
    $b = [IO.File]::ReadAllBytes($p.FullName)
    Report ($b.Length -ge 3 -and $b[0] -eq 0xEF -and $b[1] -eq 0xBB -and $b[2] -eq 0xBF) ("BOM " + $p.Name)
}

Write-Output '[instructions]'
$claudeMd = Read-Utf8 (Join-Path $root 'CLAUDE.md')
Report ($claudeMd -match '(?m)^@AGENTS\.md\s*$') 'CLAUDE.md imports @AGENTS.md'
Report ($claudeMd -match '(?m)^@\.harness/context\.md\s*$') 'CLAUDE.md imports @.harness/context.md'
Report ($claudeMd -match 'Codex') 'CLAUDE.md explains what Codex is'
$agentsMd = Read-Utf8 (Join-Path $root 'AGENTS.md')
# files Codex reads must not reveal the private checks
$codexVisible = @('AGENTS.md', 'README.md', '.harness/context.md', '.harness/templates/plan.md', '.harness/templates/review.md')
$codexVisible += @(Get-ChildItem (Join-Path $root '.docs') -Recurse -Filter *.md -ErrorAction SilentlyContinue | ForEach-Object { Get-RelPath $root $_.FullName })
$codexVisible += @(Get-ChildItem (Join-Path $root '.harness/tasks') -Recurse -Filter *.md -ErrorAction SilentlyContinue | ForEach-Object { Get-RelPath $root $_.FullName })
foreach ($f in $codexVisible) {
    $t = Read-Utf8 (Join-Path $root $f)
    Report ($t.IndexOf('harness-private', [StringComparison]::OrdinalIgnoreCase) -lt 0 -and $t.IndexOf('checks.md', [StringComparison]::OrdinalIgnoreCase) -lt 0) "$f does not reveal private checks"
}
$ctxBytes = [IO.File]::ReadAllBytes((Join-Path $root '.harness/context.md')).Length
Report ($ctxBytes -le 3072) ".harness/context.md <= 3 KB ($ctxBytes bytes)"
Report ($agentsMd -match '\.docs/') 'AGENTS.md points to .docs/'
Report ([Text.Encoding]::UTF8.GetByteCount($agentsMd) -lt 32768) 'AGENTS.md < 32 KiB (Codex project_doc_max_bytes default)'
$runCodex = Read-Utf8 (Join-Path $root '.claude/tools/run-codex.ps1')
$promptPart = ($runCodex -split '# --- codex executable ---')[1]
Report ($promptPart.IndexOf('harness-private', [StringComparison]::OrdinalIgnoreCase) -lt 0 -and $promptPart.IndexOf('checks.md', [StringComparison]::OrdinalIgnoreCase) -lt 0) 'run-codex prompts do not reveal private checks'

Write-Output '[config]'
$cfg = $null
try { $cfg = Get-HarnessConfig $root; Report $true 'config.json parses' } catch { Report $false "config.json parses: $_" }
if ($cfg) {
    foreach ($k in 'project', 'privateRoot', 'protected', 'codexWritable', 'claudeHumanOnly', 'lockedTests', 'reviewerWritable', 'codexForbiddenTokens', 'noSecretPaths', 'reviewerBashDeny') {
        Report ($null -ne $cfg.PSObject.Properties[$k]) "config key: $k"
    }
    if (-not $cfg.codexModel) { Write-Output '  WARN  codexModel empty -> global Codex default model will implement' }
    if (Test-Placeholder $cfg.project) { Write-Output "  INFO  project is a placeholder -> folder name '$(Get-ProjectName $root $cfg)' is used" }
    if (-not (@($cfg.lockedTests) | Where-Object { -not (Test-Placeholder $_) })) { Write-Output '  INFO  lockedTests not set (placeholder)' }
    Write-Output "  INFO  private dir: $(Get-PrivateDir $root $cfg $null)"
}

Write-Output '[claude settings]'
try {
    $s = Read-Utf8 (Join-Path $root '.claude/settings.json') | ConvertFrom-Json
    $pre = @($s.hooks.PreToolUse)
    $hooked = $pre | Where-Object { $_.matcher -match 'Edit' -and $_.matcher -match 'Write' -and $_.matcher -match 'Bash' -and (@($_.hooks) | Where-Object { $_.command -match 'guard\.ps1' -and $_.command -match '-Agent claude' }) }
    Report ([bool]$hooked) 'PreToolUse -> guard.ps1 -Agent claude (Edit|Write|Bash)'
    $deny = @($s.permissions.deny)
    Report ($deny -contains 'Edit(./.claude/settings.json)') 'deny Edit(./.claude/settings.json)'
    Report ($deny -contains 'Edit(./.claude/hooks/**)') 'deny Edit(./.claude/hooks/**)'
    Report (@(@($s.permissions.additionalDirectories) -match 'harness-private').Count -gt 0)'additionalDirectories includes private root'
} catch { Report $false "settings.json parses: $_" }

Write-Output '[codex]'
try {
    $c = Read-Utf8 (Join-Path $root '.codex/hooks.json') | ConvertFrom-Json
    $ok = @($c.hooks.PreToolUse) | Where-Object { @($_.hooks) | Where-Object { $_.command -match 'guard\.ps1' -and $_.command -match '-Agent codex' } }
    Report ([bool]$ok) '.codex/hooks.json PreToolUse -> guard.ps1 -Agent codex'
} catch { Report $false ".codex/hooks.json parses: $_" }

Write-Output '[agents / skills]'
$rv = Read-Utf8 (Join-Path $root '.claude/agents/reviewer.md')
Report ($rv -match '(?m)^model:\s*sonnet\s*$') 'reviewer model: sonnet'
Report ($rv -match '(?m)^name:\s*reviewer\s*$') 'reviewer name'
foreach ($sk in 'review', 'verify') {
    $t = Read-Utf8 (Join-Path $root ".claude/skills/$sk/SKILL.md")
    Report ($t -match '(?m)^context:\s*fork' -and $t -match '(?m)^agent:\s*reviewer') "skill $sk runs in reviewer (context: fork)"
}
foreach ($sk in 'plan', 'finalize') {
    $t = Read-Utf8 (Join-Path $root ".claude/skills/$sk/SKILL.md")
    Report ($t -match '(?m)^model:\s*opus\s*$') "skill $sk runs on opus"
}
foreach ($r in Get-ChildItem (Join-Path $root '.claude/rules') -Recurse -Filter *.md) {
    $t = Read-Utf8 $r.FullName
    Report ($t -match '(?s)^---.*?paths:.*?---') ("rule has paths: " + $r.Name)
}

Write-Output '[git]'
Report (Test-Path (Join-Path $root '.git')) 'git repository'
$gi = Read-Utf8 (Join-Path $root '.gitignore')
Report ($gi -match '\.harness/runs/') '.gitignore excludes .harness/runs/'

Write-Output '[guard self-test]'
$out = & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root '.claude/hooks/guard.ps1') -SelfTest
$out | ForEach-Object { Write-Output "    $_" }
Report ($LASTEXITCODE -eq 0) 'guard-tests.txt'

if ($fails -gt 0) { Write-Output "CHECK-HARNESS: FAIL ($fails)"; exit 1 }
Write-Output 'CHECK-HARNESS: OK'
exit 0
