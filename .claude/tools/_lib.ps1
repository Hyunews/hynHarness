# _lib.ps1 - shared helpers (dot-source). PowerShell 5.1 compatible. Save as UTF-8 with BOM.
Set-StrictMode -Version 2
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch {}
$OutputEncoding = [Text.Encoding]::UTF8

function Find-HarnessRoot([string]$Start) {
    if (-not $Start) { $Start = (Get-Location).Path }
    $d = [IO.Path]::GetFullPath((ConvertFrom-PosixPath $Start))
    while ($d) {
        if (Test-Path -LiteralPath (Join-Path $d '.harness\config.json')) { return $d }
        $p = Split-Path $d -Parent
        if (-not $p -or $p -eq $d) { break }
        $d = $p
    }
    return $null
}

function Get-HarnessConfig([string]$Root) {
    $raw = [IO.File]::ReadAllText((Join-Path $Root '.harness\config.json'), [Text.Encoding]::UTF8)
    return $raw | ConvertFrom-Json
}

function Read-Utf8([string]$Path) { return [IO.File]::ReadAllText($Path, [Text.Encoding]::UTF8) }

function Write-Utf8([string]$Path, [string]$Text) {
    $dir = Split-Path $Path -Parent
    if ($dir -and -not (Test-Path -LiteralPath $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }
    [IO.File]::WriteAllText($Path, $Text, (New-Object Text.UTF8Encoding $false))
}

function Test-Placeholder([string]$s) { return ($s -match '\{\{.*\}\}') }

function Get-ProjectName([string]$Root, $Cfg) {
    if ($Cfg.project -and -not (Test-Placeholder $Cfg.project)) { return $Cfg.project }
    return (Split-Path $Root -Leaf)
}

# Private root for this project (outside the repo). With -Id: the task folder.
function Get-PrivateDir([string]$Root, $Cfg, [string]$Id) {
    $base = [Environment]::ExpandEnvironmentVariables([string]$Cfg.privateRoot)
    $d = Join-Path $base (Get-ProjectName $Root $Cfg)
    if ($Id) { $d = Join-Path $d $Id }
    return [IO.Path]::GetFullPath($d)
}

function Get-PrivateBase($Cfg) {
    return [IO.Path]::GetFullPath([Environment]::ExpandEnvironmentVariables([string]$Cfg.privateRoot))
}

# /c/Users/x -> C:/Users/x ; ~ -> USERPROFILE
function ConvertFrom-PosixPath([string]$p) {
    if ($p -match '^/([a-zA-Z])/(.*)$') { return ($Matches[1].ToUpper() + ':/' + $Matches[2]) }
    if ($p -match '^~[/\\](.*)$') { return (Join-Path $env:USERPROFILE $Matches[1]) }
    return $p
}

function Get-FullPath([string]$Root, [string]$Path) {
    $p = ConvertFrom-PosixPath $Path
    if (-not [IO.Path]::IsPathRooted($p)) { $p = Join-Path $Root $p }
    return [IO.Path]::GetFullPath($p)
}

# Repo-relative path with forward slashes, or $null when outside the repo.
function Get-RelPath([string]$Root, [string]$Path) {
    $full = Get-FullPath $Root $Path
    $r = [IO.Path]::GetFullPath($Root).TrimEnd('\') + '\'
    if ($full.StartsWith($r, [StringComparison]::OrdinalIgnoreCase)) {
        return ($full.Substring($r.Length) -replace '\\', '/')
    }
    if ($full.TrimEnd('\') -ieq $r.TrimEnd('\')) { return '' }
    return $null
}

function Test-UnderDir([string]$Full, [string]$Dir) {
    $d = $Dir.TrimEnd('\') + '\'
    return ($Full.StartsWith($d, [StringComparison]::OrdinalIgnoreCase) -or $Full.TrimEnd('\') -ieq $Dir.TrimEnd('\'))
}

# gitignore-like glob -> regex. ** = any depth, * = one segment, ? = one char.
function ConvertTo-GlobRegex([string]$Glob) {
    $g = $Glob -replace '\\', '/'
    $sb = New-Object Text.StringBuilder
    $i = 0
    while ($i -lt $g.Length) {
        $c = $g[$i]
        if ($c -eq '*') {
            if ($i + 1 -lt $g.Length -and $g[$i + 1] -eq '*') {
                if ($i + 2 -lt $g.Length -and $g[$i + 2] -eq '/') { [void]$sb.Append('(?:.*/)?'); $i += 3; continue }
                [void]$sb.Append('.*'); $i += 2; continue
            }
            [void]$sb.Append('[^/]*')
        } elseif ($c -eq '?') { [void]$sb.Append('[^/]') }
        else { [void]$sb.Append([regex]::Escape([string]$c)) }
        $i++
    }
    return '^' + $sb.ToString() + '$'
}

# Returns the first matching glob (placeholders skipped) or $null.
function Find-GlobMatch([string]$Rel, $Globs) {
    if ($null -eq $Rel) { return $null }
    foreach ($g in @($Globs)) {
        if (-not $g -or (Test-Placeholder $g)) { continue }
        if ($Rel -match (ConvertTo-GlobRegex $g)) { return $g }
    }
    return $null
}

# Quote one argument for a Windows command line (CommandLineToArgvW rules).
# PowerShell 5.1 does not escape embedded quotes for native programs, so build the line ourselves.
function ConvertTo-WinArg([string]$a) {
    if ($a -and $a -notmatch '[\s"]') { return $a }
    $sb = New-Object Text.StringBuilder
    [void]$sb.Append('"')
    $bs = 0
    foreach ($ch in $a.ToCharArray()) {
        if ($ch -eq '\') { $bs++; continue }
        if ($ch -eq '"') { [void]$sb.Append('\' * (2 * $bs + 1)); [void]$sb.Append('"') }
        else { if ($bs) { [void]$sb.Append('\' * $bs) }; [void]$sb.Append($ch) }
        $bs = 0
    }
    if ($bs) { [void]$sb.Append('\' * (2 * $bs)) }
    [void]$sb.Append('"')
    return $sb.ToString()
}

# Base commit of a task = the OLDEST plan(<id>) commit (the state before Codex touched anything).
function Get-TaskBase([string]$Id) {
    $plans = @(Find-TaskCommits 'plan' $Id)
    if ($plans.Count -eq 0) { return $null }
    return $plans[$plans.Count - 1].Hash
}

function Invoke-Git {
    # Runs git with UTF-8 output; returns stdout lines. Throws on failure.
    # Simple function (no param block) so git flags like -E are not taken as PowerShell parameters.
    $GitArgs = @($args)
    $prev = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
    $out = & git -c core.quotepath=off -c i18n.logOutputEncoding=UTF-8 @GitArgs 2>$null
    $ErrorActionPreference = $prev
    if ($LASTEXITCODE -ne 0) { throw ("git " + ($GitArgs -join ' ') + " failed: " + ($out -join "`n")) }
    return @($out | ForEach-Object { [string]$_ })
}

function Find-TaskCommits([string]$Prefix, [string]$Id, [string]$Range) {
    # Newest first. Returns objects {Hash, Subject}. -Range e.g. "<hash>..HEAD" limits the search.
    $pat = '^' + $Prefix + '\(' + [regex]::Escape($Id) + '\)'
    if ($Range) { $lines = Invoke-Git log '--format=%H%x09%s' -E "--grep=$pat" $Range }
    else { $lines = Invoke-Git log '--format=%H%x09%s' -E "--grep=$pat" }
    $res = @()
    foreach ($l in $lines) {
        if (-not $l) { continue }
        $parts = $l -split "`t", 2
        $res += New-Object psobject -Property @{ Hash = $parts[0]; Subject = $parts[1] }
    }
    return $res
}
