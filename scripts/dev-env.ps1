#requires -Version 5.1
<#
  dev-env.ps1
  Locate git / node / pnpm / gh on Windows and prepend them to PATH
  for the CURRENT PowerShell session only.

  - No admin rights needed.
  - Does not touch the registry or system environment.
  - Missing tools are reported, not fatal.

  Usage:
    .\dev-env.ps1
    .\dev-env.ps1 -GitDir D:\tools\PortableGit\cmd -NodeDir D:\tools\node
    .\dev-env.ps1 -Quiet
#>
[CmdletBinding()]
param(
    [string]$GitDir,
    [string]$NodeDir,
    [switch]$Quiet
)

$ErrorActionPreference = 'Continue'

$Root = Split-Path -Parent $PSScriptRoot
$Added = New-Object System.Collections.Generic.List[string]

function Find-Tool {
    param([string[]]$Dirs, [string[]]$Leaves)
    foreach ($dir in $Dirs) {
        if ([string]::IsNullOrWhiteSpace($dir)) { continue }
        foreach ($leaf in $Leaves) {
            $p = Join-Path $dir $leaf
            if (Test-Path -LiteralPath $p) {
                return (Split-Path -Parent $p)
            }
        }
    }
    return $null
}

function Add-ToPath {
    param([string]$Dir)
    if ([string]::IsNullOrWhiteSpace($Dir)) { return }
    $resolved = [System.IO.Path]::GetFullPath($Dir).TrimEnd('\')
    $parts = @($env:PATH -split ';' | Where-Object { $_ })
    foreach ($p in $parts) {
        if ($p.TrimEnd('\') -ieq $resolved) { return }
    }
    if ($Added -notcontains $resolved) { $Added.Add($resolved) }
    $env:PATH = $resolved + ';' + $env:PATH
}

function Get-Version {
    param([string]$Exe, [string[]]$Arguments)
    try {
        $out = & $Exe @Arguments 2>&1 | Out-String
        return ($out.Trim() -split "`r?`n")[0]
    } catch {
        return $null
    }
}

# ---------------------------------------------------------------- git
$gitCandidates = @(
    $GitDir,
    (Join-Path $Root 'tools\PortableGit\cmd'),
    'C:\Program Files\Git\cmd',
    'C:\Program Files (x86)\Git\cmd',
    (Join-Path $env:LOCALAPPDATA 'Programs\Git\cmd')
)
$gitBin = Find-Tool -Dirs $gitCandidates -Leaves @('git.exe')
if ($gitBin) { Add-ToPath $gitBin }

# ---------------------------------------------------------------- node
$nodeCandidates = @(
    $NodeDir,
    (Join-Path $Root 'tools\node'),
    'C:\Program Files\nodejs',
    (Join-Path $env:LOCALAPPDATA 'Programs\nodejs')
)
$nodeBin = Find-Tool -Dirs $nodeCandidates -Leaves @('node.exe')
if ($nodeBin) { Add-ToPath $nodeBin }

# ---------------------------------------------------------------- pnpm / npm shims
$shimDirs = @(
    (Join-Path $env:APPDATA 'npm'),
    (Join-Path $env:LOCALAPPDATA 'pnpm')
)
foreach ($d in $shimDirs) {
    if (Test-Path -LiteralPath $d) {
        $hasShim = @('pnpm.cmd', 'pnpm.exe', 'npm.cmd') |
            Where-Object { Test-Path -LiteralPath (Join-Path $d $_) }
        if ($hasShim) { Add-ToPath $d }
    }
}

# ---------------------------------------------------------------- gh
$ghCandidates = @(
    'C:\Program Files\GitHub CLI',
    (Join-Path $env:LOCALAPPDATA 'Programs\gh'),
    (Join-Path $env:LOCALAPPDATA 'Microsoft\WinGet\Links')
)
$ghBin = Find-Tool -Dirs $ghCandidates -Leaves @('gh.exe')
if ($ghBin) { Add-ToPath $ghBin }

# ---------------------------------------------------------------- report
function Resolve-Exe {
    param([string]$Name)
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($cmd) { return $cmd.Source }
    return $null
}

$rows = @(
    [pscustomobject]@{ Tool = 'git';  Exe = (Resolve-Exe 'git.exe');  Args = @('--version'); Hint = 'winget install Git.Git  /  PortableGit' }
    [pscustomobject]@{ Tool = 'node'; Exe = (Resolve-Exe 'node.exe'); Args = @('-v');         Hint = 'winget install OpenJS.NodeJS.LTS' }
    [pscustomobject]@{ Tool = 'pnpm'; Exe = (Resolve-Exe 'pnpm.cmd'); Args = @('-v');         Hint = 'npm i -g pnpm' }
    [pscustomobject]@{ Tool = 'gh';   Exe = (Resolve-Exe 'gh.exe');   Args = @('--version');  Hint = 'winget install GitHub.cli' }
)

$table = foreach ($r in $rows) {
    if ($r.Exe) {
        $ver = Get-Version -Exe $r.Exe -Arguments $r.Args
        [pscustomobject]@{
            tool    = $r.Tool
            status  = 'OK'
            version = $ver
            where   = $r.Exe
        }
    } else {
        [pscustomobject]@{
            tool    = $r.Tool
            status  = 'MISSING'
            version = '-'
            where   = 'install: ' + $r.Hint
        }
    }
}

if (-not $Quiet) {
    Write-Host ''
    Write-Host ('  dev-env  ({0})' -f $PSVersionTable.PSVersion) -ForegroundColor Cyan
    Write-Host ('  added to PATH: {0} dir(s)' -f $Added.Count) -ForegroundColor DarkGray
    Write-Host ''
    $table | Format-Table -AutoSize | Out-String | Write-Host
    if ($Added.Count -gt 0) {
        foreach ($a in $Added) { Write-Host ('    + ' + $a) -ForegroundColor DarkGray }
        Write-Host ''
    }
    Write-Host '  session only. close this window to revert.' -ForegroundColor DarkGray
    Write-Host ''
}

$missing = @($table | Where-Object { $_.status -ne 'OK' } | ForEach-Object { $_.tool })

# Do not exit when dot-sourced from a profile - it would close the user's shell.
if ($MyInvocation.InvocationName -ne '.') {
    if ($missing.Count -gt 0) { exit 2 }
    exit 0
}
