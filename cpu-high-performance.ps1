#Requires -RunAsAdministrator
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [Alias('Action')]
    [string]$CpuHighPerformanceAction
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$HighPerformanceSchemeGuid = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
$BalancedSchemeGuid = '381b4222-f694-41f0-9685-ff5bb260df2e'
$ProcessorSubgroupGuid = '54533251-82be-4824-96c1-47b60b740d00'
$SleepSubgroupGuid = '238c9fa8-0aad-41ed-83f4-97be242c8f20'
$StandbyIdleGuid = '29f6c1db-86da-48c5-9fdb-f2b67b1f44da'
$HybridSleepGuid = '94ac6d29-73ce-41a6-809f-6363ba21b47e'
$HibernateIdleGuid = '9d7815a6-7ee4-497e-8888-515a05f02364'

function Assert-Administrator {
    $identity = [Security.Principal.WindowsIdentity]::GetCurrent()
    $principal = New-Object Security.Principal.WindowsPrincipal($identity)
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        throw 'Please run this script from an elevated PowerShell session.'
    }
}

function Invoke-PowerCfgQuery {
    param([Parameter(Mandatory)][string[]]$Arguments)

    $output = & powercfg.exe @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "powercfg.exe $($Arguments -join ' ') failed with exit code $LASTEXITCODE. $(($output | Out-String).Trim())"
    }

    return ($output | Out-String)
}

function Invoke-PowerCfgChange {
    param(
        [Parameter(Mandatory)][string]$Action,
        [Parameter(Mandatory)][string]$Target,
        [Parameter(Mandatory)][string[]]$Arguments
    )

    if (-not $PSCmdlet.ShouldProcess($Target, $Action)) {
        return
    }

    $output = & powercfg.exe @Arguments 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "powercfg.exe $($Arguments -join ' ') failed with exit code $LASTEXITCODE. $(($output | Out-String).Trim())"
    }
}

function New-UnicodeString {
    param([Parameter(Mandatory)][int[]]$CodePoints)

    return -join ($CodePoints | ForEach-Object { [char]$_ })
}

function Get-StateInfo {
    $commonApplicationData = [Environment]::GetFolderPath('CommonApplicationData')
    if ([string]::IsNullOrWhiteSpace($commonApplicationData)) {
        $commonApplicationData = $env:ProgramData
    }
    if ([string]::IsNullOrWhiteSpace($commonApplicationData)) {
        $commonApplicationData = $env:LOCALAPPDATA
    }
    if ([string]::IsNullOrWhiteSpace($commonApplicationData)) {
        throw 'Unable to resolve a stable directory for the backup state file.'
    }

    $stateDirectory = Join-Path -Path $commonApplicationData -ChildPath 'CpuHighPerformance'
    $stateFilePath = Join-Path -Path $stateDirectory -ChildPath 'state.json'
    $legacyStateFiles = @()

    if (-not [string]::IsNullOrWhiteSpace($PSScriptRoot)) {
        $legacyStateFiles += Join-Path -Path (Join-Path -Path $PSScriptRoot -ChildPath '.powercfg-backup') -ChildPath 'state.json'
    }

    return [ordered]@{
        StateDirectory = $stateDirectory
        StateFilePath = $stateFilePath
        LegacyStateFiles = $legacyStateFiles | Select-Object -Unique
    }
}

function Get-ExistingStateFilePath {
    param([Parameter(Mandatory)][hashtable]$StateInfo)

    if (Test-Path -Path $StateInfo.StateFilePath) {
        return $StateInfo.StateFilePath
    }

    foreach ($candidate in $StateInfo.LegacyStateFiles) {
        if (Test-Path -Path $candidate) {
            return $candidate
        }
    }

    return $null
}

function Remove-StateArtifacts {
    param([Parameter(Mandatory)][string]$StateFilePath)

    if (Test-Path -Path $StateFilePath) {
        Remove-Item -Path $StateFilePath -Force
    }

    $stateDirectory = Split-Path -Path $StateFilePath -Parent
    if ((Test-Path -Path $stateDirectory) -and -not (Get-ChildItem -Path $stateDirectory -Force | Select-Object -First 1)) {
        Remove-Item -Path $stateDirectory -Force
    }
}

function Get-FirstGuidFromText {
    param([Parameter(Mandatory)][string]$Text)

    $match = [regex]::Match($Text, '[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}')
    if (-not $match.Success) {
        throw 'Unable to find a GUID in powercfg output.'
    }

    return $match.Value.ToLowerInvariant()
}

