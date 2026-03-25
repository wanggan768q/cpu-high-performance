#Requires -Version 5.1

[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'

function Write-Info($msg)    { Write-Host "[信息] $msg" -ForegroundColor Cyan }
function Write-Ok($msg)      { Write-Host "[完成] $msg" -ForegroundColor Green }
function Write-WarnMsg($msg) { Write-Host "[警告] $msg" -ForegroundColor Yellow }
function Write-Skip($msg)    { Write-Host "[跳过] $msg" -ForegroundColor DarkYellow }
function Write-Err($msg)     { Write-Host "[错误] $msg" -ForegroundColor Red }

function Get-ExecutionPaths {
    $outputDir = (Get-Location).Path
    $launchFile = $null

    if ($PSCommandPath) {
        $launchFile = $PSCommandPath
        $outputDir = Split-Path -Parent $PSCommandPath
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
        OutputDir  = $outputDir
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
        [string[]]$Arguments,
        [switch]$IgnoreError
    )

    $output = & powercfg @Arguments 2>&1
    $code = $LASTEXITCODE

    if (-not $IgnoreError -and $code -ne 0) {
        throw "powercfg 执行失败: powercfg $($Arguments -join ' ')`n$output"
    }

    [pscustomobject]@{
        ExitCode = $code
        Output   = ($output | Out-String).Trim()
    }
}

function Find-GuidInLinesByNames {
    param(
        [Parameter(Mandatory = $true)]
        [string[]]$Lines,

        [Parameter(Mandatory = $true)]
        [string[]]$CandidateNames
    )

    $guidPattern = '(?i)\b[0-9a-f]{8}(?:-[0-9a-f]{4}){3}-[0-9a-f]{12}\b'

    for ($i = 0; $i -lt $Lines.Count; $i++) {
        $line = [string]$Lines[$i]
        $matchedName = $false

        foreach ($name in $CandidateNames) {
            if ([string]::IsNullOrWhiteSpace($name)) { continue }
            if ($line.IndexOf($name, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) {
                $matchedName = $true
                break
            }
        }

        if (-not $matchedName) { continue }

        $m = [regex]::Match($line, $guidPattern)
        if ($m.Success) {
            return $m.Value.ToLowerInvariant()
        }

        $start = [Math]::Max(0, $i - 3)
        $end   = [Math]::Min($Lines.Count - 1, $i + 3)

        for ($j = $start; $j -le $end; $j++) {
            $nearLine = [string]$Lines[$j]
            $nearMatch = [regex]::Match($nearLine, $guidPattern)
            if ($nearMatch.Success) {
                return $nearMatch.Value.ToLowerInvariant()
            }
        }
    }

    return $null
}

try {
    if (-not (Test-Admin)) {
        Write-Info "当前未以管理员身份运行，正在请求提权..."
        Restart-Elevated
    }

    Write-Info "步骤 1/6：导出当前处理器电源设置到 a.txt"
    $txtPath = Join-Path $script:Paths.OutputDir 'a.txt'
    $q1 = Invoke-PowerCfg -Arguments @('/query', 'SCHEME_CURRENT', 'SUB_PROCESSOR')
    $q2 = Invoke-PowerCfg -Arguments @('/qh')

    @(
        $q1.Output
        ""
        "===================="
        "FULL HIDDEN SETTINGS"
        "===================="
        ""
        $q2.Output
    ) | Set-Content -LiteralPath $txtPath -Encoding UTF8

    Write-Ok "已生成 $txtPath"

    Write-Host ""
    Write-Info "步骤 2/6：从 a.txt 中搜索对应 GUID"

    $lines = Get-Content -LiteralPath $txtPath -ErrorAction Stop

    $processorSubgroupGuid = Find-GuidInLinesByNames -Lines $lines -CandidateNames @(
        'Processor power management',
        '处理器电源管理'
    )

    $schedPolicyGuid = Find-GuidInLinesByNames -Lines $lines -CandidateNames @(
        'Heterogeneous thread scheduling policy',
        '异类线程调度策略'
    )

    $shortSchedPolicyGuid = Find-GuidInLinesByNames -Lines $lines -CandidateNames @(
        'Heterogeneous short running thread scheduling policy',
        '异类短运行线程调度策略'
    )

    if ($processorSubgroupGuid) {
        Write-Ok "已识别处理器子组 GUID: $processorSubgroupGuid"
    } else {
        Write-WarnMsg "未能识别处理器子组 GUID"
    }

    if ($schedPolicyGuid) {
        Write-Ok "已识别异类线程调度策略 GUID: $schedPolicyGuid"
    } else {
        Write-WarnMsg "未能识别异类线程调度策略 GUID"
    }

    if ($shortSchedPolicyGuid) {
        Write-Ok "已识别异类短运行线程调度策略 GUID: $shortSchedPolicyGuid"
    } else {
        Write-WarnMsg "未能识别异类短运行线程调度策略 GUID"
    }

    Write-Host ""
    Write-Info "步骤 3/6：移除 PowerThrottlingOff"
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
    Write-Info "步骤 4/6：恢复默认电源方案"
    Invoke-PowerCfg -Arguments @('/restoredefaultschemes') | Out-Null
    Write-Ok "已恢复默认电源方案"

    Write-Host ""
    Write-Info "步骤 5/6：切换到平衡模式"
    Invoke-PowerCfg -Arguments @('/setactive', 'SCHEME_BALANCED') | Out-Null
    Write-Ok "当前已切换到平衡电源方案"

    Write-Host ""
    Write-Info "步骤 6/6：根据 a.txt 中找到的 GUID 重新隐藏两个电源选项"

    if ($processorSubgroupGuid -and $schedPolicyGuid) {
        Invoke-PowerCfg -Arguments @('/attributes', $processorSubgroupGuid, $schedPolicyGuid, '+ATTRIB_HIDE') -IgnoreError | Out-Null
        Write-Ok "已重新隐藏异类线程调度策略"
    }
    else {
        Write-Skip "由于未找到对应 GUID，跳过隐藏异类线程调度策略"
    }

    if ($processorSubgroupGuid -and $shortSchedPolicyGuid) {
        Invoke-PowerCfg -Arguments @('/attributes', $processorSubgroupGuid, $shortSchedPolicyGuid, '+ATTRIB_HIDE') -IgnoreError | Out-Null
        Write-Ok "已重新隐藏异类短运行线程调度策略"
    }
    else {
        Write-Skip "由于未找到对应 GUID，跳过隐藏异类短运行线程调度策略"
    }

    Write-Host ""
    Write-Host "---------- 当前状态 ----------"
    try {
        $active = Invoke-PowerCfg -Arguments @('/getactivescheme')
        Write-Host $active.Output
    }
    catch {
        Write-WarnMsg "无法读取当前活动电源方案"
    }

    Write-Host ""
    Write-Host "[说明] 已恢复默认设置。"
    Write-Host "[说明] 本脚本按你的要求，从 a.txt 中搜索名称并提取 GUID。"
    Write-Host "[说明] restoredefaultschemes 会重置电源方案，并删除自定义电源计划。"
    Write-Host "[说明] 建议执行后重启一次系统。"
}
catch {
    Write-Err $_.Exception.Message
    exit 1
}
