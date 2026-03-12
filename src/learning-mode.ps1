<#
.SYNOPSIS
    ClawSysAdmin - Learning Mode Controller
.DESCRIPTION
    Control the 7-day silent learning period and user profiling
.AUTHOR
    NightClaw Digital
.VERSION
    0.2.0
#>

param(
    [switch]$Status,
    [switch]$Profile
)

# Set encoding
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# Configuration
$DataDir = "$env:USERPROFILE/.openclaw/workspace/skills/system-cleanup/data"
$DbPath = "$DataDir/clawsysadmin.db"
$JsonDbPath = "$DataDir/clawsysadmin.json"
$ConfigPath = "$DataDir/learning-config.json"

# Initialize or load config
function Get-LearningConfig {
    if (Test-Path $ConfigPath) {
        return Get-Content $ConfigPath -Raw | ConvertFrom-Json
    } else {
        $config = @{
            learning_start_date = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            learning_days = 7
            is_learning_complete = $false
            user_profile_generated = $false
            last_collection = $null
            collection_count = 0
        }
        Save-LearningConfig -Config $config
        return $config
    }
}

# Save config
function Save-LearningConfig {
    param($Config)
    $Config | ConvertTo-Json -Depth 5 | Out-File -FilePath $ConfigPath -Encoding UTF8
}

# Calculate learning progress
function Get-LearningProgress {
    param($Config)
    
    try {
        $startDate = [DateTime]::Parse($Config.learning_start_date)
    } catch {
        $startDate = Get-Date
    }
    
    $endDate = $startDate.AddDays($Config.learning_days)
    $now = Get-Date
    
    $totalDuration = $endDate - $startDate
    $elapsed = $now - $startDate
    $progress = [math]::Min(100, [math]::Round(($elapsed.TotalSeconds / $totalDuration.TotalSeconds) * 100, 2))
    $daysRemaining = [math]::Max(0, ($endDate - $now).Days)
    
    return @{
        StartDate = $startDate
        EndDate = $endDate
        Progress = $progress
        DaysRemaining = $daysRemaining
        IsComplete = $now -ge $endDate
    }
}

# Get learning statistics
function Get-LearningStats {
    try {
        if (Test-Path $JsonDbPath) {
            $db = Get-Content $JsonDbPath -Raw | ConvertFrom-Json
            
            $metrics = $db.tables.system_metrics
            $processes = $db.tables.process_usage
            $software = $db.tables.software_usage
            
            # Calculate stats
            $collectionCount = $metrics.Count
            $avgCpu = if ($metrics.Count -gt 0) { 
                [math]::Round(($metrics | Measure-Object -Property CpuUsage -Average).Average, 2) 
            } else { 0 }
            
            $avgMemory = if ($metrics.Count -gt 0) { 
                [math]::Round(($metrics | Measure-Object -Property MemoryUsagePercent -Average).Average, 2) 
            } else { 0 }
            
            $uniqueProcesses = ($processes | Select-Object -Property ProcessName -Unique).Count
            
            return @{
                CollectionCount = $collectionCount
                AvgCpu = $avgCpu
                AvgMemory = $avgMemory
                UniqueProcesses = $uniqueProcesses
                DataPoints = @{
                    SystemMetrics = $metrics.Count
                    ProcessRecords = $processes.Count
                    SoftwareRecords = $software.Count
                }
            }
        }
        return $null
    } catch {
        return $null
    }
}