function Convert-HexIndexToDecimal {
    param([Parameter(Mandatory)][string]$Value)

    return [int][Convert]::ToUInt32($Value.Replace('0x', ''), 16)
}

function Get-IndexValueFromLines {
    param(
        [Parameter(Mandatory)][AllowEmptyString()][string[]]$Lines,
        [Parameter(Mandatory)][string[]]$Markers
    )

    foreach ($line in $Lines) {
        foreach ($marker in $Markers) {
            if ($line -like "*$marker*") {
                $match = [regex]::Match($line, '0x[0-9A-Fa-f]+')
                if ($match.Success) {
                    return Convert-HexIndexToDecimal -Value $match.Value
                }
            }
        }
    }

    throw 'Unable to extract a power setting index from powercfg output.'
}

function Get-SettingValuePair {
    param(
        [Parameter(Mandatory)][string]$SchemeGuid,
        [Parameter(Mandatory)][string]$SubgroupGuid,
        [Parameter(Mandatory)][string]$SettingGuid
    )

    $text = Invoke-PowerCfgQuery -Arguments @('/q', $SchemeGuid, $SubgroupGuid, $SettingGuid)
    if ([string]::IsNullOrWhiteSpace($text)) {
        throw "powercfg /q returned no output for scheme '$SchemeGuid', subgroup '$SubgroupGuid', setting '$SettingGuid'."
    }

    $lines = ($text -split "`r?`n") | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }
    $currentAcMarkerZh = New-UnicodeString -CodePoints @(0x5F53,0x524D,0x4EA4,0x6D41,0x7535,0x6E90,0x8BBE,0x7F6E,0x7D22,0x5F15)
    $currentDcMarkerZh = New-UnicodeString -CodePoints @(0x5F53,0x524D,0x76F4,0x6D41,0x7535,0x6E90,0x8BBE,0x7F6E,0x7D22,0x5F15)

    return [ordered]@{
        Ac = Get-IndexValueFromLines -Lines $lines -Markers @('Current AC Power Setting Index', $currentAcMarkerZh)
        Dc = Get-IndexValueFromLines -Lines $lines -Markers @('Current DC Power Setting Index', $currentDcMarkerZh)
    }
}

function Get-HeterogeneousDisplayNames {
    return [ordered]@{
        Thread = @(
            (New-UnicodeString -CodePoints @(0x5F02,0x7C7B,0x7EBF,0x7A0B,0x8C03,0x5EA6,0x7B56,0x7565)),
            'Heterogeneous thread scheduling policy'
        )
        ShortThread = @(
            (New-UnicodeString -CodePoints @(0x5F02,0x7C7B,0x77ED,0x8FD0,0x884C,0x7EBF,0x7A0B,0x8C03,0x5EA6,0x7B56,0x7565)),
            'Heterogeneous short running thread scheduling policy'
        )
    }
}

function Resolve-HeterogeneousSetting {
    param(
        [Parameter(Mandatory)][string]$QueryText,
        [Parameter(Mandatory)][string]$Name,
        [Parameter(Mandatory)][string[]]$LocalizedDisplayNames,
        [Parameter(Mandatory)][string]$Alias
    )

    $guidPattern = '[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}'
    $lines = $QueryText -split "`r?`n"

    foreach ($displayName in $LocalizedDisplayNames) {
        foreach ($line in $lines) {
            if ($line -like "*$displayName*") {
                $match = [regex]::Match($line, $guidPattern)
                if ($match.Success) {
                    return [ordered]@{
                        Name = $Name
                        Guid = $match.Value.ToLowerInvariant()
                        MatchedBy = 'display-name'
                        MatchedValue = $displayName
                    }
                }
            }
        }
    }

    for ($index = 0; $index -lt $lines.Length; $index++) {
        if ($lines[$index] -match ('(GUID 别名|GUID Alias)\s*[:：]\s*' + [regex]::Escape($Alias) + '\b')) {
            for ($lookup = $index - 1; $lookup -ge [Math]::Max(0, $index - 4); $lookup--) {
                $match = [regex]::Match($lines[$lookup], $guidPattern)
                if ($match.Success) {
                    return [ordered]@{
                        Name = $Name
                        Guid = $match.Value.ToLowerInvariant()
                        MatchedBy = 'alias'
                        MatchedValue = $Alias
                    }
                }
            }
        }
    }

    throw "Unable to find the GUID for '$Name'."
}

