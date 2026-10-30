@echo off
setlocal
title OpenCode Free
set "PS1=%TEMP%\opencode-free.ps1"
more +7 "%~f0" > "%PS1%"
powershell -NoProfile -ExecutionPolicy Bypass -File "%PS1%"
exit /b
# OpenCode Free - launch the OpenCode desktop app through a rotatable WARP
# egress and restart it automatically when the free tier answers "limit".
#
# Portable: no paths are hardcoded. The app, warp-cli and the opencode log
# are discovered at runtime. Every setting can be overridden by an
# environment variable (see the config block).

$ErrorActionPreference = 'Continue'
$Version = '1.0.0'

# ---- config (override with environment variables) --------------------------
$ProxyPort = if ($env:OC_PROXY_PORT) { [int]$env:OC_PROXY_PORT } else { 40000 }
$ProxyUrl  = 'http://127.0.0.1:' + $ProxyPort
$Cooldown  = if ($env:OC_COOLDOWN) { [int]$env:OC_COOLDOWN } else { 45 }
$NoRotate  = ($env:OC_NO_ROTATE -eq '1')
$Fatal     = 'Free usage limit reached|Rate limit exceeded'
$Tmp       = Join-Path $env:TEMP ('ocfree-' + [guid]::NewGuid().ToString('N'))
$StateDir  = Join-Path $env:LOCALAPPDATA 'opencode-free'
$PidFile   = Join-Path $StateDir 'wrapper.pid'

New-Item -ItemType Directory -Force -Path $StateDir | Out-Null
New-Item -ItemType Directory -Force -Path $Tmp | Out-Null

function Say([string]$m, [string]$c = 'Gray') { Write-Host $m -ForegroundColor $c }

# ---- discovery -------------------------------------------------------------
function Find-Warp {
    $cands = @()
    if ($env:OC_WARP) { $cands += $env:OC_WARP }
    if ($env:ProgramFiles)      { $cands += (Join-Path $env:ProgramFiles 'Cloudflare\Cloudflare WARP\warp-cli.exe') }
    if (${env:ProgramFiles(x86)}) { $cands += (Join-Path ${env:ProgramFiles(x86)} 'Cloudflare\Cloudflare WARP\warp-cli.exe') }
    if ($env:LOCALAPPDATA)      { $cands += (Join-Path $env:LOCALAPPDATA 'Cloudflare\Cloudflare WARP\warp-cli.exe') }
    foreach ($c in $cands) { if (Test-Path -LiteralPath $c) { return $c } }
    $w = Get-Command 'warp-cli.exe' -ErrorAction SilentlyContinue
    if ($w) { return $w.Source }
    return $null
}

function Find-App {
    $cands = @()
    if ($env:OC_APP) { $cands += $env:OC_APP }
    if ($env:LOCALAPPDATA) {
        $cands += (Join-Path $env:LOCALAPPDATA 'Programs\ai.opencode.desktop\OpenCode.exe')
        $cands += (Join-Path $env:LOCALAPPDATA 'Programs\opencode\OpenCode.exe')
        $cands += (Join-Path $env:LOCALAPPDATA 'opencode\OpenCode.exe')
    }
    if ($env:ProgramFiles) { $cands += (Join-Path $env:ProgramFiles 'opencode\OpenCode.exe') }
    foreach ($c in $cands) { if (Test-Path -LiteralPath $c) { return $c } }
    $w = Get-Command 'OpenCode.exe' -ErrorAction SilentlyContinue
    if ($w) { return $w.Source }
    return $null
}

function Find-Log {
    $a = Join-Path $env:USERPROFILE '.local\share\opencode\log\opencode.log'
    $b = Join-Path $env:LOCALAPPDATA 'opencode\log\opencode.log'
    if (Test-Path -LiteralPath $b) { return $b }
    return $a
}

