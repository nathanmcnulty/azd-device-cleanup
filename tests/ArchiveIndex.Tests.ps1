Describe 'Version-bound archive index writer' {
    BeforeAll {
        Set-StrictMode -Version Latest
        $runbookPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'runbooks/DeviceCleanup.ps1'
        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($runbookPath, [ref]$tokens, [ref]$errors)
        if ($errors.Count) { throw ($errors | Out-String) }
        foreach ($definition in @($ast.EndBlock.Statements | Where-Object { $_ -is [System.Management.Automation.Language.FunctionDefinitionAst] })) {
            . ([scriptblock]::Create($definition.Extent.Text))
        }
        $script:GraphResourceUrl = 'https://graph.microsoft.com/'
        $script:KeyVaultResourceUrl = 'https://vault.azure.net'
        $script:ArchiveIndexKind = 'device-archive-index'
        $script:ArchiveIndexSchemaVersion = '1.0'
        $script:ArchiveIndexContentType = 'application/vnd.azd-device-cleanup.archive-index+json;v=1'
        $script:ArchiveIndexMaxBytes = 8192
    }

    BeforeEach {
        $script:puts = @()
        $script:archiveVersion = '11111111111111111111111111111111'
        $script:indexVersion = 'aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa'
        Mock Get-LapsArchive { $null }
        Mock Get-BitLockerArchive { @() }
        Mock Get-ManagedIdentityToken { 'offline-token' }
        Mock Invoke-JsonRestMethod {
            param($Method,$Uri,$Body)
            $script:puts += [pscustomobject]@{ Uri=$Uri; Body=$Body }
            $name = ([Uri]$Uri).AbsolutePath.Split('/')[-1]
            $version = if ($name.StartsWith('device-archive-index-')) { $script:indexVersion } else { $script:archiveVersion }
            [pscustomobject]@{ id = "https://archive-vault.vault.azure.net/secrets/$name/$version"; value='MUST_NOT_ESCAPE' }
        }
        $script:device = [pscustomobject]@{
            id='AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA'; deviceId='BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB'; displayName='LT-100'
            accountEnabled=$false; operatingSystem='Windows'; operatingSystemVersion='11'; trustType='AzureAd'
            approximateLastSignInDateTime='2026-01-01T00:00:00Z'
        }
        $script:settings = [pscustomobject]@{ VaultName='archive-vault'; SecretPrefix='archive'; PrimaryArchiveUserCollectionEnabled=$false }
        $script:checkIn = [pscustomobject]@{
            Intune=$null; DefenderForEndpoint=$null; AdvancedHuntingRecords=@()
            EffectiveHeartbeat=[pscustomobject]@{State='Stale';Timestamp='2026-01-01T00:00:00Z';Source='Entra';InactiveDays=120}
        }
        $script:candidate = [pscustomobject]@{Action='Delete';InactiveDays=120;HeartbeatSource='Entra';HeartbeatTimestamp='2026-01-01T00:00:00Z'}
    }

    It 'writes archive then a deterministic version-bound index without collecting a primary user' {
        Mock Get-PrimaryArchiveUser { [pscustomobject]@{State='Disabled';Id=$null;UserPrincipalName=$null} }
        $result = Save-DeviceArchive -Device $script:device -Settings $script:settings -CleanupRunId 'run-1' -Candidate $script:candidate -CheckInData $script:checkIn

        $script:puts.Count | Should -Be 2
        $script:puts[0].Uri | Should -Match '/secrets/archive-lt-100-'
        $archiveId = "https://archive-vault.vault.azure.net/secrets/$($result.SecretName)/$script:archiveVersion"
        $script:puts[1].Uri | Should -Be "https://archive-vault.vault.azure.net/secrets/$(Get-ArchiveIndexName -ArchiveSecretId $archiveId)?api-version=7.4"
        $index = $script:puts[1].Body.value | ConvertFrom-Json
        ($script:puts[1].Body.value | Test-Json -SchemaFile (Join-Path (Split-Path $PSScriptRoot -Parent) 'schemas/device-archive-index.schema.json')) | Should -BeTrue
        $index.archiveSecretVersion | Should -Be $script:archiveVersion
        $index.archiveSecretId | Should -Be $archiveId
        $index.primaryUserState | Should -Be 'Disabled'
        $script:puts[1].Body.tags.ContainsKey('primaryUserPrincipalName') | Should -BeFalse
        $script:puts[1].Body.tags.Count | Should -BeLessOrEqual 15
        Should -Invoke Get-PrimaryArchiveUser -Times 1 -Exactly -ParameterFilter { -not $Enabled }
    }

    It 'rejects noncanonical indexed identity and archive URI shapes in the published schema' {
        Mock Get-PrimaryArchiveUser { [pscustomobject]@{State='Disabled';Id=$null;UserPrincipalName=$null} }
        $null=Save-DeviceArchive -Device $script:device -Settings $script:settings -CleanupRunId 'run-1' -Candidate $script:candidate -CheckInData $script:checkIn
        $schema=Join-Path (Split-Path $PSScriptRoot -Parent) 'schemas/device-archive-index.schema.json'
        $payload=$script:puts[1].Body.value|ConvertFrom-Json
        $payload.entraObjectId='../users'
        ($payload|ConvertTo-Json -Depth 5 -Compress|Test-Json -SchemaFile $schema -ErrorAction SilentlyContinue) | Should -BeFalse
        $payload.entraObjectId='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
        $payload.archiveSecretId="https://unexpected@archive-vault.vault.azure.net/secrets/$($payload.archiveSecretName)/$($payload.archiveSecretVersion)"
        ($payload|ConvertTo-Json -Depth 5 -Compress|Test-Json -SchemaFile $schema -ErrorAction SilentlyContinue) | Should -BeFalse
    }

    It 'fails closed with safe correlation when a hostile device identity reaches post-archive validation' {
        $script:device.deviceId='../users'
        Mock Get-PrimaryArchiveUser { [pscustomobject]@{State='Disabled';Id=$null;UserPrincipalName=$null} }
        $message=try{Save-DeviceArchive -Device $script:device -Settings $script:settings -CleanupRunId 'run-1' -Candidate $script:candidate -CheckInData $script:checkIn}catch{$_.Exception.Message}
        $message | Should -Match '^Archive index write failed after archive creation\.'
        $message | Should -Not -Match '\.\./users'
        $script:puts.Count | Should -Be 1
    }

    It 'returns only the validated version reference DTO from the low-level writer' {
        $reference = Set-KeyVaultArchiveSecret -VaultName 'archive-vault' -SecretName 'archive-device' -Payload @{ok=$true} -Tags @{}
        @($reference.PSObject.Properties.Name | Sort-Object) | Should -Be @('Id','SecretName','VaultName','Version')
        $reference.PSObject.Properties.Name | Should -Not -Contain 'value'
    }

    It 'rejects a tampered write response identity without echoing its body' {
        Mock Invoke-JsonRestMethod { [pscustomobject]@{ id='https://other.vault.azure.net/secrets/archive-device/11111111111111111111111111111111'; value='SECRET_SENTINEL' } }
        $message = try { Set-KeyVaultArchiveSecret -VaultName 'archive-vault' -SecretName 'archive-device' -Payload @{ok=$true} -Tags @{} } catch { $_.Exception.Message }
        $message | Should -Be 'Key Vault secret write returned an invalid version reference.'
        $message | Should -Not -Match 'SECRET_SENTINEL|other.vault'
    }

    It 'rejects write response UserInfo before canonicalizing the version reference' {
        Mock Invoke-JsonRestMethod { [pscustomobject]@{ id='https://unexpected@archive-vault.vault.azure.net/secrets/archive-device/11111111111111111111111111111111'; value='SECRET_SENTINEL' } }
        $message = try { Set-KeyVaultArchiveSecret -VaultName 'archive-vault' -SecretName 'archive-device' -Payload @{ok=$true} -Tags @{} } catch { $_.Exception.Message }
        $message | Should -Be 'Key Vault secret write returned an invalid version reference.'
        $message | Should -Not -Match 'SECRET_SENTINEL|unexpected@'
    }

    It 'normalizes mixed-case vault input before deriving the canonical index pointer' {
        $reference = Set-KeyVaultArchiveSecret -VaultName 'ARCHIVE-VAULT' -SecretName 'archive-device' -Payload @{ok=$true} -Tags @{}
        $reference.VaultName | Should -Be 'archive-vault'
        $reference.Id | Should -Be "https://archive-vault.vault.azure.net/secrets/archive-device/$script:archiveVersion"
        (Get-ArchiveIndexName $reference.Id) | Should -Be (Get-ArchiveIndexName "https://archive-vault.vault.azure.net/secrets/archive-device/$script:archiveVersion")
    }

    It 'derives distinct index names for concurrent versions of the same archive name' {
        $one = Get-ArchiveIndexName 'https://archive-vault.vault.azure.net/secrets/archive-device/11111111111111111111111111111111'
        $two = Get-ArchiveIndexName 'https://archive-vault.vault.azure.net/secrets/archive-device/22222222222222222222222222222222'
        $one | Should -Not -Be $two
        $one | Should -Match '^device-archive-index-[a-f0-9]{64}$'
    }

    It 'retains only safe orphan correlation when pre-PUT index validation fails after the archive succeeds' {
        $script:device.displayName = 'x' * 257
        Mock Get-PrimaryArchiveUser { [pscustomobject]@{State='Disabled';Id=$null;UserPrincipalName=$null} }
        $message = try { Save-DeviceArchive -Device $script:device -Settings $script:settings -CleanupRunId 'run-1' -Candidate $script:candidate -CheckInData $script:checkIn } catch { $_.Exception.Message }
        $message | Should -Match "^Archive index write failed after archive creation\. ArchiveSecretName=.*; ArchiveVersion=$script:archiveVersion; CleanupRunId=run-1\.$"
        $message | Should -Not -Match 'displayName'
        $script:puts.Count | Should -Be 1
    }

    It 'sanitizes recovery-source errors before they can enter action output' {
        Mock Get-LapsArchive { throw 'raw LAPS SECRET_SENTINEL response' }
        $message = try { Save-DeviceArchive -Device $script:device -Settings $script:settings -CleanupRunId 'run-1' -Candidate $script:candidate -CheckInData $script:checkIn } catch { $_.Exception.Message }
        $message | Should -Be 'Archive recovery evidence collection failed.'
        $message | Should -Not -Match 'SECRET_SENTINEL|raw LAPS'
        $script:puts.Count | Should -Be 0
    }

    It 'blocks DELETE and reports only safe orphan correlation when the index write fails' {
        Mock Get-DeviceCleanupSettings {
            [pscustomobject]@{
                VaultName='archive-vault';SecretPrefix='archive';PrimaryArchiveUserCollectionEnabled=$false
                EnvironmentName='offline';SubscriptionId='sub';ResourceGroupName='rg';AutomationAccountName='aa';AutomationRunbookName='cleanup'
                DisableAfterDays=30;DeleteAfterDays=90;MaxDisableCount=10;MaxDeleteCount=10;DisableBatchOverrideCount=$null
                DisableEnabled=$false;DeleteEnabled=$true;ExclusionGroupId=$null;IntuneCheckInAttributeNumber=0;DefenderCheckInAttributeNumber=0
                AdvancedHuntingEnabled=$false;AdvancedHuntingLookbackDays=30;NotificationsEnabled=$false
            }
        }
        Mock Get-EntraDevices { $script:device }
        Mock Sync-DeviceCheckInAttributes { [pscustomobject]@{UpdatedCount=0;RestrictedManagementUnitSkippedCount=0;DeviceCount=1} }
        Mock Get-DeviceCheckInData { $script:checkIn }
        Mock Get-DeviceLifecycleAction { [pscustomobject]@{Action='Delete';InactiveDays=120;HeartbeatSource='Entra';HeartbeatTimestamp='2026-01-01T00:00:00Z'} }
        Mock Get-PrimaryArchiveUser { [pscustomobject]@{State='Disabled';Id=$null;UserPrincipalName=$null} }
        Mock Invoke-JsonRestMethod {
            param($Method,$Uri,$Body)
            $name=([Uri]$Uri).AbsolutePath.Split('/')[-1]
            if($name.StartsWith('device-archive-index-')){throw 'raw response SECRET_SENTINEL user@example.com'}
            [pscustomobject]@{id="https://archive-vault.vault.azure.net/secrets/$name/$script:archiveVersion"}
        }
        Mock Remove-EntraDevice {}
        Mock Invoke-DeviceCleanupNotification {}

        $summary=@(Invoke-DeviceCleanupJob)|Select-Object -Last 1
        $summary.counts.archivedDeletedDevices | Should -Be 0
        $summary.counts.actionFailures | Should -Be 1
        $summary.results.failedActions[0].message | Should -Match "ArchiveSecretName=.*ArchiveVersion=$script:archiveVersion; CleanupRunId="
        $summary.results.failedActions[0].message | Should -Not -Match 'SECRET_SENTINEL|user@example.com|raw response'
        Should -Invoke Remove-EntraDevice -Times 0 -Exactly
    }
}

