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
            $launchFile = Join-Path $env:TEMP 'cpu-high-performance.ps1'
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
        throw "无法确定脚本路径。请改用“先下载再执行”的方式运行此脚本。"
    }

    $argList = @(
        '-NoProfile'
        '-ExecutionPolicy', 'Bypass'
        '-File', "`"$($script:Paths.LaunchFile)`""
    )

    Start-Process powershell.exe -Verb RunAs -ArgumentList $argList
    exit
}

function Get-OsInfo {
    $cv = Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion'
    [pscustomobject]@{
        ProductName        = $cv.ProductName
        CurrentVersion     = $cv.CurrentVersion
        CurrentBuildNumber = [int]$cv.CurrentBuildNumber
        DisplayVersion     = $cv.DisplayVersion
    }
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

function Test-PowerCfgSetting {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Alias
    )

    $r = Invoke-PowerCfg -Arguments @('/query', 'SCHEME_CURRENT', 'SUB_PROCESSOR', $Alias) -IgnoreError
    return ($r.ExitCode -eq 0)
}

try {
    if (-not (Test-Admin)) {
        Write-Info "当前未以管理员身份运行，正在请求提权..."
        Restart-Elevated
    }

    $os = Get-OsInfo

    Write-Info "Windows Product : $($os.ProductName)"
    Write-Info "Windows Version : $($os.CurrentVersion)"
    Write-Info "Windows Build   : $($os.CurrentBuildNumber)"
    if ($os.DisplayVersion) {
        Write-Info "Display Version : $($os.DisplayVersion)"
    }
    Write-Host ""

    $isWin10 = $os.ProductName -like '*Windows 10*'
    $isWin11 = $os.ProductName -like '*Windows 11*'

    if (-not ($isWin10 -or $isWin11)) {
        Write-Err "该脚本按 Windows 10 / 11 桌面版设计，当前系统不在支持范围内。"
        exit 1
    }

    $supportPowerThrottling = $os.CurrentBuildNumber -ge 16299

    Write-Info "步骤 1/6：检查“关闭电源节流”支持情况"
    if ($supportPowerThrottling) {
        New-Item -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' -Force | Out-Null
        New-ItemProperty `
            -Path 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' `
            -Name 'PowerThrottlingOff' `
            -PropertyType DWord `
            -Value 1 `
            -Force | Out-Null
        Write-Ok "已写入 PowerThrottlingOff=1"
    }
    else {
        Write-Skip "当前系统版本过低，不支持该设置。需要 Windows 10 1709 / Build 16299 或更高版本。"
    }

    Write-Host ""
    Write-Info "步骤 2/6：恢复默认电源方案"
    try {
        Invoke-PowerCfg -Arguments @('/restoredefaultschemes') | Out-Null
        Write-Ok "已恢复默认电源方案"
    }
    catch {
        Write-WarnMsg $_.Exception.Message
    }

    Write-Host ""
    Write-Info "步骤 3/6：切换到高性能电源方案"
    try {
        Invoke-PowerCfg -Arguments @('/setactive', 'SCHEME_MIN') | Out-Null
        Write-Ok "当前已切换到“高性能”"
    }
    catch {
        Write-WarnMsg "切换到高性能电源方案失败，继续执行后续步骤。"
    }

    Write-Host ""
    Write-Info "步骤 4/6：导出当前处理器电源设置到 a.txt"
    $txtPath = Join-Path $script:Paths.OutputDir 'a.txt'
    try {
        $q1 = Invoke-PowerCfg -Arguments @('/query', 'SCHEME_CURRENT', 'SUB_PROCESSOR')
        $q2 = Invoke-PowerCfg -Arguments @('/qh')
        @(
            $q1.Output
            ""
            $q2.Output
        ) | Set-Content -LiteralPath $txtPath -Encoding UTF8
        Write-Ok "已生成 $txtPath"
    }
    catch {
        Write-WarnMsg "导出电源设置失败：$($_.Exception.Message)"
    }

    Write-Host ""
    Write-Info "步骤 5/6：检查异类线程调度策略支持情况"

    $hasSchedPolicy = Test-PowerCfgSetting -Alias 'SCHEDPOLICY'
    $hasShortSchedPolicy = Test-PowerCfgSetting -Alias 'SHORTSCHEDPOLICY'

    if ($hasSchedPolicy) {
        Invoke-PowerCfg -Arguments @('/setacvalueindex', 'SCHEME_CURRENT', 'SUB_PROCESSOR', 'SCHEDPOLICY', '2') | Out-Null
        Invoke-PowerCfg -Arguments @('/setdcvalueindex', 'SCHEME_CURRENT', 'SUB_PROCESSOR', 'SCHEDPOLICY', '2') | Out-Null
        Write-Ok "SCHEDPOLICY 已设置为“首选高性能处理器”"
    }
    else {
        Write-Skip "当前系统/CPU 未暴露 SCHEDPOLICY"
    }

    if ($hasShortSchedPolicy) {
        Invoke-PowerCfg -Arguments @('/setacvalueindex', 'SCHEME_CURRENT', 'SUB_PROCESSOR', 'SHORTSCHEDPOLICY', '2') | Out-Null
        Invoke-PowerCfg -Arguments @('/setdcvalueindex', 'SCHEME_CURRENT', 'SUB_PROCESSOR', 'SHORTSCHEDPOLICY', '2') | Out-Null
        Write-Ok "SHORTSCHEDPOLICY 已设置为“首选高性能处理器”"
    }
    else {
        Write-Skip "当前系统/CPU 未暴露 SHORTSCHEDPOLICY"
    }

    if (-not $hasSchedPolicy -and -not $hasShortSchedPolicy) {
        Write-WarnMsg "该机器虽然是受支持的 Windows 10/11，但当前平台没有暴露异类线程调度策略。常见原因是非混合架构 CPU，或固件/平台未提供这些设置。"
    }

    Invoke-PowerCfg -Arguments @('/setactive', 'SCHEME_CURRENT') -IgnoreError | Out-Null

    Write-Host ""
    Write-Info "步骤 6/6：输出当前状态"

    try {
        $reg = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' -ErrorAction Stop
        Write-Host "---------- Power Throttling ----------"
        Write-Host "PowerThrottlingOff = $($reg.PowerThrottlingOff)"
    }
    catch {
        Write-WarnMsg "无法读取 PowerThrottlingOff"
    }

    if ($hasSchedPolicy) {
        Write-Host "---------- SCHEDPOLICY ----------"
        (Invoke-PowerCfg -Arguments @('/query', 'SCHEME_CURRENT', 'SUB_PROCESSOR', 'SCHEDPOLICY')).Output | Write-Host
    }

    if ($hasShortSchedPolicy) {
        Write-Host "---------- SHORTSCHEDPOLICY ----------"
        (Invoke-PowerCfg -Arguments @('/query', 'SCHEME_CURRENT', 'SUB_PROCESSOR', 'SHORTSCHEDPOLICY')).Output | Write-Host
    }

    Write-Host ""
    Write-Host "[说明] 关闭电源节流仅适用于 Windows 10 1709+ / Windows 11"
    Write-Host "[说明] 异类线程调度策略仅在系统实际提供该设置时才会应用"
    Write-Host "[说明] “首选高性能处理器” 对应值为 2"
    Write-Host "[说明] 建议执行后重启一次系统"
}
catch {
    Write-Err $_.Exception.Message
    exit 1
}
