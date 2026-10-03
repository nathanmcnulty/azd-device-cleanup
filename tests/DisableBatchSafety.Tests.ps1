Describe 'Disable batch safety limit' {
    BeforeAll {
        # The runbook's final statement starts a live job. Load only its function definitions.
        $runbookPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'runbooks/DeviceCleanup.ps1'
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($runbookPath, [ref] $tokens, [ref] $parseErrors)
        if ($parseErrors.Count -gt 0) { throw ($parseErrors | Out-String) }
        foreach ($definition in @($ast.EndBlock.Statements | Where-Object { $_ -is [System.Management.Automation.Language.FunctionDefinitionAst] })) {
            . ([scriptblock]::Create($definition.Extent.Text))
        }
    }

    BeforeEach {
        $script:overrideCount = $null
        $script:disableEnabled = $true
        $script:maxDisableCount = 1
        Mock Get-DeviceCleanupSettings {
            [pscustomobject]@{
                EnvironmentName = 'offline-test'; SubscriptionId = '00000000-0000-0000-0000-000000000001'
                ResourceGroupName = 'rg-offline'; AutomationAccountName = 'aa-offline'; AutomationRunbookName = 'cleanup'
                DisableAfterDays = 30; DeleteAfterDays = 90; MaxDisableCount = $script:maxDisableCount; MaxDeleteCount = 10
                DisableBatchOverrideCount = $script:overrideCount
                DisableEnabled = $script:disableEnabled; DeleteEnabled = $false; ExclusionGroupId = $null
                IntuneCheckInAttributeNumber = 0; DefenderCheckInAttributeNumber = 0
                AdvancedHuntingEnabled = $false; AdvancedHuntingLookbackDays = 30
                NotificationsEnabled = $false
            }
        }
        Mock Get-EntraDevices {
            [pscustomobject]@{ id = 'device-A'; deviceId = 'registration-A'; displayName = 'Device A' }
            [pscustomobject]@{ id = 'device-B'; deviceId = 'registration-B'; displayName = 'Device B' }
        }
        Mock Sync-DeviceCheckInAttributes { [pscustomobject]@{ UpdatedCount = 0; RestrictedManagementUnitSkippedCount = 0; DeviceCount = 2 } }
        Mock Get-DeviceCheckInData { [pscustomobject]@{ Heartbeat = 'offline-test' } }
        Mock Get-DeviceLifecycleAction {
            [pscustomobject]@{ Action = 'Disable'; InactiveDays = 100; HeartbeatSource = 'Entra'; HeartbeatTimestamp = '2026-01-01T00:00:00Z' }
        }
        Mock Disable-EntraDevice {}
        Mock Remove-EntraDevice {}
        Mock Invoke-DeviceCleanupNotification {}
    }

    It 'blocks an above-limit enabled batch before disabling or deleting any device' {
        { Invoke-DeviceCleanupJob } | Should -Throw '*Safety threshold reached*2 disable candidates*'
        Should -Invoke Disable-EntraDevice -Times 0 -Exactly
        Should -Invoke Remove-EntraDevice -Times 0 -Exactly
    }

    It 'allows only a one-off override matching the exact candidate count' {
        $script:overrideCount = 2
        $summary = @(Invoke-DeviceCleanupJob) | Select-Object -Last 1
        $summary.status | Should -Be 'Succeeded'
        $summary.counts.disabledDevices | Should -Be 2
        Should -Invoke Disable-EntraDevice -Times 2 -Exactly
    }

    It 'allows a batch at the configured limit without an override' {
        $script:maxDisableCount = 2
        $summary = @(Invoke-DeviceCleanupJob) | Select-Object -Last 1
        $summary.counts.disabledDevices | Should -Be 2
        Should -Invoke Disable-EntraDevice -Times 2 -Exactly
    }

    It 'rejects a stale or mismatched override before lifecycle actions' {
        $script:overrideCount = 3
        { Invoke-DeviceCleanupJob } | Should -Throw '*must equal the above-limit disable candidate count*'
        Should -Invoke Disable-EntraDevice -Times 0 -Exactly
    }

    It 'reports a large dry-run batch without an override or disabling devices' {
        $script:disableEnabled = $false
        $summary = @(Invoke-DeviceCleanupJob) | Select-Object -Last 1
        $summary.counts.dryRunDisableCandidates | Should -Be 2
        Should -Invoke Disable-EntraDevice -Times 0 -Exactly
    }

    It 'rejects a stale override even when no devices need action' {
        Mock Get-EntraDevices {}
        $script:overrideCount = 2
        { Invoke-DeviceCleanupJob } | Should -Throw '*must equal the above-limit disable candidate count*'
        Should -Invoke Disable-EntraDevice -Times 0 -Exactly
    }

    It 'rejects a non-positive disable cap even when no devices need action' {
        Mock Get-EntraDevices {}
        $script:maxDisableCount = 0
        { Invoke-DeviceCleanupJob } | Should -Throw '*MaxDisableCount must be at least 1*'
        Should -Invoke Disable-EntraDevice -Times 0 -Exactly
    }
}