# Display learning status
function Show-LearningStatus {
    Write-Host "`n============================================================" -ForegroundColor Cyan
    Write-Host "    ClawSysAdmin - Learning Mode" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
    
    $config = Get-LearningConfig
    $progress = Get-LearningProgress -Config $config
    $stats = Get-LearningStats
    
    # Learning period info
    Write-Host "[Learning Period]" -ForegroundColor Yellow
    Write-Host "  Started: $($progress.StartDate.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor White
    Write-Host "  Ends: $($progress.EndDate.ToString('yyyy-MM-dd HH:mm:ss'))" -ForegroundColor White
    Write-Host "  Duration: $($config.learning_days) days" -ForegroundColor White
    Write-Host ""
    
    # Progress bar
    $progressBarLength = 40
    $filledLength = [math]::Round(($progress.Progress / 100) * $progressBarLength)
    $emptyLength = $progressBarLength - $filledLength
    $filledBar = "=" * $filledLength
    $emptyBar = "-" * $emptyLength
    
    Write-Host "[Progress] $($progress.Progress)%" -ForegroundColor Yellow
    Write-Host "  [$filledBar$emptyBar]" -ForegroundColor Cyan
    Write-Host "  Days remaining: $($progress.DaysRemaining)" -ForegroundColor White
    Write-Host ""
    
    # Learning stats
    if ($stats) {
        Write-Host "[Collected Data]" -ForegroundColor Yellow
        Write-Host "  Total collections: $($stats.CollectionCount)" -ForegroundColor White
        Write-Host "  Avg CPU usage: $($stats.AvgCpu)%" -ForegroundColor White
        Write-Host "  Avg Memory usage: $($stats.AvgMemory)%" -ForegroundColor White
        Write-Host "  Unique processes tracked: $($stats.UniqueProcesses)" -ForegroundColor White
        Write-Host ""
    }
    
    # Mode status
    if ($progress.IsComplete) {
        Write-Host "[Status] Learning Complete!" -ForegroundColor Green
        Write-Host "  Ready to generate user profile." -ForegroundColor White
        Write-Host "  Run: openclaw run system-cleanup profile" -ForegroundColor Gray
    } else {
        Write-Host "[Status] Silent Learning Active" -ForegroundColor Yellow
        Write-Host "  Currently observing system behavior..." -ForegroundColor White
        Write-Host "  No automated actions will be taken during learning." -ForegroundColor Gray
    }
    Write-Host ""
    
    # Learning principles
    Write-Host "[Learning Principles]" -ForegroundColor Gray
    Write-Host "  - Only collecting data, no system modifications" -ForegroundColor Gray
    Write-Host "  - All data stored locally, never uploaded" -ForegroundColor Gray
    Write-Host "  - Building baseline for personalized recommendations" -ForegroundColor Gray
    Write-Host ""
}

# Generate user profile report
function New-UserProfile {
    $config = Get-LearningConfig
    $progress = Get-LearningProgress -Config $config
    
    if (!$progress.IsComplete) {
        Write-Host "Learning period not complete yet!" -ForegroundColor Yellow
        Write-Host "Days remaining: $($progress.DaysRemaining)" -ForegroundColor White
        return
    }
    
    if (!(Test-Path $JsonDbPath)) {
        Write-Host "No data available to generate profile." -ForegroundColor Red
        return
    }
    
    $db = Get-Content $JsonDbPath -Raw | ConvertFrom-Json
    $metrics = $db.tables.system_metrics
    $processes = $db.tables.process_usage
    
    # Generate report
    $reportPath = "$DataDir/user-profile-$(Get-Date -Format 'yyyyMMdd').md"
    
    $avgCpu = [math]::Round(($metrics | Measure-Object -Property CpuUsage -Average).Average, 2)
    $maxCpu = [math]::Round(($metrics | Measure-Object -Property CpuUsage -Maximum).Maximum, 2)
    $avgMemory = [math]::Round(($metrics | Measure-Object -Property MemoryUsagePercent -Average).Average, 2)
    $maxMemory = [math]::Round(($metrics | Measure-Object -Property MemoryUsagePercent -Maximum).Maximum, 2)
    $minMemory = [math]::Round(($metrics | Measure-Object -Property MemoryUsagePercent -Minimum).Minimum, 2)
    $currentDisk = if ($metrics.Count -gt 0) { [math]::Round($metrics[-1].DiskUsagePercent, 2) } else { 0 }
    
    $topProcesses = $processes | Group-Object -Property ProcessName | Sort-Object -Property Count -Descending | Select-Object -First 10 | ForEach-Object { "- $($_.Name): $($_.Count) occurrences" }
    $processList = if ($topProcesses) { $topProcesses -join "`n" } else { "No process data available" }
    
    $report = @"
# ClawSysAdmin - User System Profile

**Generated:** $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')  
**Learning Period:** $($progress.StartDate.ToString('yyyy-MM-dd')) to $($progress.EndDate.ToString('yyyy-MM-dd'))  
**Data Points:** $($metrics.Count) collections

---

## System Performance Baseline

### CPU Usage
- Average: $avgCpu%
- Peak: $maxCpu%
- Typical Range: Normal

### Memory Usage
- Average: $avgMemory%
- Peak: $maxMemory%
- Typical Range: $minMemory% - $maxMemory%

### Disk Usage
- Current: $currentDisk%
- Trend: Stable

---

## Usage Patterns

### Most Active Software
$processList

---

## Recommendations

Based on your usage patterns, ClawSysAdmin suggests:

1. **Regular Cleanup:** Run system cleanup weekly to maintain performance
2. **Monitor Peak Hours:** CPU usage peaks detected, consider closing unused applications
3. **Disk Space:** Monitor disk usage trend, clean temporary files regularly

---

*Generated by ClawSysAdmin v0.2.0*  
*NightClaw Digital*
"@

    $report | Out-File -FilePath $reportPath -Encoding UTF8
    
    Write-Host "User profile generated: $reportPath" -ForegroundColor Green
    
    # Update config
    $config.user_profile_generated = $true
    Save-LearningConfig -Config $config
}

# Main execution
if ($Profile) {
    New-UserProfile
} else {
    Show-LearningStatus
}
