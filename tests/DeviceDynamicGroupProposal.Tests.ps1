Describe 'Offline device dynamic-group proposals' {
  BeforeAll {
    Set-StrictMode -Version Latest
    $script:repoRoot = Split-Path $PSScriptRoot -Parent
    $script:proposalPath = Join-Path $script:repoRoot 'scripts/New-DeviceDynamicGroupProposal.ps1'
    $tokens = $null
    $parseErrors = $null
    $ast = [Management.Automation.Language.Parser]::ParseFile($script:proposalPath, [ref] $tokens, [ref] $parseErrors)
    if ($parseErrors.Count -gt 0) { throw ($parseErrors | Out-String) }
    foreach ($definition in @($ast.EndBlock.Statements | Where-Object { $_ -is [Management.Automation.Language.FunctionDefinitionAst] })) {
      . ([scriptblock]::Create($definition.Extent.Text))
    }

    function Copy-ProposalFixture {
      param([Parameter(Mandatory = $true)][string] $Name)
      $source = Join-Path $script:repoRoot "tests/fixtures/$Name"
      $target = Join-Path $TestDrive $Name
      Copy-Item -LiteralPath $source -Destination $target
      return $target
    }

    function Write-ProposalFixture {
      param([Parameter(Mandatory = $true)][object] $Fixture, [Parameter(Mandatory = $true)][string] $Path)
      $Fixture | ConvertTo-Json -Depth 20 | Set-Content -LiteralPath $Path -Encoding utf8NoBOM
    }

    function Invoke-ProposalCliCapture {
      param(
        [Parameter(Mandatory = $true)][string] $FixturePath,
        [string] $Kind = 'Unmanaged'
      )

      $isUnmanaged = $Kind -ieq 'Unmanaged'
      $attributeNumber = if ($isUnmanaged) { 14 } else { 13 }
      $attributeOwner = if ($isUnmanaged) { 'fixture-admin/intune-state' } else { 'fixture-admin/defender-onboarding' }
      $evidenceSha256 = if ($isUnmanaged) { 'a' * 64 } else { 'b' * 64 }
      $output = & (Join-Path $PSHOME 'pwsh.exe') -NoProfile -File $script:proposalPath -Mode Preview -Kind $Kind `
        -FixturePath $FixturePath -TenantId $script:tenantId -AttributeNumber $attributeNumber `
        -AttributeOwner $attributeOwner -EvidenceSha256 $evidenceSha256 `
        -MaximumEvidenceAgeHours 24 -ReferenceTimeUtc $script:referenceTime 2>&1
      $exitCode = $LASTEXITCODE
      return [pscustomobject]@{
        ExitCode = $exitCode
        Output = @($output)
        Json = if ($exitCode -eq 0) { ($output -join "`n") | ConvertFrom-Json -DateKind String } else { $null }
      }
    }

    function Invoke-ProposalCli {
      param(
        [Parameter(Mandatory = $true)][string] $FixturePath,
        [string] $Kind = 'Unmanaged'
      )

      $capture = Invoke-ProposalCliCapture -FixturePath $FixturePath -Kind $Kind
      $capture.ExitCode | Should -Be 0
      return $capture.Json
    }

    $script:tenantId = '11111111-1111-1111-1111-111111111111'
    $script:referenceTime = [datetimeoffset] '2026-10-13T13:00:00Z'
  }

  It 'is inert by default without resolving a fixture' {
    $result = Invoke-DeviceDynamicGroupProposal -Mode Disabled -FixturePath (Join-Path $TestDrive 'missing.json')
    $result.status | Should -Be 'Disabled'
    $result.requiredGraphPermissions.Count | Should -Be 0
    $result.attributeMutation | Should -BeFalse
    $result.groupMutation | Should -BeFalse
    $result.defaultDisableIntegration | Should -BeFalse
  }

  It 'classifies complete Intune evidence and previews the existing attribute separately' {
    $path = Copy-ProposalFixture 'device-group-proposal-intune.json'
    $result = Invoke-DeviceDynamicGroupProposal -Mode Preview -Kind Unmanaged -FixturePath $path `
      -TenantId $script:tenantId -AttributeNumber 14 -AttributeOwner 'fixture-admin/intune-state' `
      -EvidenceSha256 ('a' * 64) -MaximumEvidenceAgeHours 24 -ReferenceTimeUtc $script:referenceTime

    $result.membershipRule | Should -Be 'device.extensionAttribute14 -eq "Unmanaged|none"'
    $result.syntaxValidatedOffline | Should -BeTrue
    $result.sourceTrust | Should -Be 'provided-fixture'
    $result.publisherPresent | Should -BeFalse
    $result.groupCreationReady | Should -BeFalse
    $result.counts.prospectiveIncluded | Should -Be 1
    $result.counts.prospectiveExcluded | Should -Be 1
    $result.counts.existingIncluded | Should -Be 1
    $result.results[1].prospective.reason | Should -Be 'CompleteInventoryNoMatch'
  }

  It 'requires an exact unique fresh CanBeOnboarded record for a prospective NotOnboarded member' {
    $path = Copy-ProposalFixture 'device-group-proposal-defender.json'
    $result = Invoke-DeviceDynamicGroupProposal -Mode Preview -Kind NotOnboarded -FixturePath $path `
      -TenantId $script:tenantId -AttributeNumber 13 -AttributeOwner 'fixture-admin/defender-onboarding' `
      -EvidenceSha256 ('b' * 64) -MaximumEvidenceAgeHours 24 -ReferenceTimeUtc $script:referenceTime

    $result.membershipRule | Should -Be 'device.extensionAttribute13 -eq "CanBeOnboarded"'
    $result.counts.prospectiveIncluded | Should -Be 1
    $result.counts.prospectiveExcluded | Should -Be 1
    $result.results[0].prospective.reason | Should -Be 'ExactCanBeOnboardedMatch'
    $result.results[1].prospective.reason | Should -Be 'ExactOnboardedMatch'
  }

  It 'does not present a prospective match as an existing attribute match' {
    $path = Copy-ProposalFixture 'device-group-proposal-defender.json'
    $fixture = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -DateKind String
    $fixture.devices[0].PSObject.Properties.Remove('existingAttribute')
    Write-ProposalFixture $fixture $path

    $result = Invoke-DeviceDynamicGroupProposal -Mode Preview -Kind NotOnboarded -FixturePath $path `
      -TenantId $script:tenantId -AttributeNumber 13 -AttributeOwner 'fixture-admin/defender-onboarding' `
      -EvidenceSha256 ('b' * 64) -MaximumEvidenceAgeHours 24 -ReferenceTimeUtc $script:referenceTime
    $result.results[0].prospective.state | Should -Be 'Included'
    $result.results[0].existingAttribute.state | Should -Be 'Unknown'
    $result.results[0].existingAttribute.reason | Should -Be 'AttributeMissing'
  }

  It 'refuses a globally unqualified fixture' -ForEach @(
    @{ Case = 'tenant'; Expected = 'TenantMismatch'; Change = { param($f) $f.tenantId = '99999999-9999-9999-9999-999999999999' } },
    @{ Case = 'unavailable'; Expected = 'CollectionUnavailable'; Change = { param($f) $f.source.collectionState = 'Unavailable' } },
    @{ Case = 'nodata'; Expected = 'CollectionNoData'; Change = { param($f) $f.source.collectionState = 'NoData' } },
    @{ Case = 'incomplete'; Expected = 'CollectionNotComplete'; Change = { param($f) $f.source.collectionState = 'Incomplete' } },
    @{ Case = 'stale'; Expected = 'StaleEvidence'; Change = { param($f) $f.source.collectedAtUtc = '2026-10-01T00:00:00Z' } },
    @{ Case = 'hash'; Expected = 'EvidenceHashMismatch'; Change = { param($f) $f.source.sha256 = ('c' * 64) } }
  ) {
    $path = Copy-ProposalFixture "device-group-proposal-intune.json"
    $fixture = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -DateKind String
    & $Change $fixture
    Write-ProposalFixture $fixture $path
    $result = Invoke-DeviceDynamicGroupProposal -Mode Preview -Kind Unmanaged -FixturePath $path `
      -TenantId $script:tenantId -AttributeNumber 14 -AttributeOwner 'fixture-admin/intune-state' `
      -EvidenceSha256 ('a' * 64) -MaximumEvidenceAgeHours 24 -ReferenceTimeUtc $script:referenceTime
    $result.counts.prospectiveIncluded | Should -Be 0
    $result.counts.prospectiveUnknown | Should -Be 2
    $result.results[0].prospective.reason | Should -Be $Expected
  }

  It 'refuses Defender absence, ambiguity, unsupported state, and stale machine evidence' -ForEach @(
    @{ Case = 'absence'; Expected = 'NoSourceMatch'; Change = { param($f) $f.source.records = @($f.source.records | Select-Object -Skip 1) } },
    @{ Case = 'ambiguity'; Expected = 'AmbiguousSourceMatch'; Change = { param($f) $f.source.records += $f.source.records[0].PSObject.Copy() } },
    @{ Case = 'unsupported'; Expected = 'UnsupportedSourceState'; Change = { param($f) $f.source.records[0].onboardingStatus = 'InsufficientInfo' } },
    @{ Case = 'stale'; Expected = 'StaleEvidence'; Change = { param($f) $f.source.records[0].lastSeen = '2026-10-01T00:00:00Z' } },
    @{ Case = 'malformed'; Expected = 'MalformedSourceRecord'; Change = { param($f) $f.source.records[0].id = 'not-a-machine-id' } }
  ) {
    $path = Copy-ProposalFixture 'device-group-proposal-defender.json'
    $fixture = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -DateKind String
    & $Change $fixture
    Write-ProposalFixture $fixture $path
    $result = Invoke-DeviceDynamicGroupProposal -Mode Preview -Kind NotOnboarded -FixturePath $path `
      -TenantId $script:tenantId -AttributeNumber 13 -AttributeOwner 'fixture-admin/defender-onboarding' `
      -EvidenceSha256 ('b' * 64) -MaximumEvidenceAgeHours 24 -ReferenceTimeUtc $script:referenceTime
    $result.results[0].prospective.state | Should -Be 'Unknown'
    $result.results[0].prospective.reason | Should -Be $Expected
  }

  It 'refuses duplicate Entra identity before evaluating its attributes' {
    $path = Copy-ProposalFixture 'device-group-proposal-intune.json'
    $fixture = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -DateKind String
    $fixture.devices[1].deviceId = $fixture.devices[0].deviceId
    Write-ProposalFixture $fixture $path
    $result = Invoke-DeviceDynamicGroupProposal -Mode Preview -Kind Unmanaged -FixturePath $path `
      -TenantId $script:tenantId -AttributeNumber 14 -AttributeOwner 'fixture-admin/intune-state' `
      -EvidenceSha256 ('a' * 64) -MaximumEvidenceAgeHours 24 -ReferenceTimeUtc $script:referenceTime
    $result.counts.prospectiveUnknown | Should -Be 2
    $result.results.prospective.reason | Should -Contain 'DuplicateEntraIdentity'
    $result.results.existingAttribute.reason | Should -Contain 'DuplicateEntraIdentity'
  }

  It 'refuses scalar collection shapes without converting them into positive rows' -ForEach @(
    @{ Case = 'records object'; Expected = 'RecordsNotArray'; Change = { param($f) $f.source.records = $f.source.records[0] } },
    @{ Case = 'devices object'; Expected = 'DevicesNotArray'; Change = { param($f) $f.devices = $f.devices[1] } }
  ) {
    $path = Copy-ProposalFixture 'device-group-proposal-intune.json'
    $fixture = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -DateKind String
    & $Change $fixture
    Write-ProposalFixture $fixture $path
    $result = Invoke-DeviceDynamicGroupProposal -Mode Preview -Kind Unmanaged -FixturePath $path `
      -TenantId $script:tenantId -AttributeNumber 14 -AttributeOwner 'fixture-admin/intune-state' `
      -EvidenceSha256 ('a' * 64) -MaximumEvidenceAgeHours 24 -ReferenceTimeUtc $script:referenceTime
    $result.counts.prospectiveIncluded | Should -Be 0
    $result.counts.prospectiveUnknown | Should -BeGreaterThan 0
    $result.results[0].prospective.reason | Should -Be $Expected
  }

  It 'keeps a valid empty Intune array distinct from missing or scalar records' -ForEach @(
    @{ Case = 'empty'; ExpectedIncluded = 2; ExpectedReason = 'CompleteInventoryNoMatch'; Change = { param($f) $f.source.records = @() } },
    @{ Case = 'null'; ExpectedIncluded = 0; ExpectedReason = 'RecordsNotArray'; Change = { param($f) $f.source.records = $null } },
    @{ Case = 'string'; ExpectedIncluded = 0; ExpectedReason = 'RecordsNotArray'; Change = { param($f) $f.source.records = '' } }
  ) {
    $path = Copy-ProposalFixture 'device-group-proposal-intune.json'
    $fixture = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -DateKind String
    & $Change $fixture
    Write-ProposalFixture $fixture $path
    $result = Invoke-DeviceDynamicGroupProposal -Mode Preview -Kind Unmanaged -FixturePath $path `
      -TenantId $script:tenantId -AttributeNumber 14 -AttributeOwner 'fixture-admin/intune-state' `
      -EvidenceSha256 ('a' * 64) -MaximumEvidenceAgeHours 24 -ReferenceTimeUtc $script:referenceTime
    $result.counts.prospectiveIncluded | Should -Be $ExpectedIncluded
    $result.results[0].prospective.reason | Should -Be $ExpectedReason
  }

  It 'refuses a singleton-array device identity rather than coercing it to a GUID' {
    $path = Copy-ProposalFixture 'device-group-proposal-intune.json'
    $fixture = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -DateKind String
    $fixture.devices[1].deviceId = @($fixture.devices[1].deviceId)
    Write-ProposalFixture $fixture $path
    $result = Invoke-DeviceDynamicGroupProposal -Mode Preview -Kind Unmanaged -FixturePath $path `
      -TenantId $script:tenantId -AttributeNumber 14 -AttributeOwner 'fixture-admin/intune-state' `
      -EvidenceSha256 ('a' * 64) -MaximumEvidenceAgeHours 24 -ReferenceTimeUtc $script:referenceTime
    $result.counts.prospectiveIncluded | Should -Be 0
    $result.results[1].prospective.reason | Should -Be 'MissingDeviceIdentity'
    $result.results[1].existingAttribute.reason | Should -Be 'MissingDeviceIdentity'
  }

  It 'refuses an unqualified existing attribute assertion' -ForEach @(
    @{ Case = 'owner'; Expected = 'AttributeUnowned'; Change = { param($a) $a.owner = 'another-owner' } },
    @{ Case = 'stale'; Expected = 'AttributeStale'; Change = { param($a) $a.observedAtUtc = '2026-10-01T00:00:00Z' } },
    @{ Case = 'hash'; Expected = 'AttributeHashMismatch'; Change = { param($a) $a.sourceSha256 = ('c' * 64) } },
    @{ Case = 'slot'; Expected = 'AttributeWrongSlot'; Change = { param($a) $a.number = 12 } }
  ) {
    $path = Copy-ProposalFixture 'device-group-proposal-intune.json'
    $fixture = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -DateKind String
    & $Change $fixture.devices[0].existingAttribute
    Write-ProposalFixture $fixture $path
    $result = Invoke-DeviceDynamicGroupProposal -Mode Preview -Kind Unmanaged -FixturePath $path `
      -TenantId $script:tenantId -AttributeNumber 14 -AttributeOwner 'fixture-admin/intune-state' `
      -EvidenceSha256 ('a' * 64) -MaximumEvidenceAgeHours 24 -ReferenceTimeUtc $script:referenceTime
    $result.results[0].existingAttribute.state | Should -Be 'Unknown'
    $result.results[0].existingAttribute.reason | Should -Be $Expected
  }

  It 'returns bounded CLI output for malformed attribute slot types without changing the prospective result' -ForEach @(
    @{ Case = 'text'; Value = 'not-a-number' },
    @{ Case = 'numeric string'; Value = '14' }
  ) {
    $path = Copy-ProposalFixture 'device-group-proposal-intune.json'
    $fixture = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -DateKind String
    $fixture.devices[1].existingAttribute.number = $Value
    Write-ProposalFixture $fixture $path
    $result = Invoke-ProposalCli -FixturePath $path
    $result.results[1].prospective.state | Should -Be 'Included'
    $result.results[1].existingAttribute.state | Should -Be 'Unknown'
    $result.results[1].existingAttribute.reason | Should -Be 'AttributeSlotInvalid'
  }

  It 'normalizes case-insensitive CLI kind input before rule round-trip validation' {
    $path = Copy-ProposalFixture 'device-group-proposal-intune.json'
    $result = Invoke-ProposalCli -FixturePath $path -Kind 'unmanaged'
    $result.proposalKind | Should -Be 'Unmanaged'
    $result.membershipRule | Should -Be 'device.extensionAttribute14 -eq "Unmanaged|none"'
  }

  It 'refuses every remaining singleton-array scalar in helper and CLI paths' -ForEach @(
    @{ Case = 'machine id'; Expected = 'MalformedSourceRecord'; Change = { param($f) $f.source.records[0].id = @($f.source.records[0].id) } },
    @{ Case = 'onboarding status'; Expected = 'MalformedSourceRecord'; Change = { param($f) $f.source.records[0].onboardingStatus = @($f.source.records[0].onboardingStatus) } },
    @{ Case = 'source type'; Expected = 'SourceTypeInvalid'; Change = { param($f) $f.source.type = @($f.source.type) } },
    @{ Case = 'collection state'; Expected = 'CollectionStateInvalid'; Change = { param($f) $f.source.collectionState = @($f.source.collectionState) } }
  ) {
    $path = Copy-ProposalFixture 'device-group-proposal-defender.json'
    $fixture = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -DateKind String
    & $Change $fixture
    Write-ProposalFixture $fixture $path

    $helper = Invoke-DeviceDynamicGroupProposal -Mode Preview -Kind NotOnboarded -FixturePath $path `
      -TenantId $script:tenantId -AttributeNumber 13 -AttributeOwner 'fixture-admin/defender-onboarding' `
      -EvidenceSha256 ('b' * 64) -MaximumEvidenceAgeHours 24 -ReferenceTimeUtc $script:referenceTime
    $helper.counts.prospectiveIncluded | Should -Be 0
    $helper.results[0].prospective.state | Should -Be 'Unknown'
    $helper.results[0].prospective.reason | Should -Be $Expected

    $cli = Invoke-ProposalCliCapture -FixturePath $path -Kind NotOnboarded
    $cli.ExitCode | Should -Be 0
    $cli.Json.counts.prospectiveIncluded | Should -Be 0
    $cli.Json.results[0].prospective.reason | Should -Be $Expected
  }

  It 'rejects array-shaped top-level contract scalars in helper and CLI paths' -ForEach @(
    @{ Case = 'schema version'; Change = { param($f) $f.schemaVersion = @($f.schemaVersion) } },
    @{ Case = 'fixture kind'; Change = { param($f) $f.kind = @($f.kind) } }
  ) {
    $path = Copy-ProposalFixture 'device-group-proposal-defender.json'
    $fixture = Get-Content -LiteralPath $path -Raw | ConvertFrom-Json -DateKind String
    & $Change $fixture
    Write-ProposalFixture $fixture $path

    { Invoke-DeviceDynamicGroupProposal -Mode Preview -Kind NotOnboarded -FixturePath $path `
        -TenantId $script:tenantId -AttributeNumber 13 -AttributeOwner 'fixture-admin/defender-onboarding' `
        -EvidenceSha256 ('b' * 64) -MaximumEvidenceAgeHours 24 -ReferenceTimeUtc $script:referenceTime } |
      Should -Throw '*contract is unsupported*'
    $cli = Invoke-ProposalCliCapture -FixturePath $path -Kind NotOnboarded
    $cli.ExitCode | Should -Be 1
  }

  It 'does not unwrap a singleton top-level JSON array in helper or CLI paths' {
    $path = Copy-ProposalFixture 'device-group-proposal-defender.json'
    $raw = Get-Content -LiteralPath $path -Raw
    Set-Content -LiteralPath $path -Value "[$raw]" -Encoding utf8NoBOM

    { Invoke-DeviceDynamicGroupProposal -Mode Preview -Kind NotOnboarded -FixturePath $path `
        -TenantId $script:tenantId -AttributeNumber 13 -AttributeOwner 'fixture-admin/defender-onboarding' `
        -EvidenceSha256 ('b' * 64) -MaximumEvidenceAgeHours 24 -ReferenceTimeUtc $script:referenceTime } |
      Should -Throw '*contract is unsupported*'
    $cli = Invoke-ProposalCliCapture -FixturePath $path -Kind NotOnboarded
    $cli.ExitCode | Should -Be 1
  }

  It 'accepts generic dictionary fixture values and rejects rules outside its grammar' {
    $dictionary = [Collections.Generic.Dictionary[string, object]]::new()
    $dictionary['name'] = 'value'
    (Get-ProposalObjectValue -InputObject $dictionary -Name 'name') | Should -Be 'value'
    (ConvertFrom-DeviceDynamicGroupRule 'device.extensionAttribute15 -eq "CanBeOnboarded"').kind | Should -Be 'NotOnboarded'
    { ConvertFrom-DeviceDynamicGroupRule 'device.managementType -eq null' } | Should -Throw '*outside the supported*'
    { ConvertFrom-DeviceDynamicGroupRule 'device.extensionAttribute16 -eq "CanBeOnboarded"' } | Should -Throw '*outside the supported*'
  }

  It 'contains no provider or lifecycle integration surface' {
    $source = Get-Content -LiteralPath $script:proposalPath -Raw
    $source | Should -Not -Match 'graph\.microsoft\.com|api\.security\.microsoft\.com|Invoke-RestMethod|Invoke-GraphJson|Get-DeviceLifecycleAction'
    $source | Should -Match "requiredGraphPermissions = @\(\)"
  }

  It 'keeps the committed fixtures inside the bounded JSON contract' {
    $schemaPath = Join-Path $script:repoRoot 'schemas/device-dynamic-group-proposal-fixture.schema.json'
    foreach ($name in @('device-group-proposal-intune.json', 'device-group-proposal-defender.json')) {
      Get-Content -LiteralPath (Join-Path $script:repoRoot "tests/fixtures/$name") -Raw |
        Test-Json -SchemaFile $schemaPath | Should -BeTrue
    }
  }
}
