#requires -Version 7.6
Describe 'Archive reader preserves JSON strings at the transport boundary' {
    BeforeAll {
        $path = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts/Get-ArchivedDevice.ps1'
        $tokens=$null; $errors=$null
        $ast=[Management.Automation.Language.Parser]::ParseFile($path,[ref]$tokens,[ref]$errors)
        if($errors.Count){throw($errors|Out-String)}
        foreach($definition in @($ast.EndBlock.Statements | Where-Object { $_ -is [Management.Automation.Language.FunctionDefinitionAst] })) { . ([scriptblock]::Create($definition.Extent.Text)) }
    }
    BeforeEach {
        Mock Ensure-AzureCli {}
        Mock Get-KeyVaultAccessToken { 'offline-token' }
        $script:requests=@()
        $script:timestamp='2026-01-01T00:00:00.0000000Z'
        $script:version='11111111111111111111111111111111'
        $script:archiveId="https://archive-vault.vault.azure.net/secrets/archive-device/$script:version"
        $script:indexName=Get-ArchiveIndexName -ArchiveSecretId $script:archiveId
        $script:indexPayload=[ordered]@{
            schemaVersion='1.0';kind='device-archive-index';archiveSecretName='archive-device';archiveSecretVersion=$script:version;archiveSecretId=$script:archiveId
            entraObjectId='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';deviceId=$null;displayName='INDEXED';serialNumber=$null;intuneManagedDeviceId=$null;defenderMachineId=$null
            archivedAt=$script:timestamp;cleanupRunId='synthetic-run';primaryUserState='None';primaryUserId=$null;primaryUserPrincipalName=$null
        }
        $script:metadata=@(
            @{id='https://archive-vault.vault.azure.net/secrets/archive-device';tags=@{displayName='LEGACY';archivedAt=$script:timestamp}}
            @{id="https://archive-vault.vault.azure.net/secrets/$script:indexName";contentType='application/vnd.azd-device-cleanup.archive-index+json;v=1';tags=@{
                kind='device-archive-index';schemaVersion='1.0';archiveSecretName='archive-device';archiveSecretVersion=$script:version;archiveIdHash=$script:indexName.Substring('device-archive-index-'.Length)
                entraObjectId='aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa';displayName='INDEXED';archivedAt=$script:timestamp;cleanupRunId='synthetic-run';primaryUserState='None'
            }}
        )
        $script:archivePayload=@{archivedAt=$script:timestamp;laps=@{credentials=@(@{password=$script:timestamp})};bitlocker=@(@{key=$script:timestamp})}
        Mock Invoke-WebRequest {
            param($Method,$Uri,$Headers)
            $path=([uri]$Uri).AbsolutePath; $script:requests+=$path
            if($path -eq '/secrets'){$body=@{value=$script:metadata}}
            elseif($path -eq "/secrets/$script:indexName"){$body=@{id="https://archive-vault.vault.azure.net/secrets/$script:indexName/22222222222222222222222222222222";contentType='application/vnd.azd-device-cleanup.archive-index+json;v=1';value=($script:indexPayload|ConvertTo-Json -Depth 8 -Compress)}}
            elseif($path -eq '/secrets/archive-device' -or $path -eq "/secrets/archive-device/$script:version"){$body=@{id=$script:archiveId;contentType='application/json';value=($script:archivePayload|ConvertTo-Json -Depth 8 -Compress)}}
            else{throw 'Unexpected transport URI.'}
            # Raw wire JSON exercises the production parser rather than supplying decoded objects.
            [pscustomobject]@{Content=($body|ConvertTo-Json -Depth 10 -Compress)}
        }
    }
    It 'accepts legacy and indexed timestamp tags without reading values' {
        $items=@(Get-KeyVaultSecretMetadata -VaultName 'archive-vault')
        $items[0].tags.archivedAt | Should -BeOfType [string]
        $items[0].tags.archivedAt | Should -BeExactly $script:timestamp
        (ConvertTo-Summary $items[0] 'archive-vault').RecordType | Should -Be 'LegacyLatestAlias'
        (Get-ValidatedIndexTagSummary $items[1] 'archive-vault').ArchiveVersion | Should -Be $script:version
        $result=Invoke-ArchivedDeviceLookup -KeyVaultName 'archive-vault' -DisplayName 'INDEXED' -AsJson | ConvertFrom-Json -DateKind String
        $result.RecordType | Should -Be 'IndexedExactVersion'
        @($script:requests|Where-Object {$_ -ne '/secrets'}).Count | Should -Be 0
    }
    It 'keeps timestamp-shaped secret strings exact in indexed recovery' {
        $result=Invoke-ArchivedDeviceLookup -KeyVaultName 'archive-vault' -DisplayName 'INDEXED' -ShowRecoveryMaterial -AsJson | ConvertFrom-Json -DateKind String
        $result.archivedAt | Should -BeExactly $script:timestamp
        $result.laps.credentials[0].password | Should -BeExactly $script:timestamp
        $result.bitlocker[0].key | Should -BeExactly $script:timestamp
        $script:requests | Should -Be @('/secrets',"/secrets/$script:indexName","/secrets/archive-device/$script:version")
    }
    It 'keeps timestamp-shaped secret strings exact in legacy latest recovery' {
        $result=Invoke-ArchivedDeviceLookup -KeyVaultName 'archive-vault' -DisplayName 'LEGACY' -ShowRecoveryMaterial -AsJson | ConvertFrom-Json -DateKind String
        $result.laps.credentials[0].password | Should -BeExactly $script:timestamp
        $script:requests | Should -Be @('/secrets','/secrets/archive-device')
    }
    It 'still refuses non-string tags received as wire JSON' {
        $script:metadata[0].tags.archivedAt=@{nested='not-a-string'}
        $script:metadata[1].tags.archivedAt=42
        $items=@(Get-KeyVaultSecretMetadata -VaultName 'archive-vault')
        ConvertTo-Summary $items[0] 'archive-vault' | Should -BeNullOrEmpty
        Get-ValidatedIndexTagSummary $items[1] 'archive-vault' | Should -BeNullOrEmpty
        $script:requests | Should -Be @('/secrets')
    }
    It 'sanitizes malformed wire JSON without exposing its content' {
        Mock Invoke-WebRequest {[pscustomobject]@{Content='SECRET_SENTINEL invalid JSON'}}
        $message=try{Get-KeyVaultSecretMetadata -VaultName 'archive-vault'}catch{$_.Exception.Message}
        $message | Should -Be 'Key Vault request failed.'
        $message | Should -Not -Match 'SECRET_SENTINEL'
    }
}
