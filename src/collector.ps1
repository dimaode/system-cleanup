<#
.SYNOPSIS
    ClawSysAdmin - Data Collector Module
.DESCRIPTION
    Collect system metrics and user behavior data for learning
.AUTHOR
    NightClaw Digital
.VERSION
    0.2.0
#>

# Set encoding
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Configuration
$DataDir = "$env:USERPROFILE/.openclaw/workspace/skills/system-cleanup/data"
$DbPath = "$DataDir/clawsysadmin.db"
$JsonDbPath = "$DataDir/clawsysadmin.json"
$IsJsonMode = $false

# Check storage mode
function Test-StorageMode {
    if (Test-Path $DbPath) {
        $script:IsJsonMode = $false
        return "sqlite"
    } elseif (Test-Path $JsonDbPath) {
        $script:IsJsonMode = $true
        return "json"
    } else {
        Write-Host "Database not initialized. Run init-database.ps1 first." -ForegroundColor Red
        exit 1
    }
}

# Collect system metrics
function Collect-SystemMetrics {
    try {
        # CPU
        $cpu = Get-Counter "\Processor(_Total)\% Processor Time" -ErrorAction SilentlyContinue
        $cpuUsage = [math]::Round($cpu.CounterSamples[0].CookedValue, 2)
        $cpuInfo = Get-WmiObject -Class Win32_Processor | Select-Object -First 1
        
        # Memory
        $os = Get-CimInstance -ClassName Win32_OperatingSystem
        $memoryTotal = $os.TotalVisibleMemorySize * 1KB
        $memoryFree = $os.FreePhysicalMemory * 1KB
        $memoryUsed = $memoryTotal - $memoryFree
        $memoryUsagePercent = [math]::Round(($memoryUsed / $memoryTotal) * 100, 2)
        
        # Disk
        $disks = Get-WmiObject -Class Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 }
        $diskTotal = 0
        $diskUsed = 0
        foreach ($disk in $disks) {
            $diskTotal += $disk.Size
            $diskUsed += ($disk.Size - $disk.FreeSpace)
        }
        $diskUsagePercent = if ($diskTotal -gt 0) { [math]::Round(($diskUsed / $diskTotal) * 100, 2) } else { 0 }
        
        # Network
        $netStats = Get-NetAdapterStatistics -ErrorAction SilentlyContinue | 
                    Measure-Object -Property ReceivedBytes, SentBytes -Sum
        $netRx = $netStats[0].Sum
        $netTx = $netStats[1].Sum
        
        # Uptime - Get from WMI instead of CIM to avoid date conversion issues
        try {
            $osWmi = Get-WmiObject -Class Win32_OperatingSystem
            $lastBoot = $osWmi.ConvertToDateTime($osWmi.LastBootUpTime)
            $uptime = (Get-Date) - $lastBoot
            $uptimeSeconds = [int]$uptime.TotalSeconds
        } catch {
            $uptimeSeconds = 0
        }
        
        return @{
            Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            CpuUsage = $cpuUsage
            CpuCores = $cpuInfo.NumberOfCores
            MemoryTotalBytes = $memoryTotal
            MemoryUsedBytes = $memoryUsed
            MemoryUsagePercent = $memoryUsagePercent
            DiskTotalBytes = $diskTotal
            DiskUsedBytes = $diskUsed
            DiskUsagePercent = $diskUsagePercent
            NetworkRxBytes = $netRx
            NetworkTxBytes = $netTx
            UptimeSeconds = $uptimeSeconds
        }
    } catch {
        Write-Host "Error collecting system metrics: $($_.Exception.Message)" -ForegroundColor Red
        return $null
    }
}

# Collect disk details
function Collect-DiskMetrics {
    try {
        $disks = Get-WmiObject -Class Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 }
        $diskMetrics = @()
        
        foreach ($disk in $disks) {
            $size = $disk.Size
            $free = $disk.FreeSpace
            $used = $size - $free
            $usagePercent = if ($size -gt 0) { [math]::Round(($used / $size) * 100, 2) } else { 0 }
            
            $diskMetrics += @{
                Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                DriveLetter = $disk.DeviceID
                TotalBytes = $size
                UsedBytes = $used
                FreeBytes = $free
                UsagePercent = $usagePercent
            }
        }
        
        return $diskMetrics
    } catch {
        return @()
    }
}

