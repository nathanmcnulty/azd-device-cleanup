Describe 'Archived device reader safety boundaries' {
    BeforeAll {
        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'
        $repoRoot = Split-Path $PSScriptRoot -Parent
        $scriptPath = Join-Path $repoRoot 'scripts/Get-ArchivedDevice.ps1'
        $tokens = $null
        $parseErrors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref] $tokens, [ref] $parseErrors)
        if ($parseErrors.Count -gt 0) { throw ($parseErrors | Out-String) }
        foreach ($definition in @($ast.FindAll({
                    param($node)
                    $node -is [System.Management.Automation.Language.FunctionDefinitionAst]
                }, $true))) {
            . ([scriptblock]::Create($definition.Extent.Text))
        }

        function New-ArchiveMetadata {
            param(
                [Parameter(Mandatory = $true)] [string] $Name,
                [string] $DisplayName = 'LT-100',
                [string] $ArchivedAt = '2026-10-01T00:00:00Z',
                [object] $Tags
            )

            if ($null -eq $Tags) {
                $Tags = [pscustomobject]@{
                    displayName = $DisplayName
                    deviceId = "device-$Name"
                    entraObjectId = "entra-$Name"
                    archivedAt = $ArchivedAt
                }
            }

            return [pscustomobject]@{
                id = "https://archive-vault.vault.azure.net/secrets/$Name"
                tags = $Tags
            }
        }

        function Capture-Failure {
            param(
                [Parameter(Mandatory = $true)]
                [scriptblock] $Operation
            )

            return @(& {
                    try { & $Operation }
                    catch { $_ }
                } *>&1 | Out-String)
        }
    }

    BeforeEach {
        $script:metadata = @()
        $script:valueCalls = 0
        $script:metadataCalls = 0
        Mock Ensure-AzureCli {}
        Mock Get-KeyVaultSecretValue {
            param($VaultName,$SecretName,$Version,$ExpectedContentType)
            $script:valueCalls++
            $returnedVersion=if([string]::IsNullOrWhiteSpace($Version)){'11111111111111111111111111111111'}else{$Version}
            return [pscustomobject]@{ id="https://archive-vault.vault.azure.net/secrets/$SecretName/$returnedVersion";contentType='application/json';value=$script:archiveJson }
        }
    }

    It 'keeps a single default match metadata-only' {
        Mock Get-KeyVaultSecretMetadata { $script:metadataCalls++; return $script:metadata }
        $script:metadata = @(New-ArchiveMetadata -Name 'one' -DisplayName 'LT-100')
        $script:archiveJson = '{"laps":{"credentials":[{"password":"RECOVERY_SENTINEL"}]}}'

        $output = @(& {
                Invoke-ArchivedDeviceLookup -KeyVaultName 'archive-vault' -DisplayName 'LT-100' -AsJson
            } *>&1 | Out-String)

        $script:metadataCalls | Should -Be 1
        $script:valueCalls | Should -Be 0
        ($output -join "`n") | Should -Match '"SecretName":\s*"one"'
        ($output -join "`n") | Should -Not -Match 'RECOVERY_SENTINEL'
    }

    It 'keeps many default matches metadata-only and preserves duplicate hostnames' {
        Mock Get-KeyVaultSecretMetadata { $script:metadataCalls++; return $script:metadata }
        $script:metadata = @(
            (New-ArchiveMetadata -Name 'one' -DisplayName 'DUPLICATE-HOST'),
            (New-ArchiveMetadata -Name 'two' -DisplayName 'DUPLICATE-HOST' -ArchivedAt '2026-09-01T00:00:00Z')
        )
        $script:archiveJson = '{"laps":{"credentials":[{"password":"RECOVERY_SENTINEL"}]}}'

        $output = @(& {
                Invoke-ArchivedDeviceLookup -KeyVaultName 'archive-vault' -DisplayName 'DUPLICATE-HOST' -AsJson
            } *>&1 | Out-String)

        $script:metadataCalls | Should -Be 1
        $script:valueCalls | Should -Be 0
        ($output -join "`n") | Should -Match '"SecretName":\s*"one"'
        ($output -join "`n") | Should -Match '"SecretName":\s*"two"'
        ($output -join "`n") | Should -Not -Match 'RECOVERY_SENTINEL'
    }

    It 'retains the explicit single-record recovery view and reads exactly once' {
        Mock Get-KeyVaultSecretMetadata { $script:metadataCalls++; return $script:metadata }
        $script:metadata = @(New-ArchiveMetadata -Name 'one' -DisplayName 'LT-100')
        $script:archiveJson = '{"archivedAt":"2026-10-01T00:00:00Z","laps":{"credentials":[{"password":"RECOVERY_SENTINEL"}]},"bitlocker":[{"key":"BITLOCKER_SENTINEL"}]}'

        $output = @(& {
                Invoke-ArchivedDeviceLookup -KeyVaultName 'archive-vault' -DisplayName 'LT-100' -ShowRecoveryMaterial -AsJson
            } *>&1 | Out-String)

        $script:valueCalls | Should -Be 1
        ($output -join "`n") | Should -Match 'RECOVERY_SENTINEL'
        ($output -join "`n") | Should -Match 'BITLOCKER_SENTINEL'
    }

    It 'reports zero recovery counts when optional recovery sections are null' {
        Mock Get-KeyVaultSecretMetadata { $script:metadataCalls++; return $script:metadata }
        $script:metadata = @(New-ArchiveMetadata -Name 'one' -DisplayName 'LT-100')
        $script:archiveJson = '{"archivedAt":"2026-10-01T00:00:00Z","laps":null,"bitlocker":null}'

        $output = @(& {
                Invoke-ArchivedDeviceLookup -KeyVaultName 'archive-vault' -DisplayName 'LT-100' -ShowRecoveryMaterial -AsJson
            } *>&1 | Out-String)

        $script:valueCalls | Should -Be 1
        ($output -join "`n") | Should -Match '"lapsCredentialCount":\s*0'
        ($output -join "`n") | Should -Match '"bitLockerKeyCount":\s*0'
    }

    It 'rejects ambiguous recovery before reading any secret value' {
        Mock Get-KeyVaultSecretMetadata { $script:metadataCalls++; return $script:metadata }
        $script:metadata = @(
            (New-ArchiveMetadata -Name 'one' -DisplayName 'DUPLICATE-HOST'),
            (New-ArchiveMetadata -Name 'two' -DisplayName 'DUPLICATE-HOST')
        )

        { Invoke-ArchivedDeviceLookup -KeyVaultName 'archive-vault' -DisplayName 'DUPLICATE-HOST' -ShowRecoveryMaterial } |
            Should -Throw '*Multiple archived device secrets*'
        $script:valueCalls | Should -Be 0
    }

    It 'treats absent optional tags and attributes as non-matches without StrictMode failures' {
        Set-StrictMode -Version Latest
        $missingTags = [pscustomobject]@{ id = 'https://archive-vault.vault.azure.net/secrets/no-tags' }
        $nullAttributes = [pscustomobject]@{
            id = 'https://archive-vault.vault.azure.net/secrets/null-attributes'
            attributes = $null
        }
        $partialTags = [pscustomobject]@{
            id = 'https://archive-vault.vault.azure.net/secrets/partial'
            tags = [pscustomobject]@{ displayName = 'LT-100' }
        }
        $hashtableTags = [pscustomobject]@{
            id = 'https://archive-vault.vault.azure.net/secrets/hashtable'
            tags = @{ displayName = 'LT-100' }
        }

        { Test-Match -Secret $missingTags -DisplayName 'LT-100' } | Should -Not -Throw
        { Test-Match -Secret $nullAttributes -DeviceId 'device-1' } | Should -Not -Throw
        { Test-Match -Secret $partialTags -DeviceId 'device-1' } | Should -Not -Throw
        { Test-Match -Secret $hashtableTags -DeviceId 'device-1' } | Should -Not -Throw
        (Test-Match -Secret $missingTags -DisplayName 'LT-100') | Should -BeFalse
        (Test-Match -Secret $nullAttributes -DeviceId 'device-1') | Should -BeFalse
        (Test-Match -Secret $partialTags -DeviceId 'device-1') | Should -BeFalse
        (Test-Match -Secret $hashtableTags -DisplayName 'LT-100') | Should -BeTrue
        { ConvertTo-Summary -SecretMetadata $nullAttributes -VaultName 'archive-vault' } | Should -Not -Throw
        (ConvertTo-Summary -SecretMetadata $nullAttributes -VaultName 'archive-vault').DisplayName | Should -BeNullOrEmpty
    }

    It 'rejects an invalid vault hostname before token or metadata access' {
        $script:tokenCalls = 0
        Mock Get-KeyVaultAccessToken { $script:tokenCalls++; return 'TOKEN_SENTINEL' }
        Mock Get-KeyVaultSecretMetadata { $script:metadataCalls++; return $script:metadata }

        { Invoke-ArchivedDeviceLookup -KeyVaultName 'archive-vault.example' } |
            Should -Throw '*KeyVaultName must be*'
        $script:tokenCalls | Should -Be 0
        $script:metadataCalls | Should -Be 0
    }

    It 'sanitizes Key Vault response exceptions across captured output streams' {
        Mock Get-KeyVaultAccessToken { return 'TOKEN_SENTINEL' }
        Mock Invoke-RestMethod { throw 'raw response SECRET_SENTINEL value' }

        $output = Capture-Failure -Operation {
            Get-KeyVaultSecretMetadata -VaultName 'archive-vault'
        }

        $output | Should -Match 'Key Vault request failed'
        $output | Should -Not -Match 'SECRET_SENTINEL|raw response'
    }

    It 'follows a valid two-page metadata continuation without reading values' {
        $script:requestCalls = 0
        Mock Get-KeyVaultAccessToken { return 'TOKEN_SENTINEL' }
        Mock Invoke-RestMethod {
            $script:requestCalls++
            if ($script:requestCalls -eq 1) {
                return [pscustomobject]@{
                    value = @(New-ArchiveMetadata -Name 'one')
                    nextLink = 'https://archive-vault.vault.azure.net/secrets?api-version=7.4&skiptoken=page2'
                }
            }

            return [pscustomobject]@{
                value = @(New-ArchiveMetadata -Name 'two' -ArchivedAt '2026-09-01T00:00:00Z')
            }
        }

        $items = @(Get-KeyVaultSecretMetadata -VaultName 'archive-vault')

        $script:requestCalls | Should -Be 2
        $items.Count | Should -Be 2
        @($items | ForEach-Object { $_.id.Split('/')[-1] }) | Should -Contain 'one'
        @($items | ForEach-Object { $_.id.Split('/')[-1] }) | Should -Contain 'two'
    }

    It 'rejects a recovery-secret metadata continuation before a second request' {
        $script:requestCalls = 0
        $script:tokenCalls = 0
        Mock Get-KeyVaultAccessToken { $script:tokenCalls++; return 'TOKEN_SENTINEL' }
        Mock Invoke-RestMethod {
            $script:requestCalls++
            return [pscustomobject]@{
                value = @(New-ArchiveMetadata -Name 'one')
                nextLink = 'https://archive-vault.vault.azure.net/secrets/recovery-name?api-version=7.4'
            }
        }

        $output = Capture-Failure -Operation {
            Get-KeyVaultSecretMetadata -VaultName 'archive-vault'
        }

        $output | Should -Match 'Key Vault metadata continuation URI is invalid'
        $output | Should -Not -Match 'recovery-name|TOKEN_SENTINEL'
        $script:requestCalls | Should -Be 1
        $script:tokenCalls | Should -Be 1
    }

    It 'sanitizes malformed archive JSON without exposing the secret value' {
        Mock Get-KeyVaultSecretMetadata { $script:metadataCalls++; return $script:metadata }
        $script:metadata = @(New-ArchiveMetadata -Name 'one')
        $script:archiveJson = 'SECRET_SENTINEL malformed payload'

        $output = Capture-Failure -Operation {
            Invoke-ArchivedDeviceLookup -KeyVaultName 'archive-vault' -DisplayName 'LT-100' -ShowRecoveryMaterial
        }

        $output | Should -Match 'archived secret payload could not be parsed'
        $output | Should -Not -Match 'SECRET_SENTINEL|malformed payload'
        $script:valueCalls | Should -Be 1
    }

    It 'stops after a native token CLI failure before issuing a request' {
        $script:requestCalls = 0
        $hadExitCode = Test-Path Variable:\global:LASTEXITCODE
        $priorExitCode = if ($hadExitCode) { $global:LASTEXITCODE } else { $null }
        Mock az {
            $global:LASTEXITCODE = 1
            Write-Output 'TOKEN_SENTINEL'
        }
        Mock Invoke-RestMethod { $script:requestCalls++ }

        try {
            $output = Capture-Failure -Operation {
                Get-KeyVaultSecretMetadata -VaultName 'archive-vault'
            }

            $output | Should -Match 'Azure CLI token acquisition failed'
            $output | Should -Not -Match 'TOKEN_SENTINEL'
            $script:requestCalls | Should -Be 0
        }
        finally {
            if ($hadExitCode) { $global:LASTEXITCODE = $priorExitCode } else { Remove-Variable LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue }
        }
    }

    It 'rejects multiple non-empty token lines before issuing a request' {
        $script:requestCalls = 0
        $hadExitCode = Test-Path Variable:\global:LASTEXITCODE
        $priorExitCode = if ($hadExitCode) { $global:LASTEXITCODE } else { $null }
        Mock az {
            $global:LASTEXITCODE = 0
            Write-Output 'TOKEN_ONE_SENTINEL'
            Write-Output 'TOKEN_TWO_SENTINEL'
        }
        Mock Invoke-RestMethod { $script:requestCalls++ }

        try {
            $output = Capture-Failure -Operation {
                Get-KeyVaultSecretMetadata -VaultName 'archive-vault'
            }

            $output | Should -Match 'Azure CLI token acquisition failed'
            $output | Should -Not -Match 'TOKEN_ONE_SENTINEL|TOKEN_TWO_SENTINEL'
            $script:requestCalls | Should -Be 0
        }
        finally {
            if ($hadExitCode) { $global:LASTEXITCODE = $priorExitCode } else { Remove-Variable LASTEXITCODE -Scope Global -ErrorAction SilentlyContinue }
        }
    }

    It 'rejects a tampered metadata secret path before issuing a recovery request' {
        Mock Get-KeyVaultSecretMetadata { $script:metadataCalls++; return $script:metadata }
        $script:metadata = @([pscustomobject]@{
                id = 'https://archive-vault.vault.azure.net/secrets/../SECRET_SENTINEL'
                tags = [pscustomobject]@{ displayName = 'LT-100' }
            })

        $output=@(Invoke-ArchivedDeviceLookup -KeyVaultName 'archive-vault' -DisplayName 'LT-100' -ShowRecoveryMaterial *>&1)|Out-String
        $output | Should -Match 'No archived device secrets matched'
        $output | Should -Not -Match 'SECRET_SENTINEL'
        $script:valueCalls | Should -Be 0
    }

    It 'rejects a foreign Key Vault continuation before token acquisition' {
        $script:tokenCalls = 0
        $script:requestCalls = 0
        Mock Get-KeyVaultAccessToken { $script:tokenCalls++; return 'TOKEN_SENTINEL' }
        Mock Invoke-RestMethod { $script:requestCalls++ }

        $output = Capture-Failure -Operation {
            Invoke-KeyVaultJson -Method 'GET' -VaultName 'archive-vault' -Uri 'https://foreign.vault.azure.net/secrets?api-version=7.4'
        }

        $output | Should -Match 'Key Vault request URI is invalid'
        $output | Should -Not -Match 'TOKEN_SENTINEL'
        $script:tokenCalls | Should -Be 0
        $script:requestCalls | Should -Be 0
    }
}

Describe 'Explicit recovery transport URI' {
    BeforeAll {
        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'
        $tokens = $null
        $parseErrors = $null
        $scriptPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts/Get-ArchivedDevice.ps1'
        $ast = [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
        foreach ($definition in @($ast.EndBlock.Statements | Where-Object { $_ -is [System.Management.Automation.Language.FunctionDefinitionAst] })) {
            . ([scriptblock]::Create($definition.Extent.Text))
        }
    }

    It 'uses the exact selected secret URI through the real recovery helper' {
        Mock Get-KeyVaultAccessToken { 'offline-token' }
        Mock Invoke-RestMethod { [pscustomobject]@{ id='https://archive-vault.vault.azure.net/secrets/archive-device/11111111111111111111111111111111';contentType='application/json';value='{}' } }

        $value = Get-KeyVaultSecretValue -VaultName 'archive-vault' -SecretName 'archive-device'

        $value.value | Should -Be '{}'
        Should -Invoke Invoke-RestMethod -Times 1 -Exactly -ParameterFilter {
            $Method -eq 'GET' -and $Uri -ceq 'https://archive-vault.vault.azure.net/secrets/archive-device?api-version=7.4'
        }
    }
}
