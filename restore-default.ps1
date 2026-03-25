#Requires -Version 5.1

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Write-Info($msg) { Write-Host "[信息] $msg" -ForegroundColor Cyan }
function Write-Ok($msg)   { Write-Host "[完成] $msg" -ForegroundColor Green }
function Write-WarnMsg($msg) { Write-Host "[警告] $msg" -ForegroundColor Yellow }
function Write-Err($msg)  { Write-Host "[错误] $msg" -ForegroundColor Red }

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Restart-Elevated {
    $currentPath = $PSCommandPath
    if (-not $currentPath) {
        throw "请先将脚本保存为 .ps1 文件后再运行；当前执行方式无法自动提权。"
    }

    Start-Process powershell -Verb RunAs -ArgumentList @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', "`"$currentPath`""
    )
    exit
}

function Invoke-PowerCfg {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Arguments
    )

    $output = & powercfg @Arguments 2>&1
    $code = $LASTEXITCODE

    if ($code -ne 0) {
        throw "powercfg 执行失败: powercfg $($Arguments -join ' ')`n$output"
    }

    return ($output | Out-String).Trim()
}

try {
    if (-not (Test-Admin)) {
        Write-Info "当前未以管理员身份运行，正在请求提权..."
        Restart-Elevated
    }

    Write-Info "步骤 1/3：移除 PowerThrottlingOff"
    $ptPath = 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling'
    if (Test-Path $ptPath) {
        $prop = Get-ItemProperty -Path $ptPath -Name 'PowerThrottlingOff' -ErrorAction SilentlyContinue
        if ($null -ne $prop) {
            Remove-ItemProperty -Path $ptPath -Name 'PowerThrottlingOff' -ErrorAction Stop
            Write-Ok "已删除 PowerThrottlingOff，恢复默认电源节流行为"
        }
        else {
            Write-Info "未检测到 PowerThrottlingOff，无需处理"
        }
    }
    else {
        Write-Info "未检测到 PowerThrottling 注册表路径，无需处理"
    }

    Write-Host ""
    Write-Info "步骤 2/3：恢复默认电源方案"
    Invoke-PowerCfg -Arguments @('/restoredefaultschemes') | Out-Null
    Write-Ok "已恢复默认电源方案"

    Write-Host ""
    Write-Info "步骤 3/3：切换到平衡模式"
    Invoke-PowerCfg -Arguments @('/setactive', 'SCHEME_BALANCED') | Out-Null
    Write-Ok "当前已切换到“平衡”电源方案"

    Write-Host ""
    Write-Host "---------- 当前状态 ----------"
    try {
        $active = Invoke-PowerCfg -Arguments @('/getactivescheme')
        Write-Host $active
    } catch {
        Write-WarnMsg "无法读取当前活动电源方案"
    }

    Write-Host ""
    Write-Host "[说明] 已恢复默认设置。建议重启一次系统。"

}
catch {
    Write-Err $_.Exception.Message
    exit 1
}
