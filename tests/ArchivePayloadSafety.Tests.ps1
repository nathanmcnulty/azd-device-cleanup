Describe 'Archive payload size safety' {
    BeforeAll {
        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'
        $runbookPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'runbooks/DeviceCleanup.ps1'
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($runbookPath, [ref] $tokens, [ref] $parseErrors)
        if ($parseErrors.Count -gt 0) { throw ($parseErrors | Out-String) }
        foreach ($definition in @($ast.EndBlock.Statements | Where-Object { $_ -is [System.Management.Automation.Language.FunctionDefinitionAst] })) {
            . ([scriptblock]::Create($definition.Extent.Text))
        }
        $script:GraphResourceUrl = 'https://graph.microsoft.com/'
        $script:KeyVaultResourceUrl = 'https://vault.azure.net'

        function New-PayloadAtUtf8Size {
            param([Parameter(Mandatory = $true)][int] $TargetBytes)

            $emptyJson = ([ordered]@{ data = '' } | ConvertTo-Json -Depth 20 -Compress)
            $emptyBytes = [Text.Encoding]::UTF8.GetByteCount($emptyJson)
            $remaining = $TargetBytes - $emptyBytes
            for ($count = [Math]::Max(0, [Math]::Floor($remaining / 2) - 2); $count -le ($remaining / 2 + 2); $count++) {
                for ($asciiCount = 0; $asciiCount -le 3; $asciiCount++) {
                    $payload = [ordered]@{ data = ('é' * $count) + ('a' * $asciiCount) }
                    $json = $payload | ConvertTo-Json -Depth 20 -Compress
                    if ([Text.Encoding]::UTF8.GetByteCount($json) -eq $TargetBytes) { return $payload }
                }
            }

            throw "Unable to construct a payload of exactly $TargetBytes UTF-8 bytes."
        }
    }

    BeforeEach {
        $script:tokenCalls = 0
        $script:putCalls = 0
        $script:lastPutBody = $null
        $script:lastPutUri = $null
        $script:lastTokenResource = $null
        Mock Get-ManagedIdentityToken {
            param($ResourceUrl)
            $script:tokenCalls++
            $script:lastTokenResource = $ResourceUrl
            return 'synthetic-token'
        }
        Mock Invoke-JsonRestMethod {
            param($Method, $Uri, $Body)
            $script:putCalls++
            $script:lastPutUri = $Uri
            $script:lastPutBody = $Body
            return [pscustomobject]@{ id = "https://archive-vault.vault.azure.net/secrets/archive-device/0123456789abcdef0123456789abcdef" }
        }
    }

    It 'accepts exactly 24000 UTF-8 bytes and writes one archive secret' {
        $payload = New-PayloadAtUtf8Size -TargetBytes 24000

        Set-KeyVaultArchiveSecret -VaultName 'archive-vault' -SecretName 'archive-device' -Payload $payload -Tags @{}

        $script:tokenCalls | Should -Be 1
        $script:putCalls | Should -Be 1
        $script:lastTokenResource | Should -Be 'https://vault.azure.net'
        $script:lastPutUri | Should -Be 'https://archive-vault.vault.azure.net/secrets/archive-device?api-version=7.4'
        [Text.Encoding]::UTF8.GetByteCount([string] $script:lastPutBody.value) | Should -Be 24000
        [string] $script:lastPutBody.value | Should -Match 'é'
    }

    It 'rejects 24001 UTF-8 bytes before token acquisition or PUT' {
        $payload = New-PayloadAtUtf8Size -TargetBytes 24001

        { Set-KeyVaultArchiveSecret -VaultName 'archive-vault' -SecretName 'archive-device' -Payload $payload -Tags @{} } |
            Should -Throw '*too large*'

        $script:tokenCalls | Should -Be 0
        $script:putCalls | Should -Be 0
    }

    It 'uses UTF-8 bytes for multibyte content rather than character count' {
        $payload = [ordered]@{ data = 'é' * 12000 }
        $json = $payload | ConvertTo-Json -Depth 20 -Compress
        $utf8Bytes = [Text.Encoding]::UTF8.GetByteCount($json)
        $utf8Bytes | Should -BeGreaterThan $json.Length
        $utf8Bytes | Should -BeGreaterThan 24000

        { Set-KeyVaultArchiveSecret -VaultName 'archive-vault' -SecretName 'archive-device' -Payload $payload -Tags @{} } |
            Should -Throw '*too large*'
        $script:tokenCalls | Should -Be 0
        $script:putCalls | Should -Be 0
    }

    It 'refuses an oversized real Save-DeviceArchive payload before Entra DELETE' {
        $settings = [pscustomobject]@{
            VaultName = 'archive-vault'; SecretPrefix = 'archive'; DisableAfterDays = 30; DeleteAfterDays = 90
            DisableEnabled = $false; DeleteEnabled = $true; IntuneCheckInAttributeNumber = 0
            DefenderCheckInAttributeNumber = 0; AdvancedHuntingEnabled = $true; NotificationsEnabled = $false
        }
        $device = [pscustomobject]@{
            id = 'entra-device'; deviceId = 'registration-device'; displayName = 'Synthetic device'
            accountEnabled = $false; operatingSystem = 'Windows'; operatingSystemVersion = '11'
            trustType = 'AzureAd'; approximateLastSignInDateTime = '2026-01-01T00:00:00Z'
        }
        $candidate = [pscustomobject]@{
            Device = $device; Action = 'Delete'; InactiveDays = 120; HeartbeatSource = 'Entra'
            HeartbeatTimestamp = '2026-01-01T00:00:00Z'
            CheckInData = [pscustomobject]@{
                Intune = $null; DefenderForEndpoint = $null
                EffectiveHeartbeat = [pscustomobject]@{ State = 'Stale'; Timestamp = '2026-01-01T00:00:00Z'; Source = 'Entra'; InactiveDays = 120 }
                AdvancedHuntingRecords = @([pscustomobject]@{
                    SourceTable = 'Synthetic'; HeartbeatTimestamp = '2026-01-01T00:00:00Z'; DeviceName = 'Synthetic device'
                    Record = [ordered]@{ padding = 'é' * 12000 }
                })
            }
        }

        Mock Get-LapsArchive { return $null }
        Mock Get-BitLockerArchive { return [pscustomobject]@{ id = 'synthetic-bitlocker'; key = 'synthetic-key' } }
        Mock Remove-EntraDevice {}

        { Save-DeviceArchive -Device $device -Settings $settings -CleanupRunId 'synthetic-run' -Candidate $candidate -CheckInData $candidate.CheckInData } |
            Should -Throw '*too large*'
        Should -Invoke Remove-EntraDevice -Times 0 -Exactly
        $script:tokenCalls | Should -Be 0
        $script:putCalls | Should -Be 0
    }

    It 'records archive failure and never deletes when the cleanup job reaches the real writer' {
        $device = [pscustomobject]@{
            id = 'entra-device'; deviceId = 'registration-device'; displayName = 'Synthetic device'
            accountEnabled = $false; operatingSystem = 'Windows'; operatingSystemVersion = '11'
            trustType = 'AzureAd'; approximateLastSignInDateTime = '2026-01-01T00:00:00Z'
        }
        $checkInData = [pscustomobject]@{
            Intune = $null; DefenderForEndpoint = $null
            EffectiveHeartbeat = [pscustomobject]@{ State = 'Stale'; Timestamp = '2026-01-01T00:00:00Z'; Source = 'Entra'; InactiveDays = 120 }
            AdvancedHuntingRecords = @([pscustomobject]@{
                SourceTable = 'Synthetic'; HeartbeatTimestamp = '2026-01-01T00:00:00Z'; DeviceName = 'Synthetic device'
                Record = [ordered]@{ padding = 'é' * 12000 }
            })
        }

        Mock Get-DeviceCleanupSettings {
            [pscustomobject]@{
                VaultName = 'archive-vault'; EnvironmentName = 'offline-test'; SubscriptionId = '00000000-0000-0000-0000-000000000001'
                ResourceGroupName = 'rg-offline'; AutomationAccountName = 'aa-offline'; AutomationRunbookName = 'cleanup'
                DisableAfterDays = 30; DeleteAfterDays = 90; MaxDisableCount = 10; MaxDeleteCount = 10
                DisableBatchOverrideCount = $null; DisableEnabled = $false; DeleteEnabled = $true
                ExclusionGroupId = $null; SecretPrefix = 'archive'; IntuneCheckInAttributeNumber = 0
                DefenderCheckInAttributeNumber = 0; AdvancedHuntingEnabled = $false; AdvancedHuntingLookbackDays = 30
                NotificationsEnabled = $false
            }
        }
        Mock Get-EntraDevices { return $device }
        Mock Sync-DeviceCheckInAttributes { [pscustomobject]@{ UpdatedCount = 0; RestrictedManagementUnitSkippedCount = 0; DeviceCount = 1 } }
        Mock Get-DeviceCheckInData { return $checkInData }
        Mock Get-DeviceLifecycleAction {
            [pscustomobject]@{ Action = 'Delete'; InactiveDays = 120; HeartbeatSource = 'Entra'; HeartbeatTimestamp = '2026-01-01T00:00:00Z' }
        }
        Mock Get-LapsArchive { return $null }
        Mock Get-BitLockerArchive { return [pscustomobject]@{ id = 'synthetic-bitlocker'; key = 'synthetic-key' } }
        Mock Remove-EntraDevice {}
        Mock Invoke-DeviceCleanupNotification {}

        $summary = @(Invoke-DeviceCleanupJob) | Select-Object -Last 1

        $summary.status | Should -Be 'PartiallySucceeded'
        $summary.counts.actionFailures | Should -Be 1
        $summary.counts.archivedDeletedDevices | Should -Be 0
        $summary.results.failedActions[0].action | Should -Be 'Archive'
        $summary.results.failedActions[0].reason | Should -Be 'ArchiveFailed'
        $summary.results.failedActions[0].message | Should -Match 'too large for Azure Key Vault secret storage'
        $summary.results.failedActions[0].message | Should -Not -Match 'synthetic-key|é'
        Should -Invoke Remove-EntraDevice -Times 0 -Exactly
        $script:tokenCalls | Should -Be 0
        $script:putCalls | Should -Be 0
    }
}
