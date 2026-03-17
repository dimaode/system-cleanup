<#
.SYNOPSIS
    ClawSysAdmin - 大文件扫描模块
.DESCRIPTION
    扫描系统磁盘，找出占用空间最大的文件
.AUTHOR
    夜爪数字公司
.VERSION
    0.1.1
#>

# Set per-script log name before loading common
$script:CSA_LogDir  = "$env:USERPROFILE/.openclaw/workspace/skills/system-cleanup/logs"
$script:CSA_LogFile = "$script:CSA_LogDir/large_files_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

. "$PSScriptRoot/common.ps1"

# ==================== 扫描大文件 ====================
function Find-LargeFiles {
    param(
        [string]$Path = "C:\",
        [int]$TopCount = 20,
        [long]$MinSize = 100MB
    )
    
    Write-Host "正在扫描 $Path 中的大文件（最小 $(Format-Bytes -Bytes $MinSize)）..." -ForegroundColor Yellow
    Write-Host "这可能需要几分钟时间，请耐心等待..." -ForegroundColor Gray
    Write-Host ""
    
    $excludedPaths = @(
        "C:\Windows\System32",
        "C:\Windows\SysWOW64",
        "C:\Program Files",
        "C:\Program Files (x86)",
        "C:\Windows\WinSxS"
    )
    
    try {
        # 获取所有文件
        $files = Get-ChildItem -Path $Path -Recurse -File -ErrorAction SilentlyContinue | 
                 Where-Object { 
                     $_.Length -ge $MinSize -and 
                     $excludedPaths -notcontains $_.DirectoryName -and
                     -not ($_.FullName -like "*\Windows\*") -and
                     -not ($_.FullName -like "*\Program Files*") -and
                     -not ($_.FullName -like "*\`$Recycle.Bin\*")
                 } |
                 Sort-Object -Property Length -Descending |
                 Select-Object -First $TopCount
        
        return $files
    } catch {
        Write-Host "扫描失败: $($_.Exception.Message)" -ForegroundColor Red
        return @()
    }
}

# ==================== 扫描大文件夹 ====================
function Find-LargeFolders {
    param(
        [string]$Path = "C:\Users\$env:USERNAME",
        [int]$TopCount = 10
    )
    
    Write-Host "正在扫描大文件夹..." -ForegroundColor Yellow
    
    try {
        $folders = Get-ChildItem -Path $Path -Directory -ErrorAction SilentlyContinue |
                   ForEach-Object {
                       $size = (Get-ChildItem -Path $_.FullName -Recurse -File -ErrorAction SilentlyContinue | 
                               Measure-Object -Property Length -Sum).Sum
                       [PSCustomObject]@{
                           Name = $_.Name
                           FullName = $_.FullName
                           Size = $size
                           SizeFormatted = Format-Bytes -Bytes $size
                       }
                   } |
                   Sort-Object -Property Size -Descending |
                   Select-Object -First $TopCount
        
        return $folders
    } catch {
        return @()
    }
}

# ==================== 扫描下载文件夹 ====================
function Scan-DownloadsFolder {
    $downloadsPath = "$env:USERPROFILE\Downloads"
    
    if (Test-Path $downloadsPath) {
        $files = Get-ChildItem -Path $downloadsPath -File -ErrorAction SilentlyContinue |
                 Sort-Object -Property Length -Descending
        
        $totalSize = ($files | Measure-Object -Property Length -Sum).Sum
        
        return @{
            Path = $downloadsPath
            FileCount = $files.Count
            TotalSize = $totalSize
            TotalSizeFormatted = Format-Bytes -Bytes $totalSize
            Files = $files | Select-Object -First 10
        }
    }
    return $null
}

# ==================== 扫描桌面 ====================
function Scan-Desktop {
    $desktopPath = "$env:USERPROFILE\Desktop"
    
    if (Test-Path $desktopPath) {
        $items = Get-ChildItem -Path $desktopPath -Recurse -File -ErrorAction SilentlyContinue
        $totalSize = ($items | Measure-Object -Property Length -Sum).Sum
        
        return @{
            Path = $desktopPath
            FileCount = $items.Count
            TotalSize = $totalSize
            TotalSizeFormatted = Format-Bytes -Bytes $totalSize
        }
    }
    return $null
}

