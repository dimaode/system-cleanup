<#
.SYNOPSIS
    ClawSysAdmin - System Cleanup Module
.DESCRIPTION
    Execute system cleanup: temp files, recycle bin, browser cache, etc.
.AUTHOR
    NightClaw Digital
.VERSION
    0.3.0
#>

# Set per-script log name before loading common (common.ps1 will pick it up)
$script:CSA_LogDir  = "$env:USERPROFILE/.openclaw/workspace/skills/system-cleanup/logs"
$script:CSA_LogFile = "$script:CSA_LogDir/cleanup_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

. "$PSScriptRoot/common.ps1"

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

    try {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        Write-Log "Starting system cleanup..." -Level "INFO"
        Write-Log "Log file: $script:CSA_LogFile" -Level "INFO"
        Write-Host ""

        # Get disk space before cleanup (safe fallback to 0 if CIM unavailable)
        $freeBefore = 0
        try {
            $diskBefore = Get-CimInstance -ClassName Win32_LogicalDisk -ErrorAction Stop | Where-Object { $_.DeviceID -eq "C:" }
            $freeBefore = if ($diskBefore) { $diskBefore.FreeSpace } else { 0 }
        } catch {
            Write-Log "Could not read disk space before cleanup: $($_.Exception.Message)" -Level "WARN"
        }

        $results = [System.Collections.ArrayList]::new()

        Write-Host "----------------------------------------" -ForegroundColor Gray
        try {
            $result = Clear-TempFiles
            $null = $results.Add(@{ Name = "Temp Files"; Result = $result })
        } catch {
            Write-Log "Temp file cleanup failed: $($_.Exception.Message)" -Level "ERROR"
            $null = $results.Add(@{ Name = "Temp Files"; Result = @{ Count = 0; Size = 0 } })
        }

        Write-Host "----------------------------------------" -ForegroundColor Gray
        try {
            $result = Clear-RecycleBinFiles
            $null = $results.Add(@{ Name = "Recycle Bin"; Result = $result })
        } catch {
            Write-Log "Recycle bin cleanup failed: $($_.Exception.Message)" -Level "ERROR"
            $null = $results.Add(@{ Name = "Recycle Bin"; Result = @{ Count = 0; Size = 0 } })
        }

        Write-Host "----------------------------------------" -ForegroundColor Gray
        try {
            $result = Clear-WindowsUpdateCache
            $null = $results.Add(@{ Name = "Windows Update Cache"; Result = $result })
        } catch {
            Write-Log "Windows update cache cleanup failed: $($_.Exception.Message)" -Level "ERROR"
            $null = $results.Add(@{ Name = "Windows Update Cache"; Result = @{ Count = 0; Size = 0 } })
        }

        Write-Host "----------------------------------------" -ForegroundColor Gray
        try {
            $result = Clear-OldEventLogs
            $null = $results.Add(@{ Name = "Event Logs"; Result = $result })
        } catch {
            Write-Log "Event log cleanup failed: $($_.Exception.Message)" -Level "ERROR"
            $null = $results.Add(@{ Name = "Event Logs"; Result = @{ Count = 0; Size = 0 } })
        }

        # Get disk space after cleanup
        $freeAfter = 0
        $actualFreed = 0
        try {
            $diskAfter = Get-CimInstance -ClassName Win32_LogicalDisk -ErrorAction Stop | Where-Object { $_.DeviceID -eq "C:" }
            $freeAfter = if ($diskAfter) { $diskAfter.FreeSpace } else { 0 }
            $actualFreed = $freeAfter - $freeBefore
        } catch {
            Write-Log "Could not read disk space after cleanup: $($_.Exception.Message)" -Level "WARN"
        }

        $stopwatch.Stop()
        $elapsed = $stopwatch.Elapsed

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
        if ($actualFreed -ne 0) {
            Write-Host "  Actual space freed: $(Format-Bytes -Bytes $actualFreed)" -ForegroundColor White
        }
        if ($freeAfter -ne 0) {
            Write-Host "  C: Drive free space: $(Format-Bytes -Bytes $freeAfter)" -ForegroundColor White
        }
        Write-Host "  Time elapsed: $($elapsed.Minutes)m $($elapsed.Seconds)s $($elapsed.Milliseconds)ms" -ForegroundColor Gray
        Write-Host ""

        Write-Log "System cleanup completed in $($elapsed.TotalSeconds.ToString('F2'))s" -Level "SUCCESS"
        Write-Host "Detailed log: $script:CSA_LogFile" -ForegroundColor Gray
        Write-Host ""

    } catch {
        Write-Log "Unexpected error during system cleanup: $($_.Exception.Message)" -Level "ERROR"
        Write-Host ""
        Write-Host "ERROR: Cleanup encountered an unexpected error." -ForegroundColor Red
        Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
        Write-Host "  Check log for details: $script:CSA_LogFile" -ForegroundColor Gray
        Write-Host ""
        exit 1
    }
}

Start-SystemCleanup