Describe 'Bounded primary archive user collection' {
    BeforeAll {
        Set-StrictMode -Version Latest
        $runbookPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'runbooks/DeviceCleanup.ps1'
        $tokens=$null;$errors=$null
        $ast=[Management.Automation.Language.Parser]::ParseFile($runbookPath,[ref]$tokens,[ref]$errors)
        foreach($definition in @($ast.EndBlock.Statements|Where-Object{$_ -is [Management.Automation.Language.FunctionDefinitionAst]})){. ([scriptblock]::Create($definition.Extent.Text))}
        $script:GraphResourceUrl='https://graph.microsoft.com/'
    }
    BeforeEach {
        Mock Get-ManagedIdentityToken {'offline-token'}
        $script:calls=0
        $script:device=[pscustomobject]@{deviceId='AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA'}
    }

    It 'keeps the LAPS query marker outside the interpolated device id' {
        $script:lapsUri=$null
        Mock Get-GraphObject { param($Uri);$script:lapsUri=$Uri;$null }
        Get-LapsArchive -EntraObjectId 'entra-object-1' | Should -BeNullOrEmpty
        $script:lapsUri | Should -Be 'https://graph.microsoft.com/v1.0/directory/deviceLocalCredentials/entra-object-1?$select=credentials'
    }

    It 'performs zero Graph calls when disabled' {
        Mock Invoke-JsonRestMethod { $script:calls++; throw 'unexpected' }
        (Get-PrimaryArchiveUser -Device $script:device -Enabled $false).State | Should -Be 'Disabled'
        $script:calls | Should -Be 0
    }

    It 'resolves one exact managed-device relationship user' {
        Mock Invoke-JsonRestMethod {
            $script:calls++
            if ($Uri -match '/managedDevices\?') {
                return [pscustomobject]@{value=@([pscustomobject]@{id='cccccccc-cccc-cccc-cccc-cccccccccccc';azureADDeviceId='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'})}
            }
            [pscustomobject]@{value=@([pscustomobject]@{id='DDDDDDDD-DDDD-DDDD-DDDD-DDDDDDDDDDDD';userPrincipalName='User@One.Example'})}
        }
        $result=Get-PrimaryArchiveUser -Device $script:device -Enabled $true
        $result.State | Should -Be 'Single'
        $result.Id | Should -Be 'dddddddd-dddd-dddd-dddd-dddddddddddd'
        $result.UserPrincipalName | Should -Be 'user@one.example'
        $script:calls | Should -Be 2
    }

    It 'returns None for an empty user relationship' {
        Mock Invoke-JsonRestMethod {
            if ($Uri -match '/managedDevices\?') { return [pscustomobject]@{value=@([pscustomobject]@{id='cccccccc-cccc-cccc-cccc-cccccccccccc';azureADDeviceId='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'})} }
            [pscustomobject]@{value=@()}
        }
        (Get-PrimaryArchiveUser -Device $script:device -Enabled $true).State | Should -Be 'None'
    }

    It 'follows a valid bounded user page and retains the one distinct identity' {
        $script:calls=0
        Mock Invoke-JsonRestMethod {
            $script:calls++
            if ($Uri -match '/managedDevices\?') { return [pscustomobject]@{value=@([pscustomobject]@{id='cccccccc-cccc-cccc-cccc-cccccccccccc';azureADDeviceId='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'})} }
            if ($Uri -notmatch 'skiptoken') {
                return [pscustomobject]@{value=@();'@odata.nextLink'='https://graph.microsoft.com/v1.0/deviceManagement/managedDevices/cccccccc-cccc-cccc-cccc-cccccccccccc/users?$skiptoken=page2'}
            }
            [pscustomobject]@{value=@([pscustomobject]@{id='dddddddd-dddd-dddd-dddd-dddddddddddd';userPrincipalName=$null})}
        }
        $result=Get-PrimaryArchiveUser -Device $script:device -Enabled $true
        $result.State | Should -Be 'Single'
        $result.Id | Should -Be 'dddddddd-dddd-dddd-dddd-dddddddddddd'
        $result.UserPrincipalName | Should -BeNullOrEmpty
        $script:calls | Should -Be 3
    }

    It 'treats an omitted optional UPN as a single user with a null UPN' {
        Mock Invoke-JsonRestMethod {
            if ($Uri -match '/managedDevices\?') { return [pscustomobject]@{value=@([pscustomobject]@{id='cccccccc-cccc-cccc-cccc-cccccccccccc';azureADDeviceId='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'})} }
            [pscustomobject]@{value=@([pscustomobject]@{id='dddddddd-dddd-dddd-dddd-dddddddddddd'})}
        }
        $result=Get-PrimaryArchiveUser -Device $script:device -Enabled $true
        $result.State | Should -Be 'Single'
        $result.Id | Should -Be 'dddddddd-dddd-dddd-dddd-dddddddddddd'
        $result.UserPrincipalName | Should -BeNullOrEmpty
    }

    It 'rejects a path-hostile managed-device id before requesting its users route' {
        Mock Invoke-JsonRestMethod {
            [pscustomobject]@{value=@([pscustomobject]@{id='../users';azureADDeviceId='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'})}
        }
        (Get-PrimaryArchiveUser -Device $script:device -Enabled $true).State | Should -Be 'Conflict'
        Should -Invoke Invoke-JsonRestMethod -Times 1 -Exactly
    }

    It 'rejects ambiguous exact managed-device mappings before the users relationship' {
        Mock Invoke-JsonRestMethod {
            [pscustomobject]@{value=@(
                [pscustomobject]@{id='cccccccc-cccc-cccc-cccc-cccccccccccc';azureADDeviceId='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'},
                [pscustomobject]@{id='eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';azureADDeviceId='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'}
            )}
        }
        (Get-PrimaryArchiveUser -Device $script:device -Enabled $true).State | Should -Be 'MappingAmbiguous'
        Should -Invoke Invoke-JsonRestMethod -Times 1 -Exactly
    }

    It 'stops after two distinct relationship ids prove ambiguity' {
        Mock Invoke-JsonRestMethod {
            $script:calls++
            if ($Uri -match '/managedDevices\?') { return [pscustomobject]@{value=@([pscustomobject]@{id='cccccccc-cccc-cccc-cccc-cccccccccccc';azureADDeviceId='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'})} }
            [pscustomobject]@{value=@([pscustomobject]@{id='dddddddd-dddd-dddd-dddd-dddddddddddd';userPrincipalName='one@example.com'},[pscustomobject]@{id='eeeeeeee-eeee-eeee-eeee-eeeeeeeeeeee';userPrincipalName='two@example.com'});'@odata.nextLink'='https://graph.microsoft.com/v1.0/deviceManagement/managedDevices/cccccccc-cccc-cccc-cccc-cccccccccccc/users?$skiptoken=unused'}
        }
        (Get-PrimaryArchiveUser -Device $script:device -Enabled $true).State | Should -Be 'Multiple'
        $script:calls | Should -Be 2
    }

    It 'marks an overlong UPN as Conflict without retaining identity' {
        Mock Invoke-JsonRestMethod {
            if ($Uri -match '/managedDevices\?') { return [pscustomobject]@{value=@([pscustomobject]@{id='cccccccc-cccc-cccc-cccc-cccccccccccc';azureADDeviceId='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'})} }
            [pscustomobject]@{value=@([pscustomobject]@{id='dddddddd-dddd-dddd-dddd-dddddddddddd';userPrincipalName=('x'*321)})}
        }
        $result=Get-PrimaryArchiveUser -Device $script:device -Enabled $true
        $result.State | Should -Be 'Conflict'
        $result.Id | Should -BeNullOrEmpty
        $result.UserPrincipalName | Should -BeNullOrEmpty
    }
}