# ---- single instance -------------------------------------------------------
if (Test-Path -LiteralPath $PidFile) {
    $old = 0
    try { $old = [int]((Get-Content -LiteralPath $PidFile -TotalCount 1) -as [string]) } catch { $old = 0 }
    if ($old -gt 0) {
        $op = Get-Process -Id $old -ErrorAction SilentlyContinue
        if ($op -and $op.ProcessName -eq 'powershell') {
            Stop-Process -Id $old -Force -ErrorAction SilentlyContinue
            Start-Sleep -Seconds 1
        }
    }
}
Set-Content -LiteralPath $PidFile -Value $PID

# ---- warp ------------------------------------------------------------------
function Invoke-Warp([string[]]$WarpArgs, [int]$Timeout = 40) {
    $o = Join-Path $Tmp 'w.out'
    $e = Join-Path $Tmp 'w.err'
    $p = Start-Process -FilePath $script:WarpCli -ArgumentList $WarpArgs -NoNewWindow -PassThru -RedirectStandardOutput $o -RedirectStandardError $e
    if (-not $p) { return $null }
    if (-not $p.WaitForExit($Timeout * 1000)) {
        try { $p.Kill() } catch {}
        return $null
    }
    $text = ''
    try { $text = (Get-Content -LiteralPath $o -Raw -ErrorAction SilentlyContinue) } catch {}
    try { $text += (Get-Content -LiteralPath $e -Raw -ErrorAction SilentlyContinue) } catch {}
    return $text
}

function Test-Proxy {
    if (-not (Get-Command 'curl.exe' -ErrorAction SilentlyContinue)) { return $true }
    try {
        $r = (& curl.exe -s --max-time 8 -x $ProxyUrl 'https://www.cloudflare.com/cdn-cgi/trace' 2>$null) -join "`n"
        return ($r -match 'warp=on')
    } catch { return $false }
}

function Get-ProxyIp {
    try {
        $r = (& curl.exe -s --max-time 8 -x $ProxyUrl 'https://www.cloudflare.com/cdn-cgi/trace' 2>$null) -join "`n"
        if ($r -match 'ip=([^\r\n]+)') { return $Matches[1] }
    } catch {}
    return $null
}

function Rotate-Warp {
    Invoke-Warp @('mode', 'proxy') | Out-Null
    Invoke-Warp @('proxy', 'port', [string]$ProxyPort) | Out-Null
    Invoke-Warp @('disconnect') | Out-Null
    Start-Sleep -Seconds 2
    Invoke-Warp @('registration', 'delete') | Out-Null
    Start-Sleep -Seconds 2
    Invoke-Warp @('registration', 'new') | Out-Null
    Start-Sleep -Seconds 2
    Invoke-Warp @('connect') | Out-Null
    for ($i = 0; $i -lt 25; $i++) {
        if (Test-Proxy) { return $true }
        Start-Sleep -Seconds 1
    }
    return $false
}

# ---- app -------------------------------------------------------------------
function Stop-App {
    foreach ($n in @('OpenCode', 'opencode-cli')) {
        Get-Process -Name $n -ErrorAction SilentlyContinue | Stop-Process -Force -ErrorAction SilentlyContinue
    }
    Start-Sleep -Seconds 3
}

function Start-App {
    if ($script:useProxy) {
        $env:HTTP_PROXY  = $ProxyUrl
        $env:HTTPS_PROXY = $ProxyUrl
        $env:ALL_PROXY   = $ProxyUrl
        $env:NO_PROXY    = 'localhost,127.0.0.1,::1'
    } else {
        Remove-Item Env:HTTP_PROXY, Env:HTTPS_PROXY, Env:ALL_PROXY, Env:NO_PROXY -ErrorAction SilentlyContinue
    }
    return Start-Process -FilePath $script:AppExe -PassThru
}

# ---- log tail --------------------------------------------------------------
function Get-LogOffset {
    if (-not (Test-Path -LiteralPath $script:LogFile)) { return 0 }
    try { return (Get-Item -LiteralPath $script:LogFile).Length } catch { return 0 }
}