function Get-ExistingSchemeGuids {
    $text = Invoke-PowerCfgQuery -Arguments @('/list')
    return [regex]::Matches($text, '[0-9A-Fa-f]{8}(?:-[0-9A-Fa-f]{4}){3}-[0-9A-Fa-f]{12}') |
        ForEach-Object { $_.Value.ToLowerInvariant() } |
        Select-Object -Unique
}

function Invoke-ApplyMode {
    param([Parameter(Mandatory)][hashtable]$StateInfo)

    $existingSchemes = Get-ExistingSchemeGuids
    if ($existingSchemes -notcontains $HighPerformanceSchemeGuid) {
        throw "The built-in High performance scheme ($HighPerformanceSchemeGuid) is not available on this machine."
    }

    $processorQueryText = Invoke-PowerCfgQuery -Arguments @('/qh', 'SCHEME_CURRENT', 'SUB_PROCESSOR')
    $currentActiveSchemeGuid = Get-FirstGuidFromText -Text (Invoke-PowerCfgQuery -Arguments @('/getactivescheme'))
    $displayNames = Get-HeterogeneousDisplayNames

    $heterogeneousThreadSchedulingSetting = Resolve-HeterogeneousSetting -QueryText $processorQueryText -Name 'HeterogeneousThreadSchedulingPolicy' -LocalizedDisplayNames $displayNames.Thread -Alias 'SCHEDPOLICY'
    $heterogeneousShortRunningThreadSchedulingSetting = Resolve-HeterogeneousSetting -QueryText $processorQueryText -Name 'HeterogeneousShortRunningThreadSchedulingPolicy' -LocalizedDisplayNames $displayNames.ShortThread -Alias 'SHORTSCHEDPOLICY'
    $heterogeneousSettings = @($heterogeneousThreadSchedulingSetting, $heterogeneousShortRunningThreadSchedulingSetting)

    $state = [ordered]@{
        CreatedAt = (Get-Date).ToString('o')
        PreviousActiveSchemeGuid = $currentActiveSchemeGuid
        TargetSchemeGuid = $HighPerformanceSchemeGuid
        FallbackSchemeGuid = $BalancedSchemeGuid
        SleepSettings = [ordered]@{
            StandbyIdle = [ordered]@{
                Guid = $StandbyIdleGuid
                Values = Get-SettingValuePair -SchemeGuid $HighPerformanceSchemeGuid -SubgroupGuid $SleepSubgroupGuid -SettingGuid $StandbyIdleGuid
            }
            HybridSleep = [ordered]@{
                Guid = $HybridSleepGuid
                Values = Get-SettingValuePair -SchemeGuid $HighPerformanceSchemeGuid -SubgroupGuid $SleepSubgroupGuid -SettingGuid $HybridSleepGuid
            }
            HibernateIdle = [ordered]@{
                Guid = $HibernateIdleGuid
                Values = Get-SettingValuePair -SchemeGuid $HighPerformanceSchemeGuid -SubgroupGuid $SleepSubgroupGuid -SettingGuid $HibernateIdleGuid
            }
        }
        HeterogeneousSettings = @(
            foreach ($setting in $heterogeneousSettings) {
                [ordered]@{
                    Name = $setting.Name
                    Guid = $setting.Guid
                    MatchedBy = $setting.MatchedBy
                    MatchedValue = $setting.MatchedValue
                    Values = Get-SettingValuePair -SchemeGuid $HighPerformanceSchemeGuid -SubgroupGuid $ProcessorSubgroupGuid -SettingGuid $setting.Guid
                }
            }
        )
    }

    if ($PSCmdlet.ShouldProcess($StateInfo.StateFilePath, 'Save current power plan backup state')) {
        if (-not (Test-Path -Path $StateInfo.StateDirectory)) {
            New-Item -Path $StateInfo.StateDirectory -ItemType Directory -Force | Out-Null
        }

        $state | ConvertTo-Json -Depth 8 | Set-Content -Path $StateInfo.StateFilePath -Encoding UTF8
    }

    Invoke-PowerCfgChange -Action 'Activate High performance power plan' -Target $HighPerformanceSchemeGuid -Arguments @('/setactive', $HighPerformanceSchemeGuid)
    Invoke-PowerCfgChange -Action 'Disable AC sleep timeout' -Target 'SCHEME_CURRENT standby-timeout-ac' -Arguments @('/change', 'standby-timeout-ac', '0')
    Invoke-PowerCfgChange -Action 'Disable DC sleep timeout' -Target 'SCHEME_CURRENT standby-timeout-dc' -Arguments @('/change', 'standby-timeout-dc', '0')
    Invoke-PowerCfgChange -Action 'Disable AC hibernate timeout' -Target 'SCHEME_CURRENT hibernate-timeout-ac' -Arguments @('/change', 'hibernate-timeout-ac', '0')
    Invoke-PowerCfgChange -Action 'Disable DC hibernate timeout' -Target 'SCHEME_CURRENT hibernate-timeout-dc' -Arguments @('/change', 'hibernate-timeout-dc', '0')
    Invoke-PowerCfgChange -Action 'Disable AC hybrid sleep' -Target 'SCHEME_CURRENT HYBRIDSLEEP' -Arguments @('/setacvalueindex', 'SCHEME_CURRENT', 'SUB_SLEEP', $HybridSleepGuid, '0')
    Invoke-PowerCfgChange -Action 'Disable DC hybrid sleep' -Target 'SCHEME_CURRENT HYBRIDSLEEP' -Arguments @('/setdcvalueindex', 'SCHEME_CURRENT', 'SUB_SLEEP', $HybridSleepGuid, '0')

    foreach ($setting in $heterogeneousSettings) {
        Invoke-PowerCfgChange -Action 'Unhide processor scheduling setting' -Target $setting.Guid -Arguments @('-attributes', 'SUB_PROCESSOR', $setting.Guid, '-ATTRIB_HIDE')
        Invoke-PowerCfgChange -Action 'Prefer performant processors on AC' -Target $setting.Guid -Arguments @('/setacvalueindex', 'SCHEME_CURRENT', 'SUB_PROCESSOR', $setting.Guid, '2')
    }

    Invoke-PowerCfgChange -Action 'Re-apply the active power scheme' -Target 'SCHEME_CURRENT' -Arguments @('/setactive', 'SCHEME_CURRENT')

    Write-Host "High performance configuration applied successfully."
    Write-Host "Backup state saved to: $($StateInfo.StateFilePath)"
    foreach ($setting in $heterogeneousSettings) {
        Write-Host ("Resolved {0} => {1} [{2}={3}]" -f $setting.Name, $setting.Guid, $setting.MatchedBy, $setting.MatchedValue)
    }
}

