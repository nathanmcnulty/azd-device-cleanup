Describe 'Preflight Automation job does not mutate devices' {
    BeforeAll {
        $repoRoot = Split-Path $PSScriptRoot -Parent
        foreach ($scriptPath in @('scripts/preflight.ps1', 'runbooks/DeviceCleanup.ps1')) {
            $tokens = $null
            $parseErrors = $null
            $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot $scriptPath), [ref] $tokens, [ref] $parseErrors)
            if ($parseErrors.Count -gt 0) { throw ($parseErrors | Out-String) }
            foreach ($definition in @($ast.EndBlock.Statements | Where-Object { $_ -is [System.Management.Automation.Language.FunctionDefinitionAst] })) {
                . ([scriptblock]::Create($definition.Extent.Text))
            }
        }
        function Start-AzAutomationRunbook {
            param($ResourceGroupName, $AutomationAccountName, $Name, $Parameters)
            throw 'A live Automation job must not run in an offline test.'
        }
    }

    BeforeEach {
        $script:submittedParameters = $null
        Mock Start-AzAutomationRunbook {
            $script:submittedParameters = $Parameters
            [pscustomobject]@{ JobId = 'offline-job' }
        }
    }

    It 'passes explicit zero attribute slots and false lifecycle flags to the published runbook' {
        $job = Start-PreflightAutomationJob -ResourceGroupName 'rg-offline' -AutomationAccountName 'aa-offline' -RunbookName 'cleanup' -AdvancedHuntingEnabled $true -LogicAppNotificationsEnabled $true
        $job.JobId | Should -Be 'offline-job'
        Should -Invoke Start-AzAutomationRunbook -Times 1 -Exactly -ParameterFilter { $ResourceGroupName -eq 'rg-offline' -and $AutomationAccountName -eq 'aa-offline' -and $Name -eq 'cleanup' }
        $parameters = $script:submittedParameters
        $parameters.DisableEnabled | Should -Be 'false'
        $parameters.DeleteEnabled | Should -Be 'false'
        $parameters.IntuneCheckInAttributeNumber | Should -Be '0'
        $parameters.PrimaryArchiveUserCollectionEnabled | Should -Be 'false'
        $parameters.DefenderCheckInAttributeNumber | Should -Be '0'
        $parameters.AdvancedHuntingEnabled | Should -Be 'true'
        $parameters.NotifyOnNoAction | Should -Be 'true'
        (Get-ExtensionAttributeNumberInput -Name 'IntuneCheckInAttributeNumber' -Value $parameters.IntuneCheckInAttributeNumber) | Should -Be 0
        (Get-ExtensionAttributeNumberInput -Name 'DefenderCheckInAttributeNumber' -Value $parameters.DefenderCheckInAttributeNumber) | Should -Be 0

    }

    It 'keeps changed Intune and Defender values dry while planning disable and delete candidates' {
        Set-StrictMode -Version Latest
        $null = Start-PreflightAutomationJob -ResourceGroupName 'rg-offline' -AutomationAccountName 'aa-offline' -RunbookName 'cleanup' -AdvancedHuntingEnabled $false -LogicAppNotificationsEnabled $false
        $parameters = $script:submittedParameters
        Mock Get-DeviceCleanupSettings {
            [pscustomobject]@{
                EnvironmentName = 'offline-test'; SubscriptionId = '00000000-0000-0000-0000-000000000001'
                ResourceGroupName = 'rg-offline'; AutomationAccountName = 'aa-offline'; AutomationRunbookName = 'cleanup'
                DisableAfterDays = 30; DeleteAfterDays = 90; MaxDisableCount = 10; MaxDeleteCount = 10
                DisableBatchOverrideCount = $null; ExclusionGroupId = $null; SecretPrefix = 'archive'
                DisableEnabled = Get-BooleanInput -Name 'DisableEnabled' -Value $parameters.DisableEnabled
                DeleteEnabled = Get-BooleanInput -Name 'DeleteEnabled' -Value $parameters.DeleteEnabled
                IntuneCheckInAttributeNumber = Get-ExtensionAttributeNumberInput -Name 'IntuneCheckInAttributeNumber' -Value $parameters.IntuneCheckInAttributeNumber
                DefenderCheckInAttributeNumber = Get-ExtensionAttributeNumberInput -Name 'DefenderCheckInAttributeNumber' -Value $parameters.DefenderCheckInAttributeNumber
                AdvancedHuntingEnabled = $false; AdvancedHuntingLookbackDays = 30; NotificationsEnabled = $false
            }
        }
        Mock Get-EntraDevices {
            [pscustomobject]@{ id = 'device-A'; deviceId = 'registration-A'; displayName = 'Device A'; extensionAttributes = @{ extensionAttribute14 = 'old'; extensionAttribute15 = 'old' } }
            [pscustomobject]@{ id = 'device-B'; deviceId = 'registration-B'; displayName = 'Device B'; extensionAttributes = @{ extensionAttribute14 = 'old'; extensionAttribute15 = 'old' } }
        }
        Mock Get-DeviceCheckInData {
            [pscustomobject]@{ Intune = @{ AttributeValue = 'new' }; DefenderForEndpoint = @{ AttributeValue = 'new' }; EffectiveHeartbeat = @{ Source = 'Entra'; Timestamp = '2026-01-01T00:00:00Z' } }
        }
        Mock Get-DeviceLifecycleAction {
            if ($Device.id -eq 'device-A') { return [pscustomobject]@{ Action = 'Disable'; InactiveDays = 100; HeartbeatSource = 'Entra'; HeartbeatTimestamp = '2026-01-01T00:00:00Z' } }
            return [pscustomobject]@{ Action = 'Delete'; InactiveDays = 140; HeartbeatSource = 'Entra'; HeartbeatTimestamp = '2026-01-01T00:00:00Z' }
        }
        Mock Set-DeviceExtensionAttributes {}
        Mock Disable-EntraDevice {}
        Mock Remove-EntraDevice {}
        Mock Set-KeyVaultArchiveSecret {}
        Mock Get-IntuneManagedDevices { throw 'Intune should not be queried with slot 0' }
        Mock Get-DefenderMachines { throw 'Defender should not be queried with slot 0' }
        Mock Invoke-DeviceCleanupNotification {}

        $summary = @(Invoke-DeviceCleanupJob) | Select-Object -Last 1
        $summary.status | Should -Be 'Succeeded'
        $summary.counts.dryRunDisableCandidates | Should -Be 1
        $summary.counts.dryRunDeleteCandidates | Should -Be 1
        $summary.counts.intuneDefenderAttributeUpdates | Should -Be 0
        $summary.counts.restrictedManagementUnitSkipped | Should -Be 0
        Should -Invoke Set-DeviceExtensionAttributes -Times 0 -Exactly
        Should -Invoke Disable-EntraDevice -Times 0 -Exactly
        Should -Invoke Remove-EntraDevice -Times 0 -Exactly
        Should -Invoke Set-KeyVaultArchiveSecret -Times 0 -Exactly
        Should -Invoke Get-IntuneManagedDevices -Times 0 -Exactly
        Should -Invoke Get-DefenderMachines -Times 0 -Exactly
    }
}
