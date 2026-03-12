<#
.SYNOPSIS
    ClawSysAdmin - System Monitor Module
.DESCRIPTION
    Real-time display of CPU/Memory/Disk/Network status
.AUTHOR
    NightClaw Digital
.VERSION
    0.1.0
#>

# Set encoding
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Helper function: Format bytes
function Format-Bytes {
    param([long]$Bytes)
    $sizes = @("B", "KB", "MB", "GB", "TB")
    $order = 0
    $value = $Bytes
    while ($value -ge 1024 -and $order -lt $sizes.Count - 1) {
        $value = $value / 1024
        $order++
    }
    return "{0:N2} {1}" -f $value, $sizes[$order]
}

# Helper function: Get status icon
function Get-StatusIcon {
    param([int]$Value, [int]$Threshold = 80)
    if ($Value -ge $Threshold) { return "[WARNING]" }
    if ($Value -ge ($Threshold - 15)) { return "[CAUTION]" }
    return "[OK]"
}

# ==================== CPU Monitor ====================
function Get-CPUStatus {
    try {
        $cpu = Get-Counter "\Processor(_Total)\% Processor Time" -ErrorAction SilentlyContinue
        $cpuUsage = [math]::Round($cpu.CounterSamples[0].CookedValue, 2)
        $cpuInfo = Get-WmiObject -Class Win32_Processor | Select-Object -First 1
        
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
        $disks = Get-WmiObject -Class Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 }
        $diskInfo = @()
        
        foreach ($disk in $disks) {
            $size = $disk.Size
            $free = $disk.FreeSpace
            $used = $size - $free
            $usagePercent = if ($size -gt 0) { [math]::Round(($used / $size) * 100, 2) } else { 0 }
            
            $diskInfo += @{
                Drive = $disk.DeviceID
                Label = $disk.VolumeName
                Total = Format-Bytes -Bytes $size
                Used = Format-Bytes -Bytes $used
                Free = Format-Bytes -Bytes $free
                UsagePercent = $usagePercent
                Status = Get-StatusIcon -Value $usagePercent -Threshold 85
            }
        }
        return $diskInfo
    } catch {
        return @()
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
        $os = Get-WmiObject -Class Win32_OperatingSystem
        $uptime = (Get-Date) - $os.ConvertToDateTime($os.LastBootUpTime)
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
    foreach ($disk in $disks) {
        Write-Host "  Drive $($disk.Drive) [$($disk.Label)]" -ForegroundColor White
        Write-Host "    Total: $($disk.Total) | Used: $($disk.Used) | Free: $($disk.Free)" -ForegroundColor Gray
        Write-Host "    Usage: $($disk.Status) $($disk.UsagePercent)%" -ForegroundColor White
    }
    Write-Host ""
    
    # Network Status
    Write-Host "[Network Status]" -ForegroundColor Yellow
    $networks = Get-NetworkStatus
    if ($networks.Count -eq 0) {
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
}

# Execute main function
Show-SystemStatus