function Read-LogFrom([int64]$Offset) {
    if (-not (Test-Path -LiteralPath $script:LogFile)) { return @{ Text = ''; Offset = 0 } }
    try { $fs = [IO.File]::Open($script:LogFile, 'Open', 'Read', 'ReadWrite') } catch { return @{ Text = ''; Offset = $Offset } }
    try {
        if ($fs.Length -lt $Offset) { $Offset = 0 }
        if ($fs.Length -eq $Offset) { return @{ Text = ''; Offset = $Offset } }
        [void]$fs.Seek($Offset, 'Begin')
        $sr = New-Object IO.StreamReader($fs)
        $text = $sr.ReadToEnd()
        $newOffset = $fs.Length
        $sr.Close()
        return @{ Text = $text; Offset = $newOffset }
    } finally { $fs.Close() }
}

# ---- main ------------------------------------------------------------------
Say ('opencode-free ' + $Version) 'Green'
Say '  keeps the free tier alive by moving the egress IP' 'DarkGray'

$script:AppExe  = Find-App
$script:WarpCli = Find-Warp
$script:LogFile = Find-Log

if (-not $script:AppExe) {
    Say '  [err] OpenCode desktop not found.' 'Red'
    Say '        install it from https://opencode.ai or set OC_APP=full\path\OpenCode.exe' 'Gray'
    exit 1
}
Say ('  app : ' + $script:AppExe) 'Gray'
Say ('  log : ' + $script:LogFile) 'Gray'

$script:useProxy = $false
if (-not $script:WarpCli) {
    Say '  [warp] not installed - running direct, no rotation' 'Yellow'
    Say '        get it at https://1.1.1.1 (WARP client)' 'Gray'
} elseif ($NoRotate) {
    Say '  [warp] rotation disabled by OC_NO_ROTATE' 'Yellow'
} else {
    Say '  [warp] rotating egress...' 'Cyan'
    $script:useProxy = Rotate-Warp
    if ($script:useProxy) { Say ('  [warp] exit ' + (Get-ProxyIp)) 'Cyan' }
    else { Say '  [warp] rotation failed - running direct' 'Yellow' }
}

$script:lastRot = Get-Date
$rotations = 0

while ($true) {
    Stop-App
    $offset = Get-LogOffset
    $app = Start-App
    if (-not $app) { exit 1 }
    Say ('  [ok] opencode started, pid ' + $app.Id) 'Green'

    while ($true) {
        Start-Sleep -Seconds 2
        if (-not (Get-Process -Id $app.Id -ErrorAction SilentlyContinue)) {
            if (-not (Get-Process -Name 'opencode-cli' -ErrorAction SilentlyContinue)) {
                Say '  [exit] app closed' 'Gray'
                Remove-Item -LiteralPath $PidFile -ErrorAction SilentlyContinue
                exit 0
            }
        }

        $chunk = Read-LogFrom $offset
        $offset = $chunk.Offset
        if (-not $chunk.Text) { continue }
        if ($chunk.Text -notmatch $Fatal) { continue }
        if (((Get-Date) - $script:lastRot).TotalSeconds -lt $Cooldown) { continue }

        Say '  [limit] free quota hit' 'Yellow'
        Stop-App

        $done = $false
        for ($try = 1; $try -le 2; $try++) {
            Say ('  [warp] rotating (try ' + $try + ')') 'Cyan'
            if (Rotate-Warp) { $done = $true; break }
            Start-Sleep -Seconds 5
        }
        if ($done) {
            $script:lastRot = Get-Date
            $script:useProxy = $true
            $rotations++
            Say ('  [warp] exit ' + (Get-ProxyIp)) 'Cyan'
            Say ('  [rot] count ' + $rotations) 'Cyan'
        } else {
            $script:useProxy = $false
            Say '  [warp] rotation failed - starting direct' 'Red'
        }
        Start-Sleep -Seconds 3
        break
    }
}
