# guard.ps1 - PreToolUse guard shared by Claude Code and Codex.
#   Hook mode : JSON on stdin -> exit 0 (allow) / exit 2 + stderr (deny)
#   Self test : guard.ps1 -SelfTest   (runs guard-tests.txt)
# Rules come from .harness/config.json. Human-only file: do not let agents edit.
param(
    [ValidateSet('claude', 'codex')][string]$Agent = 'claude',
    [switch]$SelfTest
)
. (Join-Path $PSScriptRoot '..\tools\_lib.ps1')

$WriteTools = @('Edit', 'Write', 'MultiEdit', 'NotebookEdit')
$ShellTools = @('Bash', 'PowerShell')

function Get-PatchPaths([string]$Text) {
    $paths = @()
    foreach ($m in [regex]::Matches($Text, '(?m)^\*\*\* (?:Add|Update|Delete) File: (.+?)\s*$')) { $paths += $m.Groups[1].Value }
    foreach ($m in [regex]::Matches($Text, '(?m)^\*\*\* Move to: (.+?)\s*$')) { $paths += $m.Groups[1].Value }
    return $paths
}

# New text an Edit/Write/MultiEdit/NotebookEdit call would put into the file.
function Get-WriteText($ToolInput) {
    $parts = @()
    foreach ($k in 'content', 'new_string', 'new_source') {
        if ($ToolInput.PSObject.Properties[$k] -and $ToolInput.$k) { $parts += [string]$ToolInput.$k }
    }
    if ($ToolInput.PSObject.Properties['edits']) {
        foreach ($e in @($ToolInput.edits)) { if ($e.PSObject.Properties['new_string']) { $parts += [string]$e.new_string } }
    }
    return ($parts -join "`n")
}

# Returns $null (allow) or a deny reason.
function Get-GuardDecision {
    param($Agent, $ToolName, $AgentType, $ToolInput, $Root, $Cfg)

    $privBase = Get-PrivateBase $Cfg
    $isReviewer = ($AgentType -eq 'reviewer')

    if ($Agent -eq 'claude') {
        if ($WriteTools -contains $ToolName) {
            $fp = $null
            foreach ($k in 'file_path', 'notebook_path', 'path') {
                if ($ToolInput.PSObject.Properties[$k] -and $ToolInput.$k) { $fp = [string]$ToolInput.$k; break }
            }
            if (-not $fp) { return $null }
            $full = Get-FullPath $Root $fp
            if (Test-UnderDir $full $privBase) {
                if ($isReviewer) { return "reviewer may read but not write the private root: $fp" }
                return $null
            }
            $rel = Get-RelPath $Root $fp
            if ($null -eq $rel) {
                if ($isReviewer) { return "reviewer may not write outside the project: $fp" }
                return $null
            }
            $g = Find-GlobMatch $rel $Cfg.claudeHumanOnly
            if ($g) { return "human-only file ($g): $rel" }
            # files Codex reads (tasks, context, docs) must not name the private checks
            if (Find-GlobMatch $rel $Cfg.noSecretPaths) {
                $text = Get-WriteText $ToolInput
                foreach ($t in @($Cfg.codexForbiddenTokens) + @($privBase)) {
                    if ($t -and $text.IndexOf($t, [StringComparison]::OrdinalIgnoreCase) -ge 0) {
                        return "Codex-visible file must not mention '$t' (write 'K-number' instead): $rel"
                    }
                }
            }
            if ($isReviewer) {
                if (Find-GlobMatch $rel $Cfg.reviewerWritable) { return $null }
                return "reviewer may only edit review.md: $rel"
            }
            return $null
        }
        if (($ShellTools -contains $ToolName) -and $isReviewer) {
            $cmd = [string]$ToolInput.command
            # nested shells would hide commands inside quotes -> deny outright
            if ($cmd -match '(?i)(^|[\s;|&(])(powershell|pwsh|bash|sh|cmd)(\.exe)?\s+(-c\b|-Command\b|/c\b|-EncodedCommand\b)') {
                return 'reviewer may not run nested shell commands (-c/-Command)'
            }
            # quoted text (e.g. commit messages with <email>) is replaced so it does not trigger write patterns
            $stripped = ($cmd -replace '"[^"]*"', 'Q') -replace "'[^']*'", 'Q'
            foreach ($pat in @($Cfg.reviewerBashDeny)) {
                if ($stripped -match $pat) { return "reviewer shell command looks like a write ($pat)" }
            }
        }
        return $null
    }

    # ---- codex ----
    $blob = ($ToolInput | ConvertTo-Json -Depth 8 -Compress)
    $blob = [regex]::Unescape($blob)
    foreach ($t in @($Cfg.codexForbiddenTokens)) {
        if ($t -and $blob.IndexOf($t, [StringComparison]::OrdinalIgnoreCase) -ge 0) { return "forbidden token '$t' in tool input" }
    }
    if ($blob.IndexOf($privBase, [StringComparison]::OrdinalIgnoreCase) -ge 0) { return "private root referenced" }

    $patchText = $null
    if ($ToolInput.PSObject.Properties['command']) {
        $c = $ToolInput.command
        if ($c -is [array]) { $c = $c -join "`n" }
        if ([string]$c -match '\*\*\* Begin Patch') { $patchText = [string]$c }
    }
    if (-not $patchText -and $ToolInput.PSObject.Properties['patch']) { $patchText = [string]$ToolInput.patch }
    if (-not $patchText -and $ToolInput.PSObject.Properties['input']) { $patchText = [string]$ToolInput.input }
    if ($patchText) {
        foreach ($p in (Get-PatchPaths $patchText)) {
            $rel = Get-RelPath $Root $p
            if ($null -eq $rel) { return "patch outside the project: $p" }
            if (Find-GlobMatch $rel $Cfg.codexWritable) { continue }   # review.md: line rules checked after commit
            $g = Find-GlobMatch $rel $Cfg.protected
            if ($g) { return "protected path ($g): $rel" }
            $g = Find-GlobMatch $rel $Cfg.lockedTests
            if ($g) { return "locked test ($g): $rel" }
        }
    }
    return $null
}

