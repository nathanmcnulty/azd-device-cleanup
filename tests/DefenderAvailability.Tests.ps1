Describe 'Defender machine inventory failure safety' {
    BeforeAll {
        # Load only the runbook's function definitions. Its final statement runs
        # the live job, which must never execute in an offline test.
        $runbookPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'runbooks/DeviceCleanup.ps1'
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($runbookPath, [ref] $tokens, [ref] $parseErrors)
        if ($parseErrors.Count -gt 0) { throw ($parseErrors | Out-String) }
        foreach ($definition in @($ast.EndBlock.Statements | Where-Object { $_ -is [System.Management.Automation.Language.FunctionDefinitionAst] })) {
            . ([scriptblock]::Create($definition.Extent.Text))
        }
        $script:DefenderResourceUrl = 'https://api.securitycenter.microsoft.com'
        $script:DefenderApiUrl = 'https://api.security.microsoft.com'
    }

    BeforeEach {
        Mock Get-ManagedIdentityToken { 'offline-test-token' }
        Mock Invoke-JsonRestMethod { throw 'Defender machines endpoint returned HTTP 404' }
        Mock Get-HttpStatusCode { 404 }
    }

    It 'propagates a first-page 404 instead of returning an empty healthy inventory' {
        { Get-DefenderMachines } | Should -Throw '*HTTP 404*'
        Should -Invoke Invoke-JsonRestMethod -Times 1 -Exactly
        Should -Invoke Get-HttpStatusCode -Times 0 -Exactly
    }

    It 'marks Defender unavailable and skips device actions when hunting is disabled' {
        Mock Get-DeviceCleanupSettings {
            [pscustomobject]@{
                EnvironmentName = 'offline-test'; SubscriptionId = '00000000-0000-0000-0000-000000000001'
                ResourceGroupName = 'rg-offline'; AutomationAccountName = 'aa-offline'; AutomationRunbookName = 'cleanup'
                DisableAfterDays = 30; DeleteAfterDays = 90; MaxDisableCount = 10; MaxDeleteCount = 10; DisableBatchOverrideCount = $null
                DisableEnabled = $true; DeleteEnabled = $true; ExclusionGroupId = $null
                IntuneCheckInAttributeNumber = 0; DefenderCheckInAttributeNumber = 1
                AdvancedHuntingEnabled = $false; AdvancedHuntingLookbackDays = 30
                NotificationsEnabled = $false
            }
        }
        Mock Get-EntraDevices { [pscustomobject]@{ id = 'device-1'; deviceId = 'device-id-1'; displayName = 'Offline Device' } }
        Mock Sync-DeviceCheckInAttributes {
            [pscustomobject]@{ UpdatedCount = 0; RestrictedManagementUnitSkippedCount = 0; DeviceCount = 1 }
        }
        Mock Invoke-DeviceCleanupNotification {}
        Mock Get-DeviceLifecycleAction { throw 'Lifecycle selection must not run without Defender data' }

        $summary = @(Invoke-DeviceCleanupJob) | Select-Object -Last 1

        $summary.status | Should -Be 'NoAction'
        $summary.defenderApi.available | Should -BeFalse
        $summary.defenderApi.failure | Should -Match 'HTTP 404'
        $summary.counts.disableCandidates | Should -Be 0
        $summary.counts.deleteCandidates | Should -Be 0
        Should -Invoke Get-DeviceLifecycleAction -Times 0 -Exactly
        Should -Invoke Invoke-DeviceCleanupNotification -Times 1 -Exactly
    }
}
