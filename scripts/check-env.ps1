#requires -Version 5.1
<#
  check-env.ps1
  Read-only environment check for a Windows dev machine:
  OS / PowerShell / git / node / pnpm / gh, plus an OPTIONAL network probe.

  Nothing is installed, nothing is modified.

  Usage:
    .\check-env.ps1
    .\check-env.ps1 -TestNetwork
    .\check-env.ps1 -TestNetwork -HostName github.com -Port 443 -TimeoutMs 5000
#>
[CmdletBinding()]
param(
    [switch]$TestNetwork,
    [string]$HostName = 'github.com',
    [int]$Port = 443,
    [int]$TimeoutMs = 5000
)

$ErrorActionPreference = 'Continue'

function Get-ToolVersion {
    param([string]$Name, [string[]]$Arguments)
    $cmd = Get-Command $Name -ErrorAction SilentlyContinue | Select-Object -First 1
    if (-not $cmd) { return $null }
    $ver = $null
    try { $ver = (& $cmd.Source @Arguments 2>&1 | Out-String).Trim().Split("`n")[0].Trim() } catch { }
    return [pscustomobject]@{ Path = $cmd.Source; Version = $ver }
}

function Test-Tcp {
    param([string]$Target, [int]$TargetPort, [int]$Timeout)
    $client = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $client.BeginConnect($Target, $TargetPort, $null, $null)
        if (-not $iar.AsyncWaitHandle.WaitOne($Timeout, $false)) { return $false }
        $client.EndConnect($iar)
        return $true
    } catch {
        return $false
    } finally {
        try { $client.Close() } catch { }
    }
}

$rows = New-Object System.Collections.ArrayList

function Add-Row {
    param([string]$Item, [string]$Status, [string]$Detail, [string]$Fix = '')
    [void]$rows.Add([pscustomobject]@{
            item   = $Item
            status = $Status
            detail = $Detail
            fix    = $Fix
        })
}

# ---------------------------------------------------------------- system
# CIM/WMI is not always reachable (locked-down machines, some sandboxes),
# so fall back to the registry, then to the .NET version string.
$osName = $null
try {
    $cim = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
    $osName = ($cim.Caption + ' ' + $cim.Version).Trim()
} catch { }
if (-not $osName) {
    try {
        $k = Get-ItemProperty -LiteralPath 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction Stop
        $osName = ('{0} {1} (build {2})' -f $k.ProductName, $k.DisplayVersion, $k.CurrentBuildNumber).Trim()
    } catch { }
}
if (-not $osName) { $osName = [Environment]::OSVersion.VersionString }
if ($osName) { Add-Row 'OS' 'OK' $osName '' } else { Add-Row 'OS' 'WARN' 'unknown' '' }

Add-Row 'PowerShell' 'OK' ($PSVersionTable.PSVersion.ToString()) ''

$is64 = [Environment]::Is64BitProcess
Add-Row 'process bitness' 'OK' $(if ($is64) { '64-bit' } else { '32-bit (use a 64-bit shell)' }) ''

# ---------------------------------------------------------------- tools
$git = Get-ToolVersion 'git.exe' @('--version')
if ($git) { Add-Row 'git' 'OK' $git.Version $git.Path }
else { Add-Row 'git' 'FAIL' 'not found' 'winget install Git.Git  /  unzip PortableGit into tools\PortableGit' }

$node = Get-ToolVersion 'node.exe' @('-v')
if ($node) { Add-Row 'node' 'OK' $node.Version $node.Path }
else { Add-Row 'node' 'FAIL' 'not found' 'winget install OpenJS.NodeJS.LTS' }

$pnpm = Get-ToolVersion 'pnpm.cmd' @('-v')
if (-not $pnpm) { $pnpm = Get-ToolVersion 'pnpm.exe' @('-v') }
if ($pnpm) { Add-Row 'pnpm' 'OK' $pnpm.Version $pnpm.Path }
else { Add-Row 'pnpm' 'WARN' 'not found' 'npm i -g pnpm' }

$gh = Get-ToolVersion 'gh.exe' @('--version')
if ($gh) { Add-Row 'gh' 'WARN' $gh.Version ($gh.Path + '  (optional)') }
else { Add-Row 'gh' 'WARN' 'not found (optional)' 'winget install GitHub.cli' }

# ---------------------------------------------------------------- identity
$gitUser = $null
$gitEmail = $null
if ($git) {
    try { $gitUser = (git config --global user.name 2>$null) } catch { }
    try { $gitEmail = (git config --global user.email 2>$null) } catch { }
}
if (-not $git) {
    Add-Row 'git identity' 'SKIP' 'needs git first' ''
} elseif ($gitUser -and $gitEmail) {
    $warn = ''
    if ($gitEmail -notmatch 'noreply\.github\.com$') { $warn = '  <- not a noreply address, it will be public in every commit' }
    Add-Row 'git identity' 'OK' ($gitUser + ' <' + $gitEmail + '>') $warn
} else {
    Add-Row 'git identity' 'WARN' 'not configured' 'git config --global user.name "..." / user.email "..."'
}

# ---------------------------------------------------------------- network (opt-in)
if ($TestNetwork) {
    $label = 'TCP ' + $HostName + ':' + $Port
    if (Test-Tcp -Target $HostName -TargetPort $Port -Timeout $TimeoutMs) {
        Add-Row $label 'OK' ('connected within ' + $TimeoutMs + ' ms budget') ''
    } else {
        Add-Row $label 'FAIL' ('no connection in ' + $TimeoutMs + ' ms') 'check proxy / VPN'
    }
} else {
    Add-Row 'network' 'SKIP' 'use -TestNetwork to probe' ''
}

# ---------------------------------------------------------------- report
Write-Host ''
Write-Host '  environment check' -ForegroundColor Cyan
Write-Host ''
$rows | Format-Table -Property item, status, detail, fix -AutoSize | Out-String | Write-Host

$bad = @($rows | Where-Object { $_.status -eq 'FAIL' })
$warn = @($rows | Where-Object { $_.status -eq 'WARN' })
$ok = @($rows | Where-Object { $_.status -eq 'OK' })

$summary = '  {0} ok, {1} warn, {2} fail' -f $ok.Count, $warn.Count, $bad.Count
Write-Host $summary -ForegroundColor $(if ($bad.Count -gt 0) { 'Red' } elseif ($warn.Count -gt 0) { 'Yellow' } else { 'Green' })
Write-Host ''

if ($bad.Count -gt 0) { exit 1 }
exit 0
