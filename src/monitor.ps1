<#
.SYNOPSIS
    ClawSysAdmin - System Monitor Module
.DESCRIPTION
    Real-time display of CPU/Memory/Disk/Network status
.AUTHOR
    NightClaw Digital
.VERSION
    0.3.0
#>

# Set per-script log name before loading common
$script:CSA_LogDir  = "$env:USERPROFILE/.openclaw/workspace/skills/system-cleanup/logs"
$script:CSA_LogFile = "$script:CSA_LogDir/monitor_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

. "$PSScriptRoot/common.ps1"

# ==================== CPU Monitor ====================
function Get-CPUStatus {
    try {
        $cpu = Get-Counter "\Processor(_Total)\% Processor Time" -ErrorAction SilentlyContinue
        $cpuUsage = [math]::Round($cpu.CounterSamples[0].CookedValue, 2)
        $cpuInfo = Get-CimInstance -ClassName Win32_Processor | Select-Object -First 1

        return @{
            Usage = $cpuUsage
            Name = $cpuInfo.Name
            Cores = $cpuInfo.NumberOfCores
            LogicalProcessors = $cpuInfo.NumberOfLogicalProcessors
            Status = Get-StatusIcon -Value $cpuUsage -Threshold 80
        }
    } catch {
        return @{ Usage = 0; Name = "Unknown"; Cores = 0; LogicalProcessors = 0; Status = "[?]" }
    }
}

# ==================== Memory Monitor ====================
function Get-MemoryStatus {
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem
        $total = $os.TotalVisibleMemorySize * 1KB
        $free = $os.FreePhysicalMemory * 1KB
        $used = $total - $free
        $usagePercent = [math]::Round(($used / $total) * 100, 2)
        
        return @{
            Total = Format-Bytes -Bytes $total
            Used = Format-Bytes -Bytes $used
            Free = Format-Bytes -Bytes $free
            UsagePercent = $usagePercent
            Status = Get-StatusIcon -Value $usagePercent -Threshold 85
        }
    } catch {
        return @{ Total = "0 B"; Used = "0 B"; Free = "0 B"; UsagePercent = 0; Status = "[?]" }
    }
}

# ==================== Disk Monitor ====================
function Get-DiskStatus {
    try {
        $disks = Get-CimInstance -ClassName Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 }
        $diskInfo = [System.Collections.ArrayList]::new()

        foreach ($disk in $disks) {
            $size = $disk.Size
            $free = $disk.FreeSpace
            $used = $size - $free
            $usagePercent = if ($size -gt 0) { [math]::Round(($used / $size) * 100, 2) } else { 0 }

            $null = $diskInfo.Add(@{
                Drive = $disk.DeviceID
                Label = $disk.VolumeName
                Total = Format-Bytes -Bytes $size
                Used = Format-Bytes -Bytes $used
                Free = Format-Bytes -Bytes $free
                UsagePercent = $usagePercent
                Status = Get-StatusIcon -Value $usagePercent -Threshold 85
            })
        }
        return $diskInfo
    } catch {
        return [System.Collections.ArrayList]::new()
    }
}

# ==================== Network Monitor ====================
function Get-NetworkStatus {
    try {
        $adapters = Get-NetAdapter | Where-Object { $_.Status -eq "Up" }
        $networkInfo = @()
        
        foreach ($adapter in $adapters) {
            $stats = Get-NetAdapterStatistics -Name $adapter.Name
            $networkInfo += @{
                Name = $adapter.Name
                LinkSpeed = $adapter.LinkSpeed
                ReceivedBytes = Format-Bytes -Bytes $stats.ReceivedBytes
                SentBytes = Format-Bytes -Bytes $stats.SentBytes
                Status = "[OK]"
            }
        }
        return $networkInfo
    } catch {
        return @()
    }
}

