<#
.SYNOPSIS
    ClawSysAdmin - System Cleanup Module
.DESCRIPTION
    Execute system cleanup: temp files, recycle bin, browser cache, etc.
.AUTHOR
    NightClaw Digital
.VERSION
    0.2.0
#>

[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$LogDir = "$env:USERPROFILE/.openclaw/workspace/skills/system-cleanup/logs"
$LogFile = "$LogDir/cleanup_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

if (!(Test-Path $LogDir)) {
    New-Item -ItemType Directory -Path $LogDir -Force | Out-Null
}

function Write-Log {
    param([string]$Message, [string]$Level = "INFO")
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    Add-Content -Path $LogFile -Value $logEntry
    
    switch ($Level) {
        "ERROR" { Write-Host $Message -ForegroundColor Red }
        "WARN"  { Write-Host $Message -ForegroundColor Yellow }
        "INFO"  { Write-Host $Message -ForegroundColor White }
        "SUCCESS" { Write-Host $Message -ForegroundColor Green }
    }
}

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

function Clear-TempFiles {
    Write-Log "Cleaning temp files..." -Level "INFO"
    $totalSize = 0
    $fileCount = 0
    
    $tempPaths = @($env:TEMP, "$env:SystemRoot\Temp", "$env:LOCALAPPDATA\Temp", "$env:SystemRoot\Prefetch")
    
    foreach ($path in $tempPaths) {
        if (Test-Path $path) {
            try {
                $files = Get-ChildItem -Path $path -Recurse -Force -ErrorAction SilentlyContinue | 
                         Where-Object { !$_.PSIsContainer -and $_.CreationTime -lt (Get-Date).AddDays(-1) }
                
                foreach ($file in $files) {
                    try {
                        $size = $file.Length
                        Remove-Item -Path $file.FullName -Force -ErrorAction SilentlyContinue
                        $totalSize += $size
                        $fileCount++
                    } catch {}
                }
            } catch {}
        }
    }
    
    Write-Log "Temp files cleaned: $fileCount files, $(Format-Bytes -Bytes $totalSize) freed" -Level "SUCCESS"
    return @{ Count = $fileCount; Size = $totalSize }
}

function Clear-RecycleBinFiles {
    Write-Log "Cleaning recycle bin..." -Level "INFO"
    try {
        # Get recycle bin info before clearing
        $recycleBin = (New-Object -ComObject Shell.Application).Namespace(0xA)
        $items = @($recycleBin.Items())
        $itemCount = $items.Count
        
        if ($itemCount -eq 0) {
            Write-Log "Recycle bin is empty" -Level "INFO"
            return @{ Count = 0; Size = 0 }
        }
        
        # Estimate size (COM properties can be unreliable)
        $totalSize = 0
        try {
            $shell = New-Object -ComObject Shell.Application
            $folder = $shell.Namespace(0xA)
            $items = $folder.Items()
            foreach ($item in $items) {
                try {
                    # Try to get size from extended properties
                    $sizeProp = $item.ExtendedProperty("System.Size")
                    if ($sizeProp -and $sizeProp -match '^\d+$') {
                        $totalSize += [long]$sizeProp
                    }
                } catch {}
            }
        } catch {}
        
        # Clear recycle bin using PowerShell cmdlet
        Clear-RecycleBin -Force -ErrorAction SilentlyContinue
        
        Write-Log "Recycle bin cleaned: $itemCount items" -Level "SUCCESS"
        return @{ Count = $itemCount; Size = $totalSize }
    } catch {
        Write-Log "Failed to clean recycle bin: $($_.Exception.Message)" -Level "ERROR"
        return @{ Count = 0; Size = 0 }
    }
}

function Clear-WindowsUpdateCache {
    Write-Log "Cleaning Windows update cache..." -Level "INFO"
    $totalSize = 0
    $fileCount = 0
    $paths = @("$env:SystemRoot\SoftwareDistribution\Download", "$env:SystemRoot\SoftwareDistribution\DataStore\Logs")
    
    foreach ($path in $paths) {
        if (Test-Path $path) {
            try {
                $files = Get-ChildItem -Path $path -Recurse -Force -ErrorAction SilentlyContinue | Where-Object { !$_.PSIsContainer }
                foreach ($file in $files) {
                    try {
                        $size = $file.Length
                        Remove-Item -Path $file.FullName -Force -ErrorAction SilentlyContinue
                        $totalSize += $size
                        $fileCount++
                    } catch {}
                }
            } catch {}
        }
    }
    
    Write-Log "Windows update cache cleaned: $fileCount files, $(Format-Bytes -Bytes $totalSize) freed" -Level "SUCCESS"
    return @{ Count = $fileCount; Size = $totalSize }
}

function Clear-OldEventLogs {
    Write-Log "Cleaning old event logs..." -Level "INFO"
    try {
        $logs = Get-WinEvent -ListLog * -ErrorAction SilentlyContinue | Where-Object { $_.RecordCount -gt 0 }
        foreach ($log in $logs) {
            try {
                if ($log.LogMode -eq "Circular" -and $log.MaximumSizeInBytes -gt 100MB) {
                    $log.MaximumSizeInBytes = 100MB
                    $log.SaveChanges()
                }
            } catch {}
        }
        Write-Log "Event logs cleaned" -Level "SUCCESS"
        return @{ Count = $logs.Count; Size = 0 }
    } catch {
        Write-Log "Failed to clean event logs: $($_.Exception.Message)" -Level "WARN"
        return @{ Count = 0; Size = 0 }
    }
}

function Start-SystemCleanup {
    Write-Host "`n============================================================" -ForegroundColor Cyan
    Write-Host "    ClawSysAdmin - System Cleanup Tool" -ForegroundColor Cyan
    Write-Host "============================================================" -ForegroundColor Cyan
    Write-Host ""
    
    Write-Log "Starting system cleanup..." -Level "INFO"
    Write-Log "Log file: $LogFile" -Level "INFO"
    Write-Host ""
    
    $diskBefore = Get-WmiObject -Class Win32_LogicalDisk | Where-Object { $_.DeviceID -eq "C:" }
    $freeBefore = $diskBefore.FreeSpace
    
    $results = @()
    
    Write-Host "----------------------------------------" -ForegroundColor Gray
    $result = Clear-TempFiles
    $results += @{ Name = "Temp Files"; Result = $result }
    
    Write-Host "----------------------------------------" -ForegroundColor Gray
    $result = Clear-RecycleBinFiles
    $results += @{ Name = "Recycle Bin"; Result = $result }
    
    Write-Host "----------------------------------------" -ForegroundColor Gray
    $result = Clear-WindowsUpdateCache
    $results += @{ Name = "Windows Update Cache"; Result = $result }
    
    Write-Host "----------------------------------------" -ForegroundColor Gray
    $result = Clear-OldEventLogs
    $results += @{ Name = "Event Logs"; Result = $result }
    
    $diskAfter = Get-WmiObject -Class Win32_LogicalDisk | Where-Object { $_.DeviceID -eq "C:" }
    $freeAfter = $diskAfter.FreeSpace
    $actualFreed = $freeAfter - $freeBefore
    
    Write-Host ""
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host "    Cleanup Report" -ForegroundColor Green
    Write-Host "============================================================" -ForegroundColor Green
    Write-Host ""
    
    $totalFiles = 0
    $estimatedSize = 0
    foreach ($item in $results) {
        Write-Host "  $($item.Name):" -ForegroundColor Yellow
        Write-Host "    Files deleted: $($item.Result.Count)" -ForegroundColor White
        Write-Host "    Space freed: $(Format-Bytes -Bytes $item.Result.Size)" -ForegroundColor White
        $totalFiles += $item.Result.Count
        $estimatedSize += $item.Result.Size
    }
    
    Write-Host ""
    Write-Host "[Summary]" -ForegroundColor Cyan
    Write-Host "  Total files deleted: $totalFiles" -ForegroundColor White
    Write-Host "  Estimated space freed: $(Format-Bytes -Bytes $estimatedSize)" -ForegroundColor White
    Write-Host "  Actual space freed: $(Format-Bytes -Bytes $actualFreed)" -ForegroundColor White
    Write-Host "  C: Drive free space: $(Format-Bytes -Bytes $freeAfter)" -ForegroundColor White
    Write-Host ""
    
    Write-Log "System cleanup completed" -Level "SUCCESS"
    Write-Host "Detailed log: $LogFile" -ForegroundColor Gray
    Write-Host ""
}

Start-SystemCleanup
