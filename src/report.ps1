<#
.SYNOPSIS
    ClawSysAdmin - 系统健康报告生成模块
.DESCRIPTION
    生成详细的系统健康报告，包括性能、存储、使用习惯分析
.AUTHOR
    夜爪数字公司
.VERSION
    0.3.0
#>

# Set per-script log name before loading common
$script:CSA_LogDir  = "$env:USERPROFILE/.openclaw/workspace/skills/system-cleanup/logs"
$script:CSA_LogFile = "$script:CSA_LogDir/report_$(Get-Date -Format 'yyyyMMdd_HHmmss').log"

. "$PSScriptRoot/common.ps1"

# ==================== 健康分级（CSA-004 B）====================
# 返回 @{ Grade="🟢|🟡🔴"; Label="正常|注意|警告"; Color="Green|Yellow|Red" }
function Get-HealthGrade {
    param([double]$Value, [double]$WarnThreshold = 70, [double]$CritThreshold = 85)
    if ($Value -ge $CritThreshold) {
        return @{ Grade = "🔴"; Label = "警告"; Color = "Red" }
    } elseif ($Value -ge $WarnThreshold) {
        return @{ Grade = "🟡"; Label = "注意"; Color = "Yellow" }
    } else {
        return @{ Grade = "🟢"; Label = "正常"; Color = "Green" }
    }
}