# ---------------- self test ----------------
if ($SelfTest) {
    $root = Find-HarnessRoot $PSScriptRoot
    $cfg = Get-HarnessConfig $root
    $note = ''
    if (-not (@($cfg.lockedTests) | Where-Object { $_ -and -not (Test-Placeholder $_) })) {
        $cfg.lockedTests = @('tests/locked/**'); $note = ' (lockedTests placeholder -> sample tests/locked/** used)'
    }
    $privBase = Get-PrivateBase $cfg
    $file = Join-Path $PSScriptRoot 'guard-tests.txt'
    $pass = 0; $fail = 0; $n = 0
    foreach ($line in [IO.File]::ReadAllLines($file, [Text.Encoding]::UTF8)) {
        $l = $line.Trim()
        if (-not $l -or $l.StartsWith('#')) { continue }
        $f = $l -split '\s*\|\s*', 5
        if ($f.Count -lt 5) { Write-Host "BAD LINE: $l"; $fail++; continue }
        $expect, $ag, $tool, $atype, $target = $f
        $target = $target.Replace('{PRIVATE}', $privBase).Replace('{ROOT}', $root)
        if ($atype -eq '-') { $atype = $null }
        $ti = New-Object psobject
        if ($WriteTools -contains $tool) {
            # "path ::: text" -> also set the written content
            $sp = $target -split '\s*:::\s*', 2
            $ti | Add-Member file_path $sp[0]
            if ($sp.Count -gt 1) { $ti | Add-Member content $sp[1] }
        }
        elseif ($tool -eq 'apply_patch') { $ti | Add-Member command ("*** Begin Patch`n*** Update File: $target`n@@`n-a`n+b`n*** End Patch") }
        else { $ti | Add-Member command $target }
        $n++
        $reason = Get-GuardDecision -Agent $ag -ToolName $tool -AgentType $atype -ToolInput $ti -Root $root -Cfg $cfg
        $got = 'allow'; if ($reason) { $got = 'deny' }
        if ($got -eq $expect) { $pass++ } else { $fail++; Write-Host ("FAIL #{0}: expected {1}, got {2} :: {3} {4}" -f $n, $expect, $got, $l, $reason) }
    }
    Write-Host ("guard self-test: {0} passed, {1} failed{2}" -f $pass, $fail, $note)
    if ($fail -gt 0) { exit 1 } else { exit 0 }
}

# ---------------- hook mode ----------------
try { [Console]::InputEncoding = [Text.Encoding]::UTF8 } catch {}
$raw = [Console]::In.ReadToEnd()
try { $evt = $raw | ConvertFrom-Json } catch {
    if ($Agent -eq 'codex') { [Console]::Error.WriteLine('[guard] cannot parse hook input; denying (fail closed)'); exit 2 }
    [Console]::Error.WriteLine('[guard] cannot parse hook input; allowing'); exit 0
}

$cwd = $null
if ($evt.PSObject.Properties['cwd']) { $cwd = [string]$evt.cwd }
$root = $null
if ($Agent -eq 'claude' -and $env:CLAUDE_PROJECT_DIR) { $root = Find-HarnessRoot $env:CLAUDE_PROJECT_DIR }
if (-not $root -and $cwd) { $root = Find-HarnessRoot $cwd }
if (-not $root) { $root = Find-HarnessRoot $PSScriptRoot }
if (-not $root) { exit 0 }
$cfg = Get-HarnessConfig $root

$toolName = [string]$evt.tool_name
$agentType = $null
if ($evt.PSObject.Properties['agent_type']) { $agentType = [string]$evt.agent_type }
$toolInput = $evt.tool_input
if ($null -eq $toolInput) { $toolInput = New-Object psobject }

$reason = Get-GuardDecision -Agent $Agent -ToolName $toolName -AgentType $agentType -ToolInput $toolInput -Root $root -Cfg $cfg
if ($reason) {
    [Console]::Error.WriteLine("[guard] blocked $toolName ($Agent$(if ($agentType) { '/' + $agentType })): $reason")
    exit 2
}
exit 0
