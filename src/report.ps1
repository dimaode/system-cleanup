<#
.SYNOPSIS
    ClawSysAdmin - 系统健康报告生成模块
.DESCRIPTION
    生成详细的系统健康报告，包括性能、存储、使用习惯分析
.AUTHOR
    夜爪数字公司
.VERSION
    0.1.0
#>

# 设置编码
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# 辅助函数：格式化字节
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

# 辅助函数：获取颜色状态
function Get-StatusText {
    param([int]$Value, [int]$Threshold = 80)
    if ($Value -ge $Threshold) { return "警告 🔴" }
    if ($Value -ge ($Threshold - 15)) { return "注意 🟡" }
    return "正常 🟢"
}

# ==================== 生成报告 ====================
function New-SystemReport {
    $reportTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $reportFile = "$env:USERPROFILE/.openclaw/workspace/skills/system-cleanup/reports/report_$(Get-Date -Format 'yyyyMMdd_HHmmss').md"
    
    # 确保报告目录存在
    $reportDir = Split-Path $reportFile -Parent
    if (!(Test-Path $reportDir)) {
        New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
    }
    
    # 收集系统信息
    $os = Get-CimInstance -ClassName Win32_OperatingSystem
    $cpu = Get-WmiObject -Class Win32_Processor | Select-Object -First 1
    $disks = Get-WmiObject -Class Win32_LogicalDisk | Where-Object { $_.DriveType -eq 3 }
    
    # 内存信息
    $memoryTotal = $os.TotalVisibleMemorySize * 1KB
    $memoryFree = $os.FreePhysicalMemory * 1KB
    $memoryUsed = $memoryTotal - $memoryFree
    $memoryUsage = [math]::Round(($memoryUsed / $memoryTotal) * 100, 2)
    
    # 计算磁盘总览
    $totalSize = 0
    $totalFree = 0
    foreach ($disk in $disks) {
        $totalSize += $disk.Size
        $totalFree += $disk.FreeSpace
    }
    $totalUsed = $totalSize - $totalFree
    $totalUsage = if ($totalSize -gt 0) { [math]::Round(($totalUsed / $totalSize) * 100, 2) } else { 0 }
    
    # 系统运行时间
    $uptime = (Get-Date) - $os.ConvertToDateTime($os.LastBootUpTime)
    $uptimeText = "{0}天 {1}小时 {2}分钟" -f $uptime.Days, $uptime.Hours, $uptime.Minutes
    
    # 生成 Markdown 报告
    $report = @"
# 🐾 ClawSysAdmin - 系统健康报告

**生成时间:** $reportTime  
**系统名称:** $($os.CSName)  
**运行时间:** $uptimeText

---

## 📊 系统概览

| 项目 | 状态 |
|------|------|
| 操作系统 | $($os.Caption) $($os.OSArchitecture) |
| 处理器 | $($cpu.Name) |
| 内存 | $(Format-Bytes -Bytes $memoryTotal) ($(Get-StatusText -Value $memoryUsage -Threshold 85)) |
| 磁盘 | $(Format-Bytes -Bytes $totalSize) ($(Get-StatusText -Value $totalUsage -Threshold 85)) |

---

## 💾 内存详情

| 项目 | 数值 | 占比 |
|------|------|------|
| 总内存 | $(Format-Bytes -Bytes $memoryTotal) | 100% |
| 已用内存 | $(Format-Bytes -Bytes $memoryUsed) | $memoryUsage% |
| 可用内存 | $(Format-Bytes -Bytes $memoryFree) | $([math]::Round(100 - $memoryUsage, 2))% |

**状态:** $(Get-StatusText -Value $memoryUsage -Threshold 85)

---

## 💽 磁盘详情

"@

    foreach ($disk in $disks) {
        $diskSize = $disk.Size
        $diskFree = $disk.FreeSpace
        $diskUsed = $diskSize - $diskFree
        $diskUsage = if ($diskSize -gt 0) { [math]::Round(($diskUsed / $diskSize) * 100, 2) } else { 0 }
        $diskLabel = if ($disk.VolumeName) { $disk.VolumeName } else { "未命名" }
        
        $report += @"

### 驱动器 $($disk.DeviceID) [$diskLabel]

| 项目 | 数值 | 占比 |
|------|------|------|
| 总容量 | $(Format-Bytes -Bytes $diskSize) | 100% |
| 已用空间 | $(Format-Bytes -Bytes $diskUsed) | $diskUsage% |
| 可用空间 | $(Format-Bytes -Bytes $diskFree) | $([math]::Round(100 - $diskUsage, 2))% |

**状态:** $(Get-StatusText -Value $diskUsage -Threshold 85)

"@
    }
    
    $report += @"

---

## 🧹 清理建议

基于当前系统状态，ClawSysAdmin 提供以下建议：

"@

    # 根据磁盘使用情况给出建议
    if ($totalUsage -gt 85) {
        $report += @"
### 🔴 磁盘空间警告

您的磁盘使用率已超过 85%，建议立即清理：

1. 运行 ``openclaw run system-cleanup clean`` 清理临时文件
2. 检查大文件: ``openclaw run system-cleanup large-files``
3. 卸载不常用的软件
4. 考虑使用外部存储或云存储迁移文件

"@
    } elseif ($totalUsage -gt 70) {
        $report += @"
### 🟡 磁盘空间注意

您的磁盘使用率已超过 70%，建议定期清理：

1. 每周运行一次系统清理
2. 检查下载文件夹
3. 清理浏览器缓存

"@
    } else {
        $report += @"
### 🟢 磁盘空间正常

您的磁盘空间充足，保持良好习惯即可：

1. 每月运行一次系统清理
2. 定期备份重要文件

"@
    }
    
    # 根据内存使用情况给出建议
    if ($memoryUsage -gt 85) {
        $report += @"
### 🔴 内存使用警告

您的内存使用率已超过 85%，可能导致系统变慢：

1. 关闭不必要的程序
2. 检查启动项: ``openclaw run system-cleanup startup``
3. 考虑增加物理内存

"@
    }
    
    $report += @"

---

## 📈 下一步行动

1. **查看详细状态:** ``openclaw run system-cleanup status``
2. **执行系统清理:** ``openclaw run system-cleanup clean``
3. **扫描大文件:** ``openclaw run system-cleanup large-files``

---

*本报告由 ClawSysAdmin 生成*  
*夜爪数字公司出品 🐾*
"@

    # 保存报告
    $report | Out-File -FilePath $reportFile -Encoding UTF8
    
    # 输出到控制台
    Write-Host "
╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║           🐾 ClawSysAdmin - 系统健康报告                    ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "报告已生成: $reportFile" -ForegroundColor Green
    Write-Host ""
    
    # 显示报告摘要
    Write-Host "【系统概览】" -ForegroundColor Yellow
    Write-Host "  操作系统: $($os.Caption) $($os.OSArchitecture)" -ForegroundColor White
    Write-Host "  处理器: $($cpu.Name)" -ForegroundColor White
    Write-Host "  内存: $(Format-Bytes -Bytes $memoryTotal) ($(Get-StatusText -Value $memoryUsage -Threshold 85))" -ForegroundColor White
    Write-Host "  磁盘: $(Format-Bytes -Bytes $totalSize) ($(Get-StatusText -Value $totalUsage -Threshold 85))" -ForegroundColor White
    Write-Host "  运行时间: $uptimeText" -ForegroundColor White
    Write-Host ""
    
    # 显示磁盘详情
    Write-Host "【磁盘详情】" -ForegroundColor Yellow
    foreach ($disk in $disks) {
        $diskSize = $disk.Size
        $diskFree = $disk.FreeSpace
        $diskUsed = $diskSize - $diskFree
        $diskUsage = if ($diskSize -gt 0) { [math]::Round(($diskUsed / $diskSize) * 100, 2) } else { 0 }
        $diskLabel = if ($disk.VolumeName) { $disk.VolumeName } else { "未命名" }
        Write-Host "  $($disk.DeviceID) [$diskLabel]: $(Get-StatusText -Value $diskUsage -Threshold 85) ($diskUsage%)" -ForegroundColor White
    }
    Write-Host ""
    
    Write-Host "使用 ``openclaw run system-cleanup clean`` 执行清理" -ForegroundColor Gray
    Write-Host ""
}

# 执行主函数
New-SystemReport
