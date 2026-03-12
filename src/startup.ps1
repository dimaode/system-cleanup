<#
.SYNOPSIS
    ClawSysAdmin - 启动项管理模块
.DESCRIPTION
    查看和管理系统启动项
.AUTHOR
    夜爪数字公司
.VERSION
    0.1.0
#>

# 设置编码
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

# ==================== 获取启动项 ====================
function Get-StartupItems {
    $startupItems = @()
    
    # 1. 注册表启动项 - 当前用户
    try {
        $regPaths = @(
            "HKCU:\Software\Microsoft\Windows\CurrentVersion\Run",
            "HKCU:\Software\Microsoft\Windows\CurrentVersion\RunOnce"
        )
        
        foreach ($regPath in $regPaths) {
            if (Test-Path $regPath) {
                $items = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
                $properties = $items.PSObject.Properties | Where-Object { $_.Name -notin @("PSPath", "PSParentPath", "PSChildName", "PSDrive", "PSProvider") }
                
                foreach ($prop in $properties) {
                    $startupItems += [PSCustomObject]@{
                        Name = $prop.Name
                        Command = $prop.Value
                        Location = "注册表 (当前用户)"
                        Type = "Registry"
                    }
                }
            }
        }
    } catch {}
    
    # 2. 注册表启动项 - 所有用户
    try {
        $regPaths = @(
            "HKLM:\Software\Microsoft\Windows\CurrentVersion\Run",
            "HKLM:\Software\Microsoft\Windows\CurrentVersion\RunOnce"
        )
        
        foreach ($regPath in $regPaths) {
            if (Test-Path $regPath) {
                $items = Get-ItemProperty -Path $regPath -ErrorAction SilentlyContinue
                $properties = $items.PSObject.Properties | Where-Object { $_.Name -notin @("PSPath", "PSParentPath", "PSChildName", "PSDrive", "PSProvider") }
                
                foreach ($prop in $properties) {
                    $startupItems += [PSCustomObject]@{
                        Name = $prop.Name
                        Command = $prop.Value
                        Location = "注册表 (所有用户)"
                        Type = "Registry"
                    }
                }
            }
        }
    } catch {}
    
    # 3. 启动文件夹 - 当前用户
    try {
        $startupFolder = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup"
        if (Test-Path $startupFolder) {
            $items = Get-ChildItem -Path $startupFolder -File -ErrorAction SilentlyContinue
            foreach ($item in $items) {
                $startupItems += [PSCustomObject]@{
                    Name = $item.BaseName
                    Command = $item.FullName
                    Location = "启动文件夹 (当前用户)"
                    Type = "Folder"
                }
            }
        }
    } catch {}
    
    # 4. 启动文件夹 - 所有用户
    try {
        $startupFolder = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"
        if (Test-Path $startupFolder) {
            $items = Get-ChildItem -Path $startupFolder -File -ErrorAction SilentlyContinue
            foreach ($item in $items) {
                $startupItems += [PSCustomObject]@{
                    Name = $item.BaseName
                    Command = $item.FullName
                    Location = "启动文件夹 (所有用户)"
                    Type = "Folder"
                }
            }
        }
    } catch {}
    
    # 5. 任务计划程序
    try {
        $tasks = Get-ScheduledTask | Where-Object { 
            $_.Triggers -and 
            $_.Triggers[0].CimClass.CimClassName -eq "MSFT_TaskBootTrigger" -and
            $_.State -ne "Disabled"
        } | Select-Object -First 20
        
        foreach ($task in $tasks) {
            $startupItems += [PSCustomObject]@{
                Name = $task.TaskName
                Command = $task.Actions.Execute
                Location = "任务计划程序"
                Type = "Task"
            }
        }
    } catch {}
    
    return $startupItems
}

# ==================== 获取启动影响 ====================
function Get-StartupImpact {
    try {
        $startupImpact = Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StartupApproved\Run" -ErrorAction SilentlyContinue
        return $startupImpact
    } catch {
        return $null
    }
}

# ==================== 主函数 ====================
function Show-StartupReport {
    Write-Host "
╔══════════════════════════════════════════════════════════════╗" -ForegroundColor Cyan
    Write-Host "║           🐾 ClawSysAdmin - 启动项管理                      ║" -ForegroundColor Cyan
    Write-Host "╚══════════════════════════════════════════════════════════════╝" -ForegroundColor Cyan
    Write-Host ""
    
    $startupItems = Get-StartupItems
    
    if ($startupItems.Count -eq 0) {
        Write-Host "未找到启动项" -ForegroundColor Gray
        return
    }
    
    Write-Host "共发现 $($startupItems.Count) 个启动项:" -ForegroundColor Yellow
    Write-Host ""
    
    # 按类型分组显示
    $grouped = $startupItems | Group-Object -Property Location
    
    foreach ($group in $grouped) {
        Write-Host "【$($group.Name)】" -ForegroundColor Green
        Write-Host "  数量: $($group.Count)" -ForegroundColor Gray
        Write-Host ""
        
        $counter = 1
        foreach ($item in $group.Group) {
            Write-Host "  $counter. $($item.Name)" -ForegroundColor White
            
            # 截断命令显示
            $command = $item.Command
            if ($command -and $command.Length -gt 60) {
                $command = $command.Substring(0, 57) + "..."
            }
            Write-Host "     命令: $command" -ForegroundColor Gray
            Write-Host ""
            $counter++
        }
        
        Write-Host ""
    }
    
    # 建议
    Write-Host "────────────────────────────────────────" -ForegroundColor Gray
    Write-Host ""
    Write-Host "💡 优化建议:" -ForegroundColor Cyan
    Write-Host "  启动项过多会拖慢开机速度，建议:" -ForegroundColor White
    Write-Host "  1. 禁用不常用的软件自启动" -ForegroundColor White
    Write-Host "  2. 保留杀毒软件、输入法等必要程序" -ForegroundColor White
    Write-Host "  3. 使用任务管理器管理启动项 (Ctrl+Shift+Esc)" -ForegroundColor White
    Write-Host ""
    Write-Host "⚠️ 注意:" -ForegroundColor Yellow
    Write-Host "  禁用启动项前请确认该程序不是系统关键服务" -ForegroundColor White
    Write-Host ""
}

# 执行主函数
Show-StartupReport