function Invoke-RestoreMode {
    param([Parameter(Mandatory)][hashtable]$StateInfo)

    $existingSchemes = Get-ExistingSchemeGuids
    $stateFilePath = Get-ExistingStateFilePath -StateInfo $StateInfo

    if ($stateFilePath) {
        $state = Get-Content -Path $stateFilePath -Raw | ConvertFrom-Json

        foreach ($sleepSettingName in @('StandbyIdle', 'HybridSleep', 'HibernateIdle')) {
            $sleepSetting = $state.SleepSettings.$sleepSettingName
            Invoke-PowerCfgChange -Action 'Restore AC sleep setting value' -Target $sleepSetting.Guid -Arguments @('/setacvalueindex', $state.TargetSchemeGuid, $SleepSubgroupGuid, $sleepSetting.Guid, [string]$sleepSetting.Values.Ac)
            Invoke-PowerCfgChange -Action 'Restore DC sleep setting value' -Target $sleepSetting.Guid -Arguments @('/setdcvalueindex', $state.TargetSchemeGuid, $SleepSubgroupGuid, $sleepSetting.Guid, [string]$sleepSetting.Values.Dc)
        }

        foreach ($setting in $state.HeterogeneousSettings) {
            Invoke-PowerCfgChange -Action 'Restore AC processor scheduling value' -Target $setting.Guid -Arguments @('/setacvalueindex', $state.TargetSchemeGuid, $ProcessorSubgroupGuid, $setting.Guid, [string]$setting.Values.Ac)
            Invoke-PowerCfgChange -Action 'Restore DC processor scheduling value' -Target $setting.Guid -Arguments @('/setdcvalueindex', $state.TargetSchemeGuid, $ProcessorSubgroupGuid, $setting.Guid, [string]$setting.Values.Dc)
            Invoke-PowerCfgChange -Action 'Hide processor scheduling setting again' -Target $setting.Guid -Arguments @('-attributes', 'SUB_PROCESSOR', $setting.Guid, '+ATTRIB_HIDE')
        }

        $restoreSchemeGuid = $BalancedSchemeGuid
        if ($state.PreviousActiveSchemeGuid -and ($existingSchemes -contains $state.PreviousActiveSchemeGuid.ToLowerInvariant())) {
            $restoreSchemeGuid = $state.PreviousActiveSchemeGuid
        }
        elseif ($state.FallbackSchemeGuid -and ($existingSchemes -contains $state.FallbackSchemeGuid.ToLowerInvariant())) {
            $restoreSchemeGuid = $state.FallbackSchemeGuid
        }
        elseif ($existingSchemes -contains $HighPerformanceSchemeGuid) {
            $restoreSchemeGuid = $HighPerformanceSchemeGuid
        }

        Invoke-PowerCfgChange -Action 'Activate restored power plan' -Target $restoreSchemeGuid -Arguments @('/setactive', $restoreSchemeGuid)

        if ($PSCmdlet.ShouldProcess($stateFilePath, 'Delete backup state after successful restore')) {
            Remove-StateArtifacts -StateFilePath $stateFilePath
        }

        Write-Host "Power settings restored from backup state successfully."
        Write-Host "Re-activated scheme: $restoreSchemeGuid"
        return
    }

    $displayNames = Get-HeterogeneousDisplayNames
    $processorQueryText = Invoke-PowerCfgQuery -Arguments @('/qh', 'SCHEME_CURRENT', 'SUB_PROCESSOR')
    $resolvedThreadSetting = Resolve-HeterogeneousSetting -QueryText $processorQueryText -Name 'HeterogeneousThreadSchedulingPolicy' -LocalizedDisplayNames $displayNames.Thread -Alias 'SCHEDPOLICY'
    $resolvedShortThreadSetting = Resolve-HeterogeneousSetting -QueryText $processorQueryText -Name 'HeterogeneousShortRunningThreadSchedulingPolicy' -LocalizedDisplayNames $displayNames.ShortThread -Alias 'SHORTSCHEDPOLICY'

    foreach ($setting in @($resolvedThreadSetting, $resolvedShortThreadSetting)) {
        Invoke-PowerCfgChange -Action 'Hide processor scheduling setting again' -Target $setting.Guid -Arguments @('-attributes', 'SUB_PROCESSOR', $setting.Guid, '+ATTRIB_HIDE')
    }

    if ($existingSchemes -notcontains $BalancedSchemeGuid) {
        throw "No backup state file was found and the built-in Balanced scheme ($BalancedSchemeGuid) is not available on this machine."
    }

    Invoke-PowerCfgChange -Action 'Activate Balanced power plan fallback' -Target $BalancedSchemeGuid -Arguments @('/setactive', $BalancedSchemeGuid)
    Write-Warning "No backup state file was found. The script hid the exposed processor settings again and switched the active plan to Balanced."
}

