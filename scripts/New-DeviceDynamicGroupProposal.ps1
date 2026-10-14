[CmdletBinding()]
param(
  [ValidateSet('Disabled', 'Preview')]
  [string] $Mode = 'Disabled',
  [ValidateSet('Unmanaged', 'NotOnboarded')]
  [string] $Kind,
  [string] $FixturePath,
  [string] $TenantId,
  [ValidateRange(0, 15)]
  [int] $AttributeNumber = 0,
  [string] $AttributeOwner,
  [string] $EvidenceSha256,
  [ValidateRange(0, 87600)]
  [int] $MaximumEvidenceAgeHours = 0,
  [datetimeoffset] $ReferenceTimeUtc
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-ProposalObjectValue {
  param(
    [AllowNull()][object] $InputObject,
    [Parameter(Mandatory = $true)][string] $Name
  )

  if ($null -eq $InputObject) { return $null }
  if ($InputObject -is [System.Collections.IDictionary]) {
    foreach ($key in $InputObject.Keys) {
      if ([string] $key -ceq $Name) {
        $value = $InputObject[$key]
        if ($value -is [System.Array]) { return ,$value }
        return $value
      }
    }
    return $null
  }

  $property = $InputObject.PSObject.Properties[$Name]
  if ($null -eq $property) { return $null }
  if ($property.Value -is [System.Array]) { return ,$property.Value }
  return $property.Value
}

function Get-NormalizedProposalGuid {
  param([AllowNull()][object] $Value)

  if ($Value -isnot [string]) { return $null }
  $parsed = [guid]::Empty
  if (-not [guid]::TryParse($Value, [ref] $parsed)) { return $null }
  return $parsed.ToString('D').ToLowerInvariant()
}

function Get-NormalizedProposalHash {
  param([AllowNull()][object] $Value)

  if ($Value -isnot [string] -or $Value -notmatch '^[0-9a-fA-F]{64}$') { return $null }
  return $Value.ToLowerInvariant()
}

function Test-ProposalObject {
  param([AllowNull()][object] $Value)

  return $null -ne $Value -and ($Value -is [System.Collections.IDictionary] -or $Value -is [pscustomobject])
}

function Test-ProposalInteger {
  param([AllowNull()][object] $Value)

  return $Value -is [byte] -or $Value -is [sbyte] -or
    $Value -is [int16] -or $Value -is [uint16] -or
    $Value -is [int32] -or $Value -is [uint32] -or
    $Value -is [int64] -or $Value -is [uint64]
}

function Get-ProposalTimestampState {
  param(
    [AllowNull()][object] $Value,
    [Parameter(Mandatory = $true)][datetimeoffset] $ReferenceTime,
    [Parameter(Mandatory = $true)][timespan] $MaximumAge
  )

  $parsed = [datetimeoffset]::MinValue
  if ($Value -isnot [string] -or -not [datetimeoffset]::TryParse($Value, [Globalization.CultureInfo]::InvariantCulture, [Globalization.DateTimeStyles]::AssumeUniversal, [ref] $parsed)) {
    return 'InvalidEvidenceTime'
  }
  $parsed = $parsed.ToUniversalTime()
  if ($parsed -gt $ReferenceTime.ToUniversalTime()) { return 'FutureEvidence' }
  if (($ReferenceTime.ToUniversalTime() - $parsed) -gt $MaximumAge) { return 'StaleEvidence' }
  return 'Fresh'
}

function Get-DeviceDynamicGroupRule {
  param(
    [Parameter(Mandatory = $true)][ValidateSet('Unmanaged', 'NotOnboarded')][string] $Kind,
    [Parameter(Mandatory = $true)][ValidateRange(1, 15)][int] $AttributeNumber
  )

  $canonicalKind = if ($Kind -ieq 'Unmanaged') { 'Unmanaged' } else { 'NotOnboarded' }
  $literal = if ($canonicalKind -eq 'Unmanaged') { 'Unmanaged|none' } else { 'CanBeOnboarded' }
  return "device.extensionAttribute$AttributeNumber -eq `"$literal`""
}

function ConvertFrom-DeviceDynamicGroupRule {
  param([Parameter(Mandatory = $true)][string] $Rule)

  $match = [regex]::Match($Rule, '^device\.extensionAttribute(?<slot>[1-9]|1[0-5]) -eq "(?<value>Unmanaged\|none|CanBeOnboarded)"$', [Text.RegularExpressions.RegexOptions]::CultureInvariant)
  if (-not $match.Success) { throw 'The proposal rule is outside the supported device rule grammar.' }

  $value = $match.Groups['value'].Value
  return [pscustomobject][ordered]@{
    attributeNumber = [int] $match.Groups['slot'].Value
    value = $value
    kind = if ($value -eq 'Unmanaged|none') { 'Unmanaged' } else { 'NotOnboarded' }
  }
}

function New-DisabledDeviceDynamicGroupProposal {
  return [pscustomobject][ordered]@{
    schemaVersion = '1.0'
    kind = 'device-dynamic-group-proposal'
    status = 'Disabled'
    sourceTrust = 'none'
    publisherPresent = $false
    groupCreationReady = $false
    groupCreationReason = 'ProposalOnly'
    defaultDisableIntegration = $false
    attributeMutation = $false
    groupMutation = $false
    requiredGraphPermissions = @()
    results = @()
  }
}

function Get-ProposalExistingPreview {
  param(
    [AllowNull()][object] $ExistingAttribute,
    [Parameter(Mandatory = $true)][int] $AttributeNumber,
    [Parameter(Mandatory = $true)][string] $AttributeOwner,
    [Parameter(Mandatory = $true)][string] $EvidenceSha256,
    [Parameter(Mandatory = $true)][string] $ExpectedValue,
    [Parameter(Mandatory = $true)][datetimeoffset] $ReferenceTime,
    [Parameter(Mandatory = $true)][timespan] $MaximumAge,
    [AllowNull()][string] $FixtureReason
  )

  if (-not [string]::IsNullOrWhiteSpace($FixtureReason)) { return [pscustomobject]@{ state = 'Unknown'; reason = $FixtureReason } }
  if ($null -eq $ExistingAttribute) { return [pscustomobject]@{ state = 'Unknown'; reason = 'AttributeMissing' } }
  if (-not (Test-ProposalObject $ExistingAttribute)) { return [pscustomobject]@{ state = 'Unknown'; reason = 'AttributeMalformed' } }
  $attributeNumberValue = Get-ProposalObjectValue $ExistingAttribute 'number'
  if (-not (Test-ProposalInteger $attributeNumberValue)) { return [pscustomobject]@{ state = 'Unknown'; reason = 'AttributeSlotInvalid' } }
  if ($attributeNumberValue -lt 1 -or $attributeNumberValue -gt 15 -or $attributeNumberValue -ne $AttributeNumber) { return [pscustomobject]@{ state = 'Unknown'; reason = 'AttributeWrongSlot' } }
  $attributeOwnerValue = Get-ProposalObjectValue $ExistingAttribute 'owner'
  if ($attributeOwnerValue -isnot [string] -or $attributeOwnerValue -cne $AttributeOwner) { return [pscustomobject]@{ state = 'Unknown'; reason = 'AttributeUnowned' } }
  if ((Get-NormalizedProposalHash (Get-ProposalObjectValue $ExistingAttribute 'sourceSha256')) -cne $EvidenceSha256) { return [pscustomobject]@{ state = 'Unknown'; reason = 'AttributeHashMismatch' } }

  $timeState = Get-ProposalTimestampState -Value (Get-ProposalObjectValue $ExistingAttribute 'observedAtUtc') -ReferenceTime $ReferenceTime -MaximumAge $MaximumAge
  if ($timeState -ne 'Fresh') {
    $reason = if ($timeState -eq 'StaleEvidence') { 'AttributeStale' } else { $timeState }
    return [pscustomobject]@{ state = 'Unknown'; reason = $reason }
  }

  $value = Get-ProposalObjectValue $ExistingAttribute 'value'
  if ($value -isnot [string]) { return [pscustomobject]@{ state = 'Unknown'; reason = 'AttributeValueInvalid' } }
  if ($value -ceq $ExpectedValue) { return [pscustomobject]@{ state = 'Included'; reason = 'ExactAttributeMatch' } }
  return [pscustomobject]@{ state = 'Excluded'; reason = 'AttributeValueMismatch' }
}

function Invoke-DeviceDynamicGroupProposal {
  [CmdletBinding()]
  param(
    [ValidateSet('Disabled', 'Preview')][string] $Mode = 'Disabled',
    [ValidateSet('Unmanaged', 'NotOnboarded')][string] $Kind,
    [string] $FixturePath,
    [string] $TenantId,
    [ValidateRange(0, 15)][int] $AttributeNumber = 0,
    [string] $AttributeOwner,
    [string] $EvidenceSha256,
    [ValidateRange(0, 87600)][int] $MaximumEvidenceAgeHours = 0,
    [datetimeoffset] $ReferenceTimeUtc
  )

  if ($Mode -eq 'Disabled') { return New-DisabledDeviceDynamicGroupProposal }

  if ([string]::IsNullOrWhiteSpace($Kind) -or [string]::IsNullOrWhiteSpace($FixturePath) -or
      [string]::IsNullOrWhiteSpace($TenantId) -or [string]::IsNullOrWhiteSpace($AttributeOwner) -or
      [string]::IsNullOrWhiteSpace($EvidenceSha256) -or $AttributeNumber -le 0 -or
      $MaximumEvidenceAgeHours -le 0 -or $ReferenceTimeUtc -eq [datetimeoffset]::MinValue) {
    throw 'Preview mode requires kind, fixture, tenant, owned slot, owner, evidence hash, maximum age, and reference time inputs.'
  }
  if ($ReferenceTimeUtc.Offset -ne [timespan]::Zero) { throw 'ReferenceTimeUtc must use a UTC offset.' }
  $canonicalKind = if ($Kind -ieq 'Unmanaged') { 'Unmanaged' } else { 'NotOnboarded' }
  $normalizedTenantId = Get-NormalizedProposalGuid $TenantId
  if ($null -eq $normalizedTenantId) { throw 'TenantId must be a GUID.' }
  if ($AttributeOwner -notmatch '^[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$') { throw 'AttributeOwner is invalid.' }
  $normalizedEvidenceHash = Get-NormalizedProposalHash $EvidenceSha256
  if ($null -eq $normalizedEvidenceHash) { throw 'EvidenceSha256 must be a SHA-256 hexadecimal value.' }

  $resolvedFixture = $ExecutionContext.SessionState.Path.GetUnresolvedProviderPathFromPSPath($FixturePath)
  if (-not (Test-Path -LiteralPath $resolvedFixture -PathType Leaf)) { throw 'The proposal fixture was not found.' }
  $fixtureFile = Get-Item -LiteralPath $resolvedFixture
  if ($fixtureFile.Length -gt 1048576) { throw 'The proposal fixture exceeds the 1 MiB limit.' }
  try { $fixture = Get-Content -LiteralPath $resolvedFixture -Raw | ConvertFrom-Json -NoEnumerate -DateKind String -Depth 30 }
  catch { throw 'The proposal fixture is not valid bounded JSON.' }

  if (-not (Test-ProposalObject $fixture)) { throw 'The proposal fixture contract is unsupported.' }
  $fixtureSchemaVersion = Get-ProposalObjectValue $fixture 'schemaVersion'
  $fixtureKind = Get-ProposalObjectValue $fixture 'kind'
  if ($fixtureSchemaVersion -isnot [string] -or $fixtureSchemaVersion -cne '1.0' -or
      $fixtureKind -isnot [string] -or $fixtureKind -cne 'device-dynamic-group-proposal-fixture') {
    throw 'The proposal fixture contract is unsupported.'
  }
  $rawDevices = Get-ProposalObjectValue $fixture 'devices'
  $deviceCollectionValid = $rawDevices -is [System.Array]
  [object[]] $devices = if ($deviceCollectionValid) { @($rawDevices) } elseif ($null -ne $rawDevices) { @($rawDevices) } else { @() }
  $source = Get-ProposalObjectValue $fixture 'source'
  $rawRecords = Get-ProposalObjectValue $source 'records'
  $recordCollectionValid = $rawRecords -is [System.Array]
  [object[]] $records = if ($recordCollectionValid) { @($rawRecords) } else { @() }
  if (@($devices).Count -gt 10000 -or @($records).Count -gt 10000) { throw 'The proposal fixture exceeds the 10,000 row limit.' }

  $expectedSourceType = if ($canonicalKind -eq 'Unmanaged') { 'IntuneManagedDevices' } else { 'DefenderMachines' }
  $maximumAge = [timespan]::FromHours($MaximumEvidenceAgeHours)
  $globalReason = $null
  if (-not $deviceCollectionValid) { $globalReason = 'DevicesNotArray' }
  elseif (-not (Test-ProposalObject $source)) { $globalReason = 'SourceMalformed' }
  elseif (-not $recordCollectionValid) { $globalReason = 'RecordsNotArray' }
  elseif ((Get-NormalizedProposalGuid (Get-ProposalObjectValue $fixture 'tenantId')) -cne $normalizedTenantId) { $globalReason = 'TenantMismatch' }
  else {
    $sourceType = Get-ProposalObjectValue $source 'type'
    $collectionState = Get-ProposalObjectValue $source 'collectionState'
  }
  if ($null -eq $globalReason -and $sourceType -isnot [string]) { $globalReason = 'SourceTypeInvalid' }
  elseif ($null -eq $globalReason -and $sourceType -cne $expectedSourceType) { $globalReason = 'WrongSourceType' }
  elseif ($null -eq $globalReason -and $collectionState -isnot [string]) { $globalReason = 'CollectionStateInvalid' }
  elseif ($null -eq $globalReason -and $collectionState -cne 'Complete') {
    $globalReason = switch ($collectionState) {
      'Unavailable' { 'CollectionUnavailable' }
      'NoData' { 'CollectionNoData' }
      default { 'CollectionNotComplete' }
    }
  }
  elseif ($null -eq $globalReason -and (Get-NormalizedProposalHash (Get-ProposalObjectValue $source 'sha256')) -cne $normalizedEvidenceHash) { $globalReason = 'EvidenceHashMismatch' }
  elseif ($null -eq $globalReason) {
    $sourceTimeState = Get-ProposalTimestampState -Value (Get-ProposalObjectValue $source 'collectedAtUtc') -ReferenceTime $ReferenceTimeUtc -MaximumAge $maximumAge
    if ($sourceTimeState -ne 'Fresh') { $globalReason = $sourceTimeState }
  }

  $normalizedDevices = @()
  foreach ($device in $devices) {
    $normalizedDevices += [pscustomobject]@{
      Raw = $device
      WellFormed = Test-ProposalObject $device
      EntraObjectId = Get-NormalizedProposalGuid (Get-ProposalObjectValue $device 'entraObjectId')
      DeviceId = Get-NormalizedProposalGuid (Get-ProposalObjectValue $device 'deviceId')
    }
  }
  $duplicateEntraIds = @($normalizedDevices | Where-Object { $null -ne $_.EntraObjectId } | Group-Object EntraObjectId | Where-Object Count -gt 1 | ForEach-Object Name)
  $duplicateDeviceIds = @($normalizedDevices | Where-Object { $null -ne $_.DeviceId } | Group-Object DeviceId | Where-Object Count -gt 1 | ForEach-Object Name)

  $expectedValue = if ($canonicalKind -eq 'Unmanaged') { 'Unmanaged|none' } else { 'CanBeOnboarded' }
  $rule = Get-DeviceDynamicGroupRule -Kind $canonicalKind -AttributeNumber $AttributeNumber
  $parsedRule = ConvertFrom-DeviceDynamicGroupRule -Rule $rule
  if ($parsedRule.attributeNumber -ne $AttributeNumber -or $parsedRule.kind -cne $canonicalKind -or $parsedRule.value -cne $expectedValue) {
    throw 'The generated proposal rule did not round-trip through the supported grammar.'
  }

  $results = @()
  foreach ($entry in @($normalizedDevices | Sort-Object EntraObjectId, DeviceId)) {
    $prospectiveState = 'Unknown'
    $prospectiveReason = $globalReason
    if ($null -eq $prospectiveReason) {
      if (-not $entry.WellFormed) { $prospectiveReason = 'MalformedDeviceRecord' }
      elseif ($null -eq $entry.EntraObjectId -or $null -eq $entry.DeviceId) { $prospectiveReason = 'MissingDeviceIdentity' }
      elseif ($duplicateEntraIds -contains $entry.EntraObjectId -or $duplicateDeviceIds -contains $entry.DeviceId) { $prospectiveReason = 'DuplicateEntraIdentity' }
      else {
        $sourceMatches = @()
        $malformedRecord = $false
        foreach ($record in $records) {
          if (-not (Test-ProposalObject $record)) { $malformedRecord = $true; continue }
          $sourceDeviceId = if ($canonicalKind -eq 'Unmanaged') {
            Get-NormalizedProposalGuid (Get-ProposalObjectValue $record 'azureADDeviceId')
          } else {
            Get-NormalizedProposalGuid (Get-ProposalObjectValue $record 'aadDeviceId')
          }
          $sourceRecordId = Get-ProposalObjectValue $record 'id'
          $sourceRecordIdValid = if ($canonicalKind -eq 'Unmanaged') {
            $null -ne (Get-NormalizedProposalGuid $sourceRecordId)
          } else {
            $sourceRecordId -is [string] -and $sourceRecordId -match '^[0-9a-fA-F]{40}$'
          }
          if ($null -eq $sourceDeviceId -or -not $sourceRecordIdValid) { $malformedRecord = $true; continue }
          if ($sourceDeviceId -ceq $entry.DeviceId) { $sourceMatches += $record }
        }

        if ($malformedRecord) { $prospectiveReason = 'MalformedSourceRecord' }
        elseif ($sourceMatches.Count -gt 1) { $prospectiveReason = 'AmbiguousSourceMatch' }
        elseif ($canonicalKind -eq 'Unmanaged') {
          if ($sourceMatches.Count -eq 0) { $prospectiveState = 'Included'; $prospectiveReason = 'CompleteInventoryNoMatch' }
          else { $prospectiveState = 'Excluded'; $prospectiveReason = 'ExactManagedDeviceMatch' }
        }
        elseif ($sourceMatches.Count -eq 0) { $prospectiveReason = 'NoSourceMatch' }
        else {
          $machine = $sourceMatches[0]
          $machineId = Get-ProposalObjectValue $machine 'id'
          if ($machineId -isnot [string] -or $machineId -notmatch '^[0-9a-fA-F]{40}$') { $prospectiveReason = 'MalformedSourceRecord' }
          else {
            $machineTimeState = Get-ProposalTimestampState -Value (Get-ProposalObjectValue $machine 'lastSeen') -ReferenceTime $ReferenceTimeUtc -MaximumAge $maximumAge
            if ($machineTimeState -ne 'Fresh') { $prospectiveReason = $machineTimeState }
            else {
              $onboardingStatus = Get-ProposalObjectValue $machine 'onboardingStatus'
              if ($onboardingStatus -isnot [string]) { $prospectiveReason = 'MalformedSourceRecord' }
              elseif ($onboardingStatus -ceq 'CanBeOnboarded') { $prospectiveState = 'Included'; $prospectiveReason = 'ExactCanBeOnboardedMatch' }
              elseif ($onboardingStatus -ceq 'onboarded') { $prospectiveState = 'Excluded'; $prospectiveReason = 'ExactOnboardedMatch' }
              else { $prospectiveReason = 'UnsupportedSourceState' }
            }
          }
        }
      }
    }

    $existingFixtureReason = $globalReason
    if ($null -eq $existingFixtureReason) {
      if (-not $entry.WellFormed) { $existingFixtureReason = 'MalformedDeviceRecord' }
      elseif ($null -eq $entry.EntraObjectId -or $null -eq $entry.DeviceId) { $existingFixtureReason = 'MissingDeviceIdentity' }
      elseif ($duplicateEntraIds -contains $entry.EntraObjectId -or $duplicateDeviceIds -contains $entry.DeviceId) { $existingFixtureReason = 'DuplicateEntraIdentity' }
    }
    $existing = Get-ProposalExistingPreview -ExistingAttribute (Get-ProposalObjectValue $entry.Raw 'existingAttribute') `
      -AttributeNumber $AttributeNumber -AttributeOwner $AttributeOwner -EvidenceSha256 $normalizedEvidenceHash `
      -ExpectedValue $expectedValue -ReferenceTime $ReferenceTimeUtc -MaximumAge $maximumAge -FixtureReason $existingFixtureReason
    $results += [pscustomobject][ordered]@{
      entraObjectId = $entry.EntraObjectId
      deviceId = $entry.DeviceId
      prospective = [ordered]@{ state = $prospectiveState; reason = $prospectiveReason }
      existingAttribute = [ordered]@{ state = $existing.state; reason = $existing.reason }
    }
  }

  $counts = [ordered]@{
    inputDeviceCount = $results.Count
    prospectiveIncluded = @($results | Where-Object { $_.prospective.state -eq 'Included' }).Count
    prospectiveExcluded = @($results | Where-Object { $_.prospective.state -eq 'Excluded' }).Count
    prospectiveUnknown = @($results | Where-Object { $_.prospective.state -eq 'Unknown' }).Count
    existingIncluded = @($results | Where-Object { $_.existingAttribute.state -eq 'Included' }).Count
    existingExcluded = @($results | Where-Object { $_.existingAttribute.state -eq 'Excluded' }).Count
    existingUnknown = @($results | Where-Object { $_.existingAttribute.state -eq 'Unknown' }).Count
  }
  $reasonCounts = [ordered]@{}
  $allReasons = foreach ($result in $results) {
    $result.prospective.reason
    $result.existingAttribute.reason
  }
  foreach ($reason in @($allReasons | Sort-Object -Unique)) {
    if ([string]::IsNullOrWhiteSpace([string] $reason)) { continue }
    $reasonCounts[$reason] = @($results | Where-Object { $_.prospective.reason -eq $reason -or $_.existingAttribute.reason -eq $reason }).Count
  }

  return [pscustomobject][ordered]@{
    schemaVersion = '1.0'
    kind = 'device-dynamic-group-proposal'
    status = 'Preview'
    proposalKind = $canonicalKind
    sourceTrust = 'provided-fixture'
    tenantId = $normalizedTenantId
    attribute = [ordered]@{ number = $AttributeNumber; owner = $AttributeOwner; expectedValue = $expectedValue }
    evidence = [ordered]@{ sha256 = $normalizedEvidenceHash; maximumAgeHours = $MaximumEvidenceAgeHours; referenceTimeUtc = $ReferenceTimeUtc.ToUniversalTime().ToString('o') }
    membershipRule = $rule
    syntaxValidatedOffline = $true
    publisherPresent = $false
    groupCreationReady = $false
    groupCreationReason = 'ProposalOnly'
    defaultDisableIntegration = $false
    attributeMutation = $false
    groupMutation = $false
    requiredGraphPermissions = @()
    counts = $counts
    reasonCounts = $reasonCounts
    results = $results
  }
}

if ($Mode -eq 'Disabled') {
  New-DisabledDeviceDynamicGroupProposal | ConvertTo-Json -Depth 12
}
else {
  $invokeParameters = @{
    Mode = $Mode
    Kind = $Kind
    FixturePath = $FixturePath
    TenantId = $TenantId
    AttributeNumber = $AttributeNumber
    AttributeOwner = $AttributeOwner
    EvidenceSha256 = $EvidenceSha256
    MaximumEvidenceAgeHours = $MaximumEvidenceAgeHours
    ReferenceTimeUtc = $ReferenceTimeUtc
  }
  Invoke-DeviceDynamicGroupProposal @invokeParameters | ConvertTo-Json -Depth 12
}
