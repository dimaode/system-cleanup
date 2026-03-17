<#
.SYNOPSIS
    ClawSysAdmin - Common Utilities Module
.DESCRIPTION
    Shared functions: logging, byte formatting, status indicators.
    All scripts in this skill should dot-source this module:
        . "$PSScriptRoot/common.ps1"
.AUTHOR
    NightClaw Digital / 夜爪数字公司
.VERSION
    1.0.0
#>

# ==================== Encoding ====================
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ==================== Log Setup ====================
# $script:CSA_LogFile can be overridden before dot-sourcing if a custom path is needed.
# Default: logs/csa_<timestamp>.log under the skill root.
if (-not $script:CSA_LogFile) {
    $script:CSA_LogDir = "$env:USERPROFILE/.openclaw/workspace/skills/system-cleanup/logs"
    $script:CSA_LogFile = "$script:CSA_LogDir/csa_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"
}

# Ensure log directory exists
try {
    if (!(Test-Path $script:CSA_LogDir)) {
        New-Item -ItemType Directory -Path $script:CSA_LogDir -Force | Out-Null
    }
} catch {
    # If log dir creation fails, log to temp
    $script:CSA_LogFile = "$env:TEMP/csa_fallback.log"
}

# ==================== Write-Log ====================
# Unified log function. Writes timestamped entries to file AND colorized console output.
# Levels: DEBUG | INFO | SUCCESS | WARN | ERROR
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("DEBUG","INFO","SUCCESS","WARN","ERROR")]
        [string]$Level = "INFO"
    )
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry  = "[$timestamp] [$Level] $Message"

    try {
        Add-Content -Path $script:CSA_LogFile -Value $logEntry -ErrorAction SilentlyContinue
    } catch {}

    switch ($Level) {
        "DEBUG"   { Write-Host $Message -ForegroundColor DarkGray }
        "INFO"    { Write-Host $Message -ForegroundColor White }
        "SUCCESS" { Write-Host $Message -ForegroundColor Green }
        "WARN"    { Write-Host $Message -ForegroundColor Yellow }
        "ERROR"   { Write-Host $Message -ForegroundColor Red }
    }
}

# ==================== Format-Bytes ====================
# Convert a raw byte count to human-readable string (B / KB / MB / GB / TB).
function Format-Bytes {
    param([long]$Bytes)
    if ($Bytes -lt 0) { $Bytes = 0 }
    $sizes = @("B", "KB", "MB", "GB", "TB")
    $order = 0
    $value = [double]$Bytes
    while ($value -ge 1024 -and $order -lt ($sizes.Count - 1)) {
        $value /= 1024
        $order++
    }
    return "{0:N2} {1}" -f $value, $sizes[$order]
}

# ==================== Status Helpers ====================
# Returns a text tag based on a percentage value vs threshold.
# Used by monitor.ps1 and report.ps1.
function Get-StatusIcon {
    param(
        [double]$Value,
        [double]$Threshold = 80
    )
    if ($Value -ge $Threshold)            { return "[WARNING]" }
    if ($Value -ge ($Threshold - 15))     { return "[CAUTION]" }
    return "[OK]"
}

# Chinese-flavored variant used by report.ps1
function Get-StatusText {
    param(
        [double]$Value,
        [double]$Threshold = 80
    )
    if ($Value -ge $Threshold)            { return "警告 [HIGH]" }
    if ($Value -ge ($Threshold - 15))     { return "注意 [MID]" }
    return "正常 [OK]"
}