# ==================== System Uptime ====================
function Get-SystemUptime {
    try {
        $os = Get-CimInstance -ClassName Win32_OperatingSystem
        $uptime = (Get-Date) - $os.LastBootUpTime
        return "{0} days {1} hours {2} minutes" -f $uptime.Days, $uptime.Hours, $uptime.Minutes
    } catch {
        return "Unknown"
    }
}

# ==================== Main Function ====================
function Show-SystemStatus {
    Write-Host "`n============================================================" -ForegroundColor Cyan
    Write-Host "    ClawSysAdmin - System Status Monitor" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""

    try {
        Write-Log "System monitor started" -Level "INFO"

        # CPU Status
        $cpu = Get-CPUStatus
        Write-Host "[CPU Status]" -ForegroundColor Yellow
        Write-Host "  Processor: $($cpu.Name)" -ForegroundColor White
        Write-Host "  Cores: $($cpu.Cores) cores / $($cpu.LogicalProcessors) threads" -ForegroundColor White
        Write-Host "  Usage: $($cpu.Status) $($cpu.Usage)%" -ForegroundColor White
        Write-Host ""

        # Memory Status
        $memory = Get-MemoryStatus
        Write-Host "[Memory Status]" -ForegroundColor Yellow
        Write-Host "  Total: $($memory.Total)" -ForegroundColor White
        Write-Host "  Used: $($memory.Used) ($($memory.UsagePercent)%) $($memory.Status)" -ForegroundColor White
        Write-Host "  Free: $($memory.Free)" -ForegroundColor White
        Write-Host ""

        # Disk Status
        Write-Host "[Disk Status]" -ForegroundColor Yellow
        $disks = Get-DiskStatus
        if ($null -eq $disks -or $disks.Count -eq 0) {
            Write-Host "  Could not retrieve disk information" -ForegroundColor Gray
        } else {
            foreach ($disk in $disks) {
                Write-Host "  Drive $($disk.Drive) [$($disk.Label)]" -ForegroundColor White
                Write-Host "    Total: $($disk.Total) | Used: $($disk.Used) | Free: $($disk.Free)" -ForegroundColor Gray
                Write-Host "    Usage: $($disk.Status) $($disk.UsagePercent)%" -ForegroundColor White
            }
        }
        Write-Host ""

        # Network Status
        Write-Host "[Network Status]" -ForegroundColor Yellow
        $networks = Get-NetworkStatus
        if ($null -eq $networks -or $networks.Count -eq 0) {
            Write-Host "  No active network connection detected" -ForegroundColor Gray
        } else {
            foreach ($net in $networks) {
                Write-Host "  Adapter: $($net.Name)" -ForegroundColor White
                Write-Host "    Speed: $($net.LinkSpeed)" -ForegroundColor Gray
                Write-Host "    RX: $($net.ReceivedBytes) | TX: $($net.SentBytes)" -ForegroundColor Gray
            }
        }
        Write-Host ""

        # System Uptime
        $uptime = Get-SystemUptime
        Write-Host "[System Info]" -ForegroundColor Yellow
        Write-Host "  Uptime: $($uptime)" -ForegroundColor White
        Write-Host "  Check Time: $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -ForegroundColor Gray
        Write-Host ""

        # Status Legend
        Write-Host "[Legend]" -ForegroundColor Gray
        Write-Host "  [OK] Normal | [CAUTION] Attention | [WARNING] Alert | [?] Unknown" -ForegroundColor Gray
        Write-Host ""
        Write-Log "System monitor completed" -Level "SUCCESS"

    } catch {
        Write-Log "Monitor encountered an unexpected error: $($_.Exception.Message)" -Level "ERROR"
        Write-Host ""
        Write-Host "ERROR: Monitor encountered an unexpected error." -ForegroundColor Red
        Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  Partial results may have been displayed above." -ForegroundColor Gray
        Write-Host ""
        exit 1
    }
}

# Execute main function
Show-SystemStatus
