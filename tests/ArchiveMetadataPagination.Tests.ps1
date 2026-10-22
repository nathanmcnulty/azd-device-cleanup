Describe 'Bounded archive metadata pagination' {
    BeforeAll {
        Set-StrictMode -Version Latest
        $ErrorActionPreference = 'Stop'
        $readerPath = Join-Path (Split-Path $PSScriptRoot -Parent) 'scripts/Get-ArchivedDevice.ps1'
        $tokens = $null
        $parseErrors = $null
        $ast = [Management.Automation.Language.Parser]::ParseFile($readerPath, [ref]$tokens, [ref]$parseErrors)
        if ($parseErrors.Count) { throw ($parseErrors | Out-String) }
        foreach ($definition in @($ast.EndBlock.Statements | Where-Object { $_ -is [Management.Automation.Language.FunctionDefinitionAst] })) {
            . ([scriptblock]::Create($definition.Extent.Text))
        }
    }

    BeforeEach {
        $script:requestCalls = 0
        $script:valueCalls = 0
        $script:totalItems = 501
        $script:pageSize = 25
        $script:duplicateTarget = $false
        Mock Ensure-AzureCli {}
        Mock Get-KeyVaultSecretValue { $script:valueCalls++; throw 'Unexpected secret-value read.' }
        Mock Invoke-KeyVaultJson {
            $offset = $script:requestCalls * $script:pageSize
            $script:requestCalls++
            $count = [Math]::Min($script:pageSize, $script:totalItems - $offset)
            $values = @(for ($i = 1; $i -le $count; $i++) {
                $number = $offset + $i
                $displayName = if ($number -eq $script:totalItems -or ($script:duplicateTarget -and $number -eq 1)) { 'TARGET' } else { 'OTHER' }
                [pscustomobject]@{
                    id = "https://archive-vault.vault.azure.net/secrets/archive-$number"
                    tags = [pscustomobject]@{ displayName = $displayName }
                }
            })
            $next = if ($offset + $count -lt $script:totalItems) {
                "https://archive-vault.vault.azure.net/secrets?api-version=7.4&skiptoken=$($script:requestCalls)"
            } else { $null }
            [pscustomobject]@{ value = $values; nextLink = $next }
        }
    }

    It 'lists beyond twenty pages without assuming full service pages' -ForEach @(
        @{ Total = 501; PageSize = 25; Calls = 21 },
        @{ Total = 21; PageSize = 1; Calls = 21 },
        @{ Total = 5000; PageSize = 25; Calls = 200 }
    ) {
        $script:totalItems = $Total
        $script:pageSize = $PageSize
        $items = @(Get-KeyVaultSecretMetadata -VaultName 'archive-vault')

        $items.Count | Should -Be $Total
        $items[-1].id | Should -Be "https://archive-vault.vault.azure.net/secrets/archive-$Total"
        $script:requestCalls | Should -Be $Calls
        $script:valueCalls | Should -Be 0
        Should -Invoke Invoke-KeyVaultJson -Times 1 -Exactly -ParameterFilter {
            $Uri -ceq 'https://archive-vault.vault.azure.net/secrets?api-version=7.4&maxresults=25'
        }
    }

    It 'finds a requested archive on page twenty-one without reading its value' {
        $output = @(Invoke-ArchivedDeviceLookup -KeyVaultName 'archive-vault' -DisplayName 'TARGET' -AsJson *>&1) | Out-String

        $output | Should -Match '"SecretName":\s*"archive-501"'
        $script:requestCalls | Should -Be 21
        $script:valueCalls | Should -Be 0
    }

    It 'detects a matching archive on a later page before permitting recovery' {
        $script:duplicateTarget = $true

        { Invoke-ArchivedDeviceLookup -KeyVaultName 'archive-vault' -DisplayName 'TARGET' -ShowRecoveryMaterial } |
            Should -Throw '*Multiple archived device secrets*'
        $script:requestCalls | Should -Be 21
        $script:valueCalls | Should -Be 0
    }

    It 'fails atomically when metadata exceeds the unchanged item budget' {
        $script:totalItems = 5001
        $script:emittedItems = 0
        $failure = try {
            Get-KeyVaultSecretMetadata -VaultName 'archive-vault' | ForEach-Object { $script:emittedItems++ }
        } catch { $_.Exception.Message }

        $failure | Should -Be 'Key Vault metadata listing exceeded its item limit.'
        $script:requestCalls | Should -Be 201
        $script:emittedItems | Should -Be 0
        $script:valueCalls | Should -Be 0
    }

    It 'stops unique empty-page continuations promptly without item progress' {
        Mock Invoke-KeyVaultJson {
            $script:requestCalls++
            [pscustomobject]@{
                value = @()
                nextLink = "https://archive-vault.vault.azure.net/secrets?api-version=7.4&skiptoken=$($script:requestCalls)"
            }
        }

        { Get-KeyVaultSecretMetadata -VaultName 'archive-vault' } |
            Should -Throw '*pagination exceeded its empty-page limit*'
        $script:requestCalls | Should -Be 20
        $script:valueCalls | Should -Be 0
    }

    It 'resets the empty-page allowance after progress and accepts an empty terminal page' {
        Mock Invoke-KeyVaultJson {
            $script:requestCalls++
            $values = @()
            if ($script:requestCalls % 11 -eq 0) {
                $values = @([pscustomobject]@{
                    id = "https://archive-vault.vault.azure.net/secrets/archive-$($script:requestCalls)"
                })
            }
            $next = if ($script:requestCalls -lt 45) {
                "https://archive-vault.vault.azure.net/secrets?api-version=7.4&skiptoken=$($script:requestCalls)"
            } else { $null }
            [pscustomobject]@{ value = $values; nextLink = $next }
        }

        $items = @(Get-KeyVaultSecretMetadata -VaultName 'archive-vault')

        $items.Count | Should -Be 4
        $script:requestCalls | Should -Be 45
        $script:valueCalls | Should -Be 0
    }

    It 'stops total request growth even while sparse pages make intermittent progress' {
        Mock Invoke-KeyVaultJson {
            $script:requestCalls++
            $values = if ($script:requestCalls % 2 -eq 0) {
                @([pscustomobject]@{ id = "https://archive-vault.vault.azure.net/secrets/archive-$($script:requestCalls)" })
            } else { @() }
            [pscustomobject]@{
                value = $values
                nextLink = "https://archive-vault.vault.azure.net/secrets?api-version=7.4&skiptoken=$($script:requestCalls)"
            }
        }

        { Get-KeyVaultSecretMetadata -VaultName 'archive-vault' } |
            Should -Throw '*pagination exceeded its page limit*'
        $script:requestCalls | Should -Be 5001
        $script:valueCalls | Should -Be 0
    }

    It 'rejects a repeated continuation before repeating the request' {
        Mock Invoke-KeyVaultJson {
            $script:requestCalls++
            [pscustomobject]@{
                value = @()
                nextLink = 'https://archive-vault.vault.azure.net/secrets?api-version=7.4&maxresults=25'
            }
        }

        { Get-KeyVaultSecretMetadata -VaultName 'archive-vault' } |
            Should -Throw '*repeated a continuation URI*'
        $script:requestCalls | Should -Be 1
    }

    It 'rejects a foreign-vault continuation before the next request' {
        Mock Invoke-KeyVaultJson {
            $script:requestCalls++
            [pscustomobject]@{
                value = @()
                nextLink = 'https://foreign-vault.vault.azure.net/secrets?api-version=7.4'
            }
        }

        { Get-KeyVaultSecretMetadata -VaultName 'archive-vault' } |
            Should -Throw '*metadata continuation URI is invalid*'
        $script:requestCalls | Should -Be 1
        $script:valueCalls | Should -Be 0
    }
}
