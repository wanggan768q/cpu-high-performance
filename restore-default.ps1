#Requires -Version 5.1

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Write-Info($msg)    { Write-Host "[信息] $msg" -ForegroundColor Cyan }
function Write-Ok($msg)      { Write-Host "[完成] $msg" -ForegroundColor Green }
function Write-WarnMsg($msg) { Write-Host "[警告] $msg" -ForegroundColor Yellow }
function Write-Err($msg)     { Write-Host "[错误] $msg" -ForegroundColor Red }

function Get-ExecutionPaths {
    $launchFile = $null

    if ($PSCommandPath) {
        $launchFile = $PSCommandPath
    }
    elseif ($MyInvocation.MyCommand -and $MyInvocation.MyCommand.ScriptBlock) {
        $selfText = $MyInvocation.MyCommand.ScriptBlock.ToString()
        if ($selfText) {
            $launchFile = Join-Path $env:TEMP 'restore-default.ps1'
            Set-Content -LiteralPath $launchFile -Value $selfText -Encoding UTF8 -Force
        }
    }

    [pscustomobject]@{
        LaunchFile = $launchFile
    }
}

$script:Paths = Get-ExecutionPaths

function Test-Admin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    $p  = New-Object Security.Principal.WindowsPrincipal($id)
    return $p.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Restart-Elevated {
    if (-not $script:Paths.LaunchFile) {
        throw "无法确定脚本路径。请改用先下载再执行的方式运行此脚本。"
    }

    Start-Process powershell.exe -Verb RunAs -ArgumentList @(
        '-NoProfile',
        '-ExecutionPolicy', 'Bypass',
        '-File', "`"$($script:Paths.LaunchFile)`""
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
    Write-Ok "当前已切换到平衡电源方案"

    Write-Host ""
    Write-Host "---------- 当前状态 ----------"
    try {
        $active = Invoke-PowerCfg -Arguments @('/getactivescheme')
        Write-Host $active
    }
    catch {
        Write-WarnMsg "无法读取当前活动电源方案"
    }

    Write-Host ""
    Write-Host "[说明] 已恢复默认设置，建议重启一次系统。"
    Write-Host "[说明] restoredefaultschemes 会重置电源方案，并删除自定义电源计划。"
}
catch {
    Write-Err $_.Exception.Message
    exit 1
}