function Read-DesiredAction {
    while ($true) {
        Write-Host ''
        Write-Host '请选择操作 / Choose an action:'
        Write-Host '  1) 启用高性能模式 / Apply high performance mode'
        Write-Host '  2) 恢复默认设置 / Restore default settings'
        Write-Host '  Q) 退出 / Exit'

        $choiceInput = Read-Host '请输入 1 / 2 / Q'
        if ($null -eq $choiceInput) {
            return $null
        }

        $choice = $choiceInput.Trim()
        switch -Regex ($choice) {
            '^(1|a|apply)$' { return 'Apply' }
            '^(2|r|restore)$' { return 'Restore' }
            '^(q|quit|exit)$' { return $null }
            default { Write-Warning '无效输入 / Invalid choice. Please try again.' }
        }
    }
}

function Resolve-DesiredAction {
    param([string]$RequestedAction)

    if ([string]::IsNullOrWhiteSpace($RequestedAction)) {
        return $null
    }

    switch -Regex ($RequestedAction.Trim()) {
        '^(apply)$' { return 'Apply' }
        '^(restore)$' { return 'Restore' }
        default {
            throw "Unsupported action '$RequestedAction'. Allowed values: Apply, Restore."
        }
    }
}

Assert-Administrator
$stateInfo = Get-StateInfo
$resolvedAction = Resolve-DesiredAction -RequestedAction $CpuHighPerformanceAction

if (-not $resolvedAction) {
    $resolvedAction = Read-DesiredAction
    if (-not $resolvedAction) {
        Write-Host 'Operation cancelled.'
        return
    }
}

switch ($resolvedAction) {
    'Apply' { Invoke-ApplyMode -StateInfo $stateInfo }
    'Restore' { Invoke-RestoreMode -StateInfo $stateInfo }
    default { throw "Unsupported action '$resolvedAction'." }
}