# Collect process information
function Collect-ProcessInfo {
    try {
        $processes = Get-Process | 
                     Where-Object { $_.WorkingSet64 -gt 100MB -or $_.CPU -gt 1 } |
                     Sort-Object -Property WorkingSet64 -Descending |
                     Select-Object -First 20
        
        $processData = @()
        foreach ($proc in $processes) {
            $runtime = if ($proc.StartTime) { 
                [int]((Get-Date) - $proc.StartTime).TotalSeconds 
            } else { 
                0 
            }
            
            $processData += @{
                Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
                ProcessName = $proc.ProcessName
                CpuPercent = [math]::Round($proc.CPU, 2)
                MemoryBytes = $proc.WorkingSet64
                RuntimeSeconds = $runtime
            }
        }
        
        return $processData
    } catch {
        return @()
    }
}

# Collect software usage (top processes by runtime)
function Collect-SoftwareUsage {
    try {
        $today = Get-Date -Format "yyyy-MM-dd"
        $processes = Get-Process | Group-Object -Property ProcessName
        
        $softwareData = @()
        foreach ($group in $processes) {
            $totalRuntime = 0
            foreach ($proc in $group.Group) {
                if ($proc.StartTime) {
                    $totalRuntime += [int]((Get-Date) - $proc.StartTime).TotalSeconds
                }
            }
            
            $softwareData += @{
                Date = $today
                SoftwareName = $group.Name
                ExecutablePath = ""
                LaunchCount = $group.Count
                TotalRuntimeSeconds = $totalRuntime
                LastUsed = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            }
        }
        
        return $softwareData
    } catch {
        return @()
    }
}

# Store metrics to JSON
function Store-MetricsToJSON {
    param($Metrics, $DiskMetrics, $ProcessData)
    
    try {
        $db = Get-Content $JsonDbPath -Raw | ConvertFrom-Json
        
        # Add system metrics
        $db.tables.system_metrics += $Metrics
        
        # Add disk metrics
        foreach ($disk in $DiskMetrics) {
            $db.tables.disk_metrics += $disk
        }
        
        # Add process data
        foreach ($proc in $ProcessData) {
            $db.tables.process_usage += $proc
        }
        
        # Save back
        $db | ConvertTo-Json -Depth 10 | Out-File -FilePath $JsonDbPath -Encoding UTF8
        
        return $true
    } catch {
        Write-Host "Error storing to JSON: $($_.Exception.Message)" -ForegroundColor Red
        return $false
    }
}

# Main collection function
function Start-DataCollection {
    param(
        [switch]$Silent,
        [switch]$OneTime
    )
    
    if (!$Silent) {
        Write-Host "`n============================================================" -ForegroundColor Cyan
        Write-Host "    ClawSysAdmin - Data Collector" -ForegroundColor Cyan
        Write-Host "============================================================" -ForegroundColor Cyan
        Write-Host ""
    }
    
    # Check storage mode
    $storageMode = Test-StorageMode
    if (!$Silent) {
        Write-Host "Storage mode: $storageMode" -ForegroundColor Gray
    }
    
    # Collect data
    if (!$Silent) { Write-Host "Collecting system metrics..." -ForegroundColor Gray }
    $metrics = Collect-SystemMetrics
    
    if (!$Silent) { Write-Host "Collecting disk metrics..." -ForegroundColor Gray }
    $diskMetrics = Collect-DiskMetrics
    
    if (!$Silent) { Write-Host "Collecting process information..." -ForegroundColor Gray }
    $processData = Collect-ProcessInfo
    
    # Store data
    if ($storageMode -eq "json") {
        $success = Store-MetricsToJSON -Metrics $metrics -DiskMetrics $diskMetrics -ProcessData $processData
    } else {
        # SQLite storage would go here
        Write-Host "SQLite storage not yet implemented, using JSON fallback" -ForegroundColor Yellow
        $success = Store-MetricsToJSON -Metrics $metrics -DiskMetrics $diskMetrics -ProcessData $processData
    }
    
    if ($success -and !$Silent) {
        Write-Host "Data collected successfully!" -ForegroundColor Green
        Write-Host "  CPU: $($metrics.CpuUsage)% | Memory: $($metrics.MemoryUsagePercent)% | Disk: $($metrics.DiskUsagePercent)%" -ForegroundColor White
        Write-Host "  Processes tracked: $($processData.Count)" -ForegroundColor White
    }
    
    if (!$OneTime -and !$Silent) {
        Write-Host "`nCollection complete. Data stored in: $DataDir" -ForegroundColor Gray
    }
}

# Execute
Start-DataCollection