# ==================== 生成报告 ====================
function New-SystemReport {
    $reportTime = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $reportFile = "$env:USERPROFILE/.openclaw/workspace/skills/system-cleanup/reports/report_$(Get-Date -Format 'yyyyMMdd_HHmmss').md"

    try {
        $stopwatch = [System.Diagnostics.Stopwatch]::StartNew()
        # 确保报告目录存在
        $reportDir = Split-Path $reportFile -Parent
        try {
            if (!(Test-Path $reportDir)) {
                New-Item -ItemType Directory -Path $reportDir -Force | Out-Null
            }
        } catch {
            Write-Host "警告: 无法创建报告目录: $($_.Exception.Message)" -ForegroundColor Yellow
            $reportFile = $null
        }

        # 收集系统信息（各项单独 try-catch，互不影响）
        $os = $null
        try {
            $os = Get-CimInstance -ClassName Win32_OperatingSystem -ErrorAction Stop
        } catch {
            Write-Host "警告: 无法获取操作系统信息: $($_.Exception.Message)" -ForegroundColor Yellow
            $os = [PSCustomObject]@{
                CSName = "未知"; Caption = "未知"; OSArchitecture = ""
                LastBootUpTime = (Get-Date); TotalVisibleMemorySize = 0; FreePhysicalMemory = 0
            }
        }

        $cpu = $null
        try {
            $cpu = Get-CimInstance -ClassName Win32_Processor -ErrorAction Stop | Select-Object -First 1
        } catch {
            Write-Host "警告: 无法获取处理器信息: $($_.Exception.Message)" -ForegroundColor Yellow
            $cpu = [PSCustomObject]@{ Name = "未知" }
        }

        $disks = @()
        try {
            $result = Get-CimInstance -ClassName Win32_LogicalDisk -ErrorAction Stop | Where-Object { $_.DriveType -eq 3 }
            if ($null -ne $result) { $disks = @($result) }
        } catch {
            Write-Host "警告: 无法获取磁盘信息: $($_.Exception.Message)" -ForegroundColor Yellow
        }

        # 内存信息
        $memoryTotal = $os.TotalVisibleMemorySize * 1KB
        $memoryFree = $os.FreePhysicalMemory * 1KB
        $memoryUsed = $memoryTotal - $memoryFree
        $memoryUsage = if ($memoryTotal -gt 0) { [math]::Round(($memoryUsed / $memoryTotal) * 100, 2) } else { 0 }

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
        $uptimeText = "未知"
        try {
            $uptime = (Get-Date) - $os.LastBootUpTime
            $uptimeText = "{0}天 {1}小时 {2}分钟" -f $uptime.Days, $uptime.Hours, $uptime.Minutes
        } catch {}

        # 健康分级（CSA-004 B）
        $memGrade  = Get-HealthGrade -Value $memoryUsage
        $diskGrade = Get-HealthGrade -Value $totalUsage

        # 整体健康等级：取最差的一个
        $overallGrade = if ($memGrade.Label -eq "警告" -or $diskGrade.Label -eq "警告") {
            @{ Grade = "🔴"; Label = "警告"; Color = "Red" }
        } elseif ($memGrade.Label -eq "注意" -or $diskGrade.Label -eq "注意") {
            @{ Grade = "🟡"; Label = "注意"; Color = "Yellow" }
        } else {
            @{ Grade = "🟢"; Label = "正常"; Color = "Green" }
        }

        # 生成 Markdown 报告（使用 StringBuilder 替代 here-string，避免缩进问题）
        $sb = New-Object System.Text.StringBuilder

        $null = $sb.AppendLine("# ClawSysAdmin - 系统健康报告")
        $null = $sb.AppendLine("")
        $null = $sb.AppendLine("**生成时间:** $reportTime")
        $null = $sb.AppendLine("**系统名称:** $($os.CSName)")
        $null = $sb.AppendLine("**运行时间:** $uptimeText")
        $null = $sb.AppendLine("**整体健康:** $($overallGrade.Grade) $($overallGrade.Label)")
        $null = $sb.AppendLine("")
        $null = $sb.AppendLine("---")
        $null = $sb.AppendLine("")
        $null = $sb.AppendLine("## 系统概览")
        $null = $sb.AppendLine("")
        $null = $sb.AppendLine("| 项目 | 状态 | 分级 |")
        $null = $sb.AppendLine("|------|------|------|")
        $null = $sb.AppendLine("| 操作系统 | $($os.Caption) $($os.OSArchitecture) | — |")
        $null = $sb.AppendLine("| 处理器 | $($cpu.Name) | — |")
        $null = $sb.AppendLine("| 内存 | $(Format-Bytes -Bytes $memoryTotal) · 已用 $memoryUsage% | $($memGrade.Grade) $($memGrade.Label) |")
        $null = $sb.AppendLine("| 磁盘 | $(Format-Bytes -Bytes $totalSize) · 已用 $totalUsage% | $($diskGrade.Grade) $($diskGrade.Label) |")
        $null = $sb.AppendLine("")
        $null = $sb.AppendLine("---")
        $null = $sb.AppendLine("")
        $null = $sb.AppendLine("## 内存详情")
        $null = $sb.AppendLine("")
        $null = $sb.AppendLine("| 项目 | 数值 | 占比 |")
        $null = $sb.AppendLine("|------|------|------|")
        $null = $sb.AppendLine("| 总内存 | $(Format-Bytes -Bytes $memoryTotal) | 100% |")
        $null = $sb.AppendLine("| 已用内存 | $(Format-Bytes -Bytes $memoryUsed) | $memoryUsage% |")
        $null = $sb.AppendLine("| 可用内存 | $(Format-Bytes -Bytes $memoryFree) | $([math]::Round(100 - $memoryUsage, 2))% |")
        $null = $sb.AppendLine("")
        $null = $sb.AppendLine("**状态:** $(Get-StatusText -Value $memoryUsage -Threshold 85)")
        $null = $sb.AppendLine("")
        $null = $sb.AppendLine("---")
        $null = $sb.AppendLine("")
        $null = $sb.AppendLine("## 磁盘详情")
        $null = $sb.AppendLine("")

        foreach ($disk in $disks) {
            $diskSize = $disk.Size
            $diskFree = $disk.FreeSpace
            $diskUsed = $diskSize - $diskFree
            $diskUsage = if ($diskSize -gt 0) { [math]::Round(($diskUsed / $diskSize) * 100, 2) } else { 0 }
            $diskLabel = if ($disk.VolumeName) { $disk.VolumeName } else { "未命名" }

            $null = $sb.AppendLine("### 驱动器 $($disk.DeviceID) [$diskLabel]")
            $null = $sb.AppendLine("")
            $null = $sb.AppendLine("| 项目 | 数值 | 占比 |")
            $null = $sb.AppendLine("|------|------|------|")
            $null = $sb.AppendLine("| 总容量 | $(Format-Bytes -Bytes $diskSize) | 100% |")
            $null = $sb.AppendLine("| 已用空间 | $(Format-Bytes -Bytes $diskUsed) | $diskUsage% |")
            $null = $sb.AppendLine("| 可用空间 | $(Format-Bytes -Bytes $diskFree) | $([math]::Round(100 - $diskUsage, 2))% |")
            $null = $sb.AppendLine("")
            $null = $sb.AppendLine("**状态:** $(Get-StatusText -Value $diskUsage -Threshold 85)")
            $null = $sb.AppendLine("")
        }

        $null = $sb.AppendLine("---")
        $null = $sb.AppendLine("")
        $null = $sb.AppendLine("## 清理建议")
        $null = $sb.AppendLine("")
        $null = $sb.AppendLine("基于当前系统状态，ClawSysAdmin 提供以下建议：")
        $null = $sb.AppendLine("")

        if ($totalUsage -gt 85) {
            $null = $sb.AppendLine("### 🔴 磁盘空间警告")
            $null = $sb.AppendLine("")
            $null = $sb.AppendLine("您的磁盘使用率已超过 85%，建议立即清理：")
            $null = $sb.AppendLine("")
            $null = $sb.AppendLine("1. 运行 'openclaw run system-cleanup clean' 清理临时文件")
            $null = $sb.AppendLine("2. 检查大文件: 'openclaw run system-cleanup large-files'")
            $null = $sb.AppendLine("3. 卸载不常用的软件")
            $null = $sb.AppendLine("4. 考虑使用外部存储或云存储迁移文件")
            $null = $sb.AppendLine("")
        } elseif ($totalUsage -gt 70) {
            $null = $sb.AppendLine("### 🟡 磁盘空间注意")
            $null = $sb.AppendLine("")
            $null = $sb.AppendLine("您的磁盘使用率已超过 70%，建议定期清理：")
            $null = $sb.AppendLine("")
            $null = $sb.AppendLine("1. 每周运行一次系统清理")
            $null = $sb.AppendLine("2. 检查下载文件夹")
            $null = $sb.AppendLine("3. 清理浏览器缓存")
            $null = $sb.AppendLine("")
        } else {
            $null = $sb.AppendLine("### 🟢 磁盘空间正常")
            $null = $sb.AppendLine("")
            $null = $sb.AppendLine("您的磁盘空间充足，保持良好习惯即可：")
            $null = $sb.AppendLine("")
            $null = $sb.AppendLine("1. 每月运行一次系统清理")
            $null = $sb.AppendLine("2. 定期备份重要文件")
            $null = $sb.AppendLine("")
        }

        if ($memoryUsage -gt 85) {
            $null = $sb.AppendLine("### 🔴 内存使用警告")
            $null = $sb.AppendLine("")
            $null = $sb.AppendLine("您的内存使用率已超过 85%，可能导致系统变慢：")
            $null = $sb.AppendLine("")
            $null = $sb.AppendLine("1. 关闭不必要的程序")
            $null = $sb.AppendLine("2. 检查启动项: 'openclaw run system-cleanup startup'")
            $null = $sb.AppendLine("3. 考虑增加物理内存")
            $null = $sb.AppendLine("")
        } elseif ($memoryUsage -gt 70) {
            $null = $sb.AppendLine("### 🟡 内存使用注意")
            $null = $sb.AppendLine("")
            $null = $sb.AppendLine("您的内存使用率超过 70%，建议关注：")
            $null = $sb.AppendLine("")
            $null = $sb.AppendLine("1. 检查是否有内存泄漏的程序")
            $null = $sb.AppendLine("2. 关闭长时间未使用的后台程序")
            $null = $sb.AppendLine("")
        }

        $stopwatch.Stop()
        $elapsed = $stopwatch.Elapsed

        $null = $sb.AppendLine("---")
        $null = $sb.AppendLine("")
        $null = $sb.AppendLine("## 下一步行动")
        $null = $sb.AppendLine("")
        $null = $sb.AppendLine("1. **查看详细状态:** 'openclaw run system-cleanup status'")
        $null = $sb.AppendLine("2. **执行系统清理:** 'openclaw run system-cleanup clean'")
        $null = $sb.AppendLine("3. **扫描大文件:** 'openclaw run system-cleanup large-files'")
        $null = $sb.AppendLine("")
        $null = $sb.AppendLine("---")
        $null = $sb.AppendLine("")
        $null = $sb.AppendLine("*报告生成耗时: $($elapsed.TotalSeconds.ToString('F2'))s*")
        $null = $sb.AppendLine("*本报告由 ClawSysAdmin 生成*")
        $null = $sb.AppendLine("*夜爪数字公司出品*")

        $report = $sb.ToString()

        # 保存报告
        if ($reportFile) {
            try {
                $report | Out-File -FilePath $reportFile -Encoding UTF8 -ErrorAction Stop
            } catch {
                Write-Host "警告: 无法保存报告文件: $($_.Exception.Message)" -ForegroundColor Yellow
                $reportFile = $null
            }
        }

        # ============================================================
        # D: 彩色摘要 Banner
        # ============================================================
        Write-Host ""
        Write-Host "╔══════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
        Write-Host "║          ClawSysAdmin · 系统健康报告                    ║" -ForegroundColor Cyan
        Write-Host "╠══════════════════════════════════════════════════════════╣" -ForegroundColor Cyan

        $bannerLine = "║  整体健康：$($overallGrade.Grade) $($overallGrade.Label)".PadRight(61) + "║"
        Write-Host $bannerLine -ForegroundColor $overallGrade.Color

        Write-Host "╠══════════════════════════════════════════════════════════╣" -ForegroundColor Cyan

        # 内存状态行
        $memLine = "║  内存     ：$($memGrade.Grade) $($memGrade.Label)  ($memoryUsage%)   已用 $(Format-Bytes -Bytes $memoryUsed) / $(Format-Bytes -Bytes $memoryTotal)".PadRight(61) + "║"
        Write-Host $memLine -ForegroundColor $memGrade.Color

        # 磁盘状态行
        $diskLine = "║  磁盘     ：$($diskGrade.Grade) $($diskGrade.Label)  ($totalUsage%)   已用 $(Format-Bytes -Bytes $totalUsed) / $(Format-Bytes -Bytes $totalSize)".PadRight(61) + "║"
        Write-Host $diskLine -ForegroundColor $diskGrade.Color

        # 各驱动器明细
        foreach ($disk in $disks) {
            $dSize  = $disk.Size
            $dFree  = $disk.FreeSpace
            $dUsed  = $dSize - $dFree
            $dPct   = if ($dSize -gt 0) { [math]::Round(($dUsed / $dSize) * 100, 1) } else { 0 }
            $dGrade = Get-HealthGrade -Value $dPct
            $dLabel = if ($disk.VolumeName) { $disk.VolumeName } else { "未命名" }
            $dLine  = "║    $($disk.DeviceID) [$dLabel]  $($dGrade.Grade) $dPct%  空闲 $(Format-Bytes -Bytes $dFree)".PadRight(61) + "║"
            Write-Host $dLine -ForegroundColor $dGrade.Color
        }

        Write-Host "╠══════════════════════════════════════════════════════════╣" -ForegroundColor Cyan
        $uptimeLine = "║  运行时间 ：$uptimeText".PadRight(61) + "║"
        Write-Host $uptimeLine -ForegroundColor White
        $timeLine = "║  报告耗时 ：$($elapsed.TotalSeconds.ToString('F2'))s   生成于 $reportTime".PadRight(61) + "║"
        Write-Host $timeLine -ForegroundColor Gray

        if ($reportFile) {
            $fileLine = "║  报告文件 ：已保存".PadRight(61) + "║"
            Write-Host $fileLine -ForegroundColor Green
        }

        Write-Host "╚══════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
        Write-Host ""

        if ($reportFile) {
            Write-Host "  $reportFile" -ForegroundColor DarkGray
            Write-Host ""
        }

        Write-Host "  运行 'openclaw run system-cleanup clean' 执行清理" -ForegroundColor Gray
        Write-Host ""

    } catch {
        Write-Host ""
        Write-Host "错误: 报告生成过程中遇到意外错误。" -ForegroundColor Red
        Write-Host "  $($_.Exception.Message)" -ForegroundColor Red
        Write-Host ""
        exit 1
    }
}

# 执行主函数
New-SystemReport
