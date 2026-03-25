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
        throw "无法确定脚本路径。请改用先下载再执行的方式运行此脚本。"
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

    Write-Info "步骤 1/7：检查关闭电源节流支持情况"
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
    Write-Info "步骤 2/7：恢复默认电源方案"
    try {
        Invoke-PowerCfg -Arguments @('/restoredefaultschemes') | Out-Null
        Write-Ok "已恢复默认电源方案"
    }
    catch {
        Write-WarnMsg $_.Exception.Message
    }

    Write-Host ""
    Write-Info "步骤 3/7：切换到高性能电源方案"
    try {
        Invoke-PowerCfg -Arguments @('/setactive', 'SCHEME_MIN') | Out-Null
        Write-Ok "当前已切换到高性能"
    }
    catch {
        Write-WarnMsg "切换到高性能电源方案失败，继续执行后续步骤。"
    }

    Write-Host ""
    Write-Info "步骤 4/7：导出当前处理器电源设置到 a.txt"
    $txtPath = Join-Path $script:Paths.OutputDir 'a.txt'
    try {
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
    }
    catch {
        Write-WarnMsg "导出电源设置失败：$($_.Exception.Message)"
    }

    Write-Host ""
    Write-Info "步骤 5/7：从 a.txt 中搜索对应 GUID"

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
        Write-Ok "已从 a.txt 识别处理器子组 GUID: $processorSubgroupGuid"
    }
    else {
        Write-WarnMsg "未能从 a.txt 识别处理器电源管理子组 GUID"
    }

    if ($schedPolicyGuid) {
        Write-Ok "已从 a.txt 识别异类线程调度策略 GUID: $schedPolicyGuid"
    }
    else {
        Write-WarnMsg "未能从 a.txt 识别异类线程调度策略 GUID"
    }

    if ($shortSchedPolicyGuid) {
        Write-Ok "已从 a.txt 识别异类短运行线程调度策略 GUID: $shortSchedPolicyGuid"
    }
    else {
        Write-WarnMsg "未能从 a.txt 识别异类短运行线程调度策略 GUID"
    }

    Write-Host ""
    Write-Info "步骤 6/7：取消隐藏对应电源选项"

    if ($processorSubgroupGuid -and $schedPolicyGuid) {
        Invoke-PowerCfg -Arguments @('-attributes', $processorSubgroupGuid, $schedPolicyGuid, '-ATTRIB_HIDE') -IgnoreError | Out-Null
        Write-Ok "已取消隐藏异类线程调度策略"
    }
    else {
        Write-Skip "由于未找到对应 GUID，跳过取消隐藏异类线程调度策略"
    }

    if ($processorSubgroupGuid -and $shortSchedPolicyGuid) {
        Invoke-PowerCfg -Arguments @('-attributes', $processorSubgroupGuid, $shortSchedPolicyGuid, '-ATTRIB_HIDE') -IgnoreError | Out-Null
        Write-Ok "已取消隐藏异类短运行线程调度策略"
    }
    else {
        Write-Skip "由于未找到对应 GUID，跳过取消隐藏异类短运行线程调度策略"
    }

    Write-Host ""
    Write-Info "步骤 7/7：写入高性能相关设置"

    if ($processorSubgroupGuid -and $schedPolicyGuid) {
        Invoke-PowerCfg -Arguments @('/setacvalueindex', 'SCHEME_CURRENT', $processorSubgroupGuid, $schedPolicyGuid, '2') | Out-Null
        Invoke-PowerCfg -Arguments @('/setdcvalueindex', 'SCHEME_CURRENT', $processorSubgroupGuid, $schedPolicyGuid, '2') | Out-Null
        Write-Ok "异类线程调度策略已设置为首选高性能处理器"
    }
    else {
        Write-Skip "由于未找到对应 GUID，跳过设置异类线程调度策略"
    }

    if ($processorSubgroupGuid -and $shortSchedPolicyGuid) {
        Invoke-PowerCfg -Arguments @('/setacvalueindex', 'SCHEME_CURRENT', $processorSubgroupGuid, $shortSchedPolicyGuid, '2') | Out-Null
        Invoke-PowerCfg -Arguments @('/setdcvalueindex', 'SCHEME_CURRENT', $processorSubgroupGuid, $shortSchedPolicyGuid, '2') | Out-Null
        Write-Ok "异类短运行线程调度策略已设置为首选高性能处理器"
    }
    else {
        Write-Skip "由于未找到对应 GUID，跳过设置异类短运行线程调度策略"
    }

    Invoke-PowerCfg -Arguments @('/setactive', 'SCHEME_CURRENT') -IgnoreError | Out-Null

    Write-Host ""
    Write-Host "---------- 当前状态 ----------"

    try {
        $reg = Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Power\PowerThrottling' -ErrorAction Stop
        Write-Host "PowerThrottlingOff = $($reg.PowerThrottlingOff)"
    }
    catch {
        Write-WarnMsg "无法读取 PowerThrottlingOff"
    }

    if ($processorSubgroupGuid -and $schedPolicyGuid) {
        Write-Host "---------- SCHED POLICY ----------"
        (Invoke-PowerCfg -Arguments @('/query', 'SCHEME_CURRENT', $processorSubgroupGuid, $schedPolicyGuid)).Output | Write-Host
    }

    if ($processorSubgroupGuid -and $shortSchedPolicyGuid) {
        Write-Host "---------- SHORT SCHED POLICY ----------"
        (Invoke-PowerCfg -Arguments @('/query', 'SCHEME_CURRENT', $processorSubgroupGuid, $shortSchedPolicyGuid)).Output | Write-Host
    }

    Write-Host ""
    Write-Host "[说明] 关闭电源节流仅适用于 Windows 10 1709+ / Windows 11"
    Write-Host "[说明] 首选高性能处理器 对应值为 2"
    Write-Host "[说明] 本脚本按你的要求，从 a.txt 中搜索名称并提取对应 GUID"
    Write-Host "[说明] 如果你的系统翻译不同，请调整脚本中的 CandidateNames"
    Write-Host "[说明] 建议执行后重启一次系统"
}
catch {
    Write-Err $_.Exception.Message
    exit 1
}