# ==================== 主函数 ====================
function Show-LargeFilesReport {
    Write-Host "
╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║           🐾 ClawSysAdmin - 大文件扫描                      ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    
    # 1. 扫描大文件
    $largeFiles = Find-LargeFiles -Path "C:\Users\$env:USERNAME" -TopCount 20 -MinSize 100MB
    
    if ($largeFiles.Count -gt 0) {
        Write-Host "【C盘用户目录大文件 TOP 20】" -ForegroundColor Yellow
        Write-Host ""
        
        $counter = 1
        foreach ($file in $largeFiles) {
            $size = Format-Bytes -Bytes $file.Length
            $name = $file.Name
            if ($name.Length -gt 50) {
                $name = $name.Substring(0, 47) + "..."
            }
            
            Write-Host "  $counter. $name" -ForegroundColor White
            Write-Host "     大小: $size" -ForegroundColor Gray
            Write-Host "     路径: $($file.FullName)" -ForegroundColor Gray
            Write-Host ""
            
            $counter++
        }
    } else {
        Write-Host "未找到大于 100MB 的文件" -ForegroundColor Gray
    }
    
    Write-Host "────────────────────────────────────────" -ForegroundColor Gray
    
    # 2. 扫描用户文件夹
    $largeFolders = Find-LargeFolders -Path "C:\Users\$env:USERNAME" -TopCount 10
    
    if ($largeFolders.Count -gt 0) {
        Write-Host "【用户目录大文件夹 TOP 10】" -ForegroundColor Yellow
        Write-Host ""
        
        $counter = 1
        foreach ($folder in $largeFolders) {
            if ($folder.Size -gt 0) {
                Write-Host "  $counter. $($folder.Name)" -ForegroundColor White
                Write-Host "     大小: $($folder.SizeFormatted)" -ForegroundColor Gray
                Write-Host ""
                $counter++
            }
        }
    }
    
    Write-Host "────────────────────────────────────────" -ForegroundColor Gray
    
    # 3. 扫描下载文件夹
    $downloads = Scan-DownloadsFolder
    if ($downloads) {
        Write-Host "【下载文件夹】" -ForegroundColor Yellow
        Write-Host "  路径: $($downloads.Path)" -ForegroundColor White
        Write-Host "  文件数: $($downloads.FileCount)" -ForegroundColor White
        Write-Host "  总大小: $($downloads.TotalSizeFormatted)" -ForegroundColor White
        Write-Host ""
        
        if ($downloads.Files.Count -gt 0) {
            Write-Host "  最大文件:" -ForegroundColor Gray
            foreach ($file in ($downloads.Files | Select-Object -First 5)) {
                Write-Host "    - $($file.Name): $(Format-Bytes -Bytes $file.Length)" -ForegroundColor Gray
            }
        }
        Write-Host ""
    }
    
    Write-Host "────────────────────────────────────────" -ForegroundColor Gray
    
    # 4. 扫描桌面
    $desktop = Scan-Desktop
    if ($desktop) {
        Write-Host "【桌面】" -ForegroundColor Yellow
        Write-Host "  文件数: $($desktop.FileCount)" -ForegroundColor White
        Write-Host "  总大小: $($desktop.TotalSizeFormatted)" -ForegroundColor White
        Write-Host ""
    }
    
    Write-Host "────────────────────────────────────────" -ForegroundColor Gray
    Write-Host ""
    Write-Host "💡 建议操作:" -ForegroundColor Cyan
    Write-Host "  1. 定期清理下载文件夹中的旧文件" -ForegroundColor White
    Write-Host "  2. 将大文件移动到外部存储或云盘" -ForegroundColor White
    Write-Host "  3. 使用 `'openclaw run system-cleanup clean'` 清理临时文件" -ForegroundColor White
    Write-Host ""
}

# 执行主函数
Show-LargeFilesReport
