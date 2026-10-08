Describe 'Version-bound archive index discovery and recovery' {
    BeforeAll {
        Set-StrictMode -Version Latest
        $readerPath=Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts/Get-ArchivedDevice.ps1'
        $tokens=$null;$errors=$null
        $ast=[Management.Automation.Language.Parser]::ParseFile($readerPath,[ref]$tokens,[ref]$errors)
        if($errors.Count){throw($errors|Out-String)}
        foreach($definition in @($ast.EndBlock.Statements|Where-Object{$_ -is [Management.Automation.Language.FunctionDefinitionAst]})){. ([scriptblock]::Create($definition.Extent.Text))}

        function New-IndexFixture {
            param([string]$Version='11111111111111111111111111111111',[string]$Upn='user@example.com',[string]$ArchiveName='archive-device')
            $archiveId="https://archive-vault.vault.azure.net/secrets/$ArchiveName/$Version"
            $indexName=Get-ArchiveIndexName $archiveId
            $payload=[ordered]@{
                schemaVersion='1.0';kind='device-archive-index';archiveSecretName=$ArchiveName;archiveSecretVersion=$Version;archiveSecretId=$archiveId
                entraObjectId='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';deviceId='bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';displayName='LT-100';serialNumber='serial-1';intuneManagedDeviceId='cccccccc-cccc-cccc-cccc-cccccccccccc'
                defenderMachineId='1111111111111111111111111111111111111111';archivedAt='2026-10-01T00:00:00Z';cleanupRunId='run-1';primaryUserState='Single'
                primaryUserId='dddddddd-dddd-dddd-dddd-dddddddddddd';primaryUserPrincipalName=$Upn
            }
            $tags=[pscustomobject]@{
                kind='device-archive-index';schemaVersion='1.0';archiveSecretName=$ArchiveName;archiveSecretVersion=$Version
                archiveIdHash=$indexName.Substring('device-archive-index-'.Length);entraObjectId='aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa';deviceId='bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb';displayName='LT-100'
                serialNumber='serial-1';intuneManagedDeviceId='cccccccc-cccc-cccc-cccc-cccccccccccc';defenderMachineId='1111111111111111111111111111111111111111';archivedAt='2026-10-01T00:00:00Z'
                cleanupRunId='run-1';primaryUserState='Single';primaryUserId='dddddddd-dddd-dddd-dddd-dddddddddddd'
            }
            [pscustomobject]@{
                Metadata=[pscustomobject]@{id="https://archive-vault.vault.azure.net/secrets/$indexName";contentType='application/vnd.azd-device-cleanup.archive-index+json;v=1';tags=$tags}
                Response=[pscustomobject]@{id="https://archive-vault.vault.azure.net/secrets/$indexName/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa";contentType='application/vnd.azd-device-cleanup.archive-index+json;v=1';value=($payload|ConvertTo-Json -Depth 5 -Compress)}
                Name=$indexName
                Payload=$payload
            }
        }
        function New-LegacyFixture {
            [pscustomobject]@{id='https://archive-vault.vault.azure.net/secrets/archive-device';tags=[pscustomobject]@{displayName='LT-100';deviceId='device-1';entraObjectId='entra-1';archivedAt='2026-10-02T00:00:00Z'}}
        }
    }
    BeforeEach {
        Mock Ensure-AzureCli {}
        $script:index=New-IndexFixture
        $script:metadata=@((New-LegacyFixture),$script:index.Metadata)
        $script:valueCalls=@()
        $script:archiveResponse=[pscustomobject]@{id='https://archive-vault.vault.azure.net/secrets/archive-device/11111111111111111111111111111111';contentType='application/json';value='{"archivedAt":"2026-10-01T00:00:00Z","laps":{"credentials":[{"password":"RECOVERY_SENTINEL"}]},"bitlocker":[]}' }
        Mock Get-KeyVaultSecretMetadata { $script:metadata }
        Mock Get-KeyVaultSecretValue {
            param($VaultName,$SecretName,$Version,$ExpectedContentType)
            $script:valueCalls += [pscustomobject]@{Name=$SecretName;Version=$Version}
            if($SecretName -eq $script:index.Name){return $script:index.Response}
            $script:archiveResponse
        }
    }

    It 'uses zero value reads by default and retains the legacy latest alias beside the exact version' {
        $output=@(Invoke-ArchivedDeviceLookup -KeyVaultName 'archive-vault' -DisplayName 'LT-100' -AsJson *>&1)|Out-String
        $script:valueCalls.Count | Should -Be 0
        $output | Should -Match 'IndexedExactVersion'
        $output | Should -Match 'LegacyLatestAlias'
        $output | Should -Match '11111111111111111111111111111111'
    }

    It 'keeps a newer orphan visible through the legacy latest alias' {
        $output=@(Invoke-ArchivedDeviceLookup -KeyVaultName 'archive-vault' -DisplayName 'LT-100' -AsJson *>&1)|Out-String
        $output | Should -Match '2026-10-02T00:00:00Z'
        $output | Should -Match '2026-10-01T00:00:00Z'
        $script:valueCalls.Count | Should -Be 0
    }

    It 'normalizes mixed-case selected vault input without changing the pointer hash' {
        $output=@(Invoke-ArchivedDeviceLookup -KeyVaultName 'ARCHIVE-VAULT' -ArchiveVersion '11111111111111111111111111111111' -AsJson *>&1)|Out-String
        $output | Should -Match 'IndexedExactVersion'
        $output | Should -Match '11111111111111111111111111111111'
        $script:valueCalls.Count | Should -Be 0
    }

    It 'quarantines every malformed reserved-prefix secret without treating it as a legacy archive' {
        $script:metadata += [pscustomobject]@{id='https://archive-vault.vault.azure.net/secrets/device-archive-index-malformed';tags=[pscustomobject]@{displayName='MALICIOUS'}}
        $script:metadata += [pscustomobject]@{id='https://archive-vault.vault.azure.net/secrets/device-archive-index-bad/extra';tags=[pscustomobject]@{displayName='MALICIOUS-PATH'}}
        $output=@(Invoke-ArchivedDeviceLookup -KeyVaultName 'archive-vault' -AsJson *>&1)|Out-String
        $output | Should -Not -Match 'MALICIOUS|device-archive-index-malformed|device-archive-index-bad'
        $script:valueCalls.Count | Should -Be 0
    }

    It 'quarantines foreign-authority and nonscalar legacy metadata' {
        $script:metadata += @(
            [pscustomobject]@{id='https://foreign-vault.vault.azure.net/secrets/foreign-host';tags=[pscustomobject]@{displayName='FOREIGN-HOST'}},
            [pscustomobject]@{id='https://user@archive-vault.vault.azure.net/secrets/userinfo-row';tags=[pscustomobject]@{displayName='USERINFO'}},
            [pscustomobject]@{id='https://archive-vault.vault.azure.net:8443/secrets/port-row';tags=[pscustomobject]@{displayName='BAD-PORT'}},
            [pscustomobject]@{id='https://archive-vault.vault.azure.net/secrets/nested-row';tags=[pscustomobject]@{displayName=[pscustomobject]@{secret='NESTED-SENTINEL'}}},
            [pscustomobject]@{id='https://archive-vault.vault.azure.net/secrets/oversized-row';tags=[pscustomobject]@{displayName=('O' * 257)}}
        )
        $output=@(Invoke-ArchivedDeviceLookup -KeyVaultName 'archive-vault' -AsJson *>&1)|Out-String
        $output | Should -Not -Match 'FOREIGN-HOST|USERINFO|BAD-PORT|NESTED-SENTINEL|oversized-row'
        $script:valueCalls.Count | Should -Be 0
    }

    It 'reads bounded index values for exact UPN selection but no recovery value' {
        $output=@(Invoke-ArchivedDeviceLookup -KeyVaultName 'archive-vault' -PrimaryUserPrincipalName 'user@example.com' -AsJson *>&1)|Out-String
        $script:valueCalls.Count | Should -Be 1
        $script:valueCalls[0].Name | Should -Be $script:index.Name
        $output | Should -Match 'user@example.com'
        $output | Should -Not -Match 'RECOVERY_SENTINEL'
    }

    It 'recovers the exact indexed archive version after validating the index value' {
        $output=@(Invoke-ArchivedDeviceLookup -KeyVaultName 'archive-vault' -ArchiveVersion '11111111111111111111111111111111' -ShowRecoveryMaterial -AsJson *>&1)|Out-String
        $script:valueCalls.Count | Should -Be 2
        $script:valueCalls[0].Name | Should -Be $script:index.Name
        $script:valueCalls[1].Name | Should -Be 'archive-device'
        $script:valueCalls[1].Version | Should -Be '11111111111111111111111111111111'
        $output | Should -Match 'RECOVERY_SENTINEL'
    }

    It 'rejects a wrong exact archive response version before exposing recovery material' {
        $script:archiveResponse.id='https://archive-vault.vault.azure.net/secrets/archive-device/22222222222222222222222222222222'
        $message=try{Invoke-ArchivedDeviceLookup -KeyVaultName 'archive-vault' -ArchiveVersion '11111111111111111111111111111111' -ShowRecoveryMaterial -AsJson}catch{$_.Exception.Message}
        $message | Should -Be 'Key Vault secret response identity is invalid.'
        $message | Should -Not -Match 'RECOVERY_SENTINEL'
        $script:valueCalls.Count | Should -Be 2
    }

    It 'rejects hostile index response identity and content type before parsing its value' -ForEach @(
        @{Id='https://other-vault.vault.azure.net/secrets/placeholder/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';ContentType='application/vnd.azd-device-cleanup.archive-index+json;v=1';Expected='identity'},
        @{Id='https://archive-vault.vault.azure.net/secrets/wrong-name/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';ContentType='application/vnd.azd-device-cleanup.archive-index+json;v=1';Expected='identity'},
        @{Id='https://unexpected@archive-vault.vault.azure.net/secrets/placeholder/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa';ContentType='application/vnd.azd-device-cleanup.archive-index+json;v=1';Expected='identity'},
        @{Id='';ContentType='application/json';Expected='content type'}
    ) {
        if ([string]::IsNullOrWhiteSpace($Id)) { $script:index.Response.id="https://archive-vault.vault.azure.net/secrets/$($script:index.Name)/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa" }
        else { $script:index.Response.id=$Id.Replace('placeholder',$script:index.Name) }
        $script:index.Response.contentType=$ContentType
        $message=try{Invoke-ArchivedDeviceLookup -KeyVaultName 'archive-vault' -PrimaryUserPrincipalName 'user@example.com'}catch{$_.Exception.Message}
        $message | Should -Be "Key Vault secret response $Expected is invalid."
        $script:valueCalls.Count | Should -Be 1
    }

    It 'rejects tampered index identity before any recovery value read' {
        $tampered=$script:index.Payload.PSObject.Copy()
        $tampered.archiveSecretId='https://archive-vault.vault.azure.net/secrets/archive-device/22222222222222222222222222222222'
        $script:index.Response.value=($tampered|ConvertTo-Json -Compress)
        $message=try{Invoke-ArchivedDeviceLookup -KeyVaultName 'archive-vault' -ArchiveVersion '11111111111111111111111111111111' -ShowRecoveryMaterial}catch{$_.Exception.Message}
        $message | Should -Be 'The archive metadata index is invalid.'
        $script:valueCalls.Count | Should -Be 1
        $message | Should -Not -Match '22222222222222222222222222222222'
    }

    It 'rejects a malicious nested property without exposing the value' {
        $malicious=[ordered]@{}
        foreach($property in $script:index.Payload.PSObject.Properties){$malicious[$property.Name]=$property.Value}
        $malicious['recovery']=[ordered]@{password='SECRET_SENTINEL'}
        $script:index.Response.value=($malicious|ConvertTo-Json -Depth 5 -Compress)
        $message=try{Invoke-ArchivedDeviceLookup -KeyVaultName 'archive-vault' -PrimaryUserPrincipalName 'user@example.com'}catch{$_.Exception.Message}
        $message | Should -Be 'The archive metadata index is invalid.'
        $message | Should -Not -Match 'SECRET_SENTINEL|password'
    }
}
