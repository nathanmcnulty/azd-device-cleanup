param(
  [string] $KeyVaultName = '',
  [string] $Search = '',
  [string] $DisplayName = '',
  [string] $DeviceId = '',
  [string] $EntraObjectId = '',
  [string] $SerialNumber = '',
  [string] $IntuneManagedDeviceId = '',
  [string] $DefenderMachineId = '',
  [string] $SecretName = '',
  [switch] $ShowRecoveryMaterial,
  [switch] $AsJson
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Ensure-AzureCli {
  if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw 'Azure CLI is required to retrieve archived devices.'
  }
}

function Get-AzdEnvironmentValues {
  param(
    [Parameter(Mandatory = $true)]
    [string] $RepositoryRoot
  )

  Push-Location $RepositoryRoot
  try {
    $values = @{}
    foreach ($line in @(azd env get-values 2>$null)) {
      if ($line -match '^([A-Z0-9_]+)=(.*)$') {
        $name = $matches[1]
        $value = $matches[2].Trim()
        if ($value.StartsWith('"') -and $value.EndsWith('"')) {
          $value = $value.Substring(1, $value.Length - 2)
        }

        $values[$name] = $value
      }
    }

    return $values
  }
  finally {
    Pop-Location
  }
}

function Get-DefaultKeyVaultName {
  param(
    [Parameter(Mandatory = $true)]
    [string] $RepositoryRoot
  )

  $envValues = Get-AzdEnvironmentValues -RepositoryRoot $RepositoryRoot
  if ($envValues.ContainsKey('DEVICE_ARCHIVE_KEY_VAULT_NAME') -and -not [string]::IsNullOrWhiteSpace($envValues['DEVICE_ARCHIVE_KEY_VAULT_NAME'])) {
    return $envValues['DEVICE_ARCHIVE_KEY_VAULT_NAME']
  }

  throw 'KeyVaultName was not provided and no azd environment value could be found. Run from the repo root or pass -KeyVaultName.'
}

function Get-KeyVaultAccessToken {
  $tokenOutput = @(az account get-access-token --resource https://vault.azure.net --query accessToken --output tsv --only-show-errors 2>$null)
  $nonEmptyLines = @($tokenOutput | Where-Object { -not [string]::IsNullOrWhiteSpace([string]$_) })
  if ($LASTEXITCODE -ne 0 -or $nonEmptyLines.Count -ne 1) {
    throw 'Azure CLI token acquisition failed.'
  }

  return ([string]$nonEmptyLines[0]).Trim()
}

function Assert-KeyVaultName {
  param(
    [Parameter(Mandatory = $true)]
    [string] $VaultName
  )

  if ($VaultName.Length -lt 3 -or $VaultName.Length -gt 24 -or
    $VaultName -notmatch '^[a-z][a-z0-9-]*[a-z0-9]$' -or $VaultName -match '--') {
    throw 'KeyVaultName must be a 3-24 character Azure Key Vault hostname label.'
  }
}

function Assert-SecretName {
  param(
    [Parameter(Mandatory = $true)]
    [string] $SecretName
  )

  if ($SecretName.Length -lt 1 -or $SecretName.Length -gt 127 -or $SecretName -notmatch '^[A-Za-z0-9-]+$') {
    throw 'The matched archive secret name is invalid.'
  }
}

function Invoke-KeyVaultJson {
  param(
    [Parameter(Mandatory = $true)]
    [string] $Method,
    [Parameter(Mandatory = $true)]
    [string] $Uri,
    [Parameter(Mandatory = $true)]
    [string] $VaultName
  )

  try {
    Assert-KeyVaultName -VaultName $VaultName
    $parsedUri = [System.Uri]::new($Uri)
    $expectedHost = "$VaultName.vault.azure.net"
    if ($parsedUri.Scheme -cne 'https' -or $parsedUri.Port -ne 443 -or $parsedUri.Host -ine $expectedHost -or
      -not [string]::IsNullOrWhiteSpace($parsedUri.UserInfo) -or
      -not [string]::IsNullOrWhiteSpace($parsedUri.Fragment) -or
      $parsedUri.AbsolutePath -notmatch '^/secrets(?:/[^/]+)?$' -or
      $parsedUri.Query -notmatch '(^|[?&])api-version=7\.4(&|$)') {
      throw 'Key Vault request URI is invalid.'
    }

    $headers = @{
      Authorization = "Bearer $(Get-KeyVaultAccessToken)"
      'Content-Type' = 'application/json'
    }

    Invoke-RestMethod -Method $Method -Uri $Uri -Headers $headers -ErrorAction Stop
  }
  catch {
    if ($_.Exception.Message -eq 'Azure CLI token acquisition failed.' -or
      $_.Exception.Message -eq 'Key Vault request URI is invalid.') {
      throw $_.Exception.Message
    }

    throw 'Key Vault request failed.'
  }
}

function Get-KeyVaultSecretMetadata {
  param(
    [Parameter(Mandatory = $true)]
    [string] $VaultName
  )

  Assert-KeyVaultName -VaultName $VaultName
  $items = @()
  $uri = "https://$VaultName.vault.azure.net/secrets?api-version=7.4"
  $visitedUris = @{}
  while (-not [string]::IsNullOrWhiteSpace($uri)) {
    if ($visitedUris.ContainsKey($uri)) {
      throw 'Key Vault metadata pagination repeated a continuation URI.'
    }
    $visitedUris[$uri] = $true

    $parsedUri = [System.Uri]::new($uri)
    if ($parsedUri.Scheme -cne 'https' -or $parsedUri.Port -ne 443 -or
      $parsedUri.Host -ine "$VaultName.vault.azure.net" -or
      -not [string]::IsNullOrWhiteSpace($parsedUri.UserInfo) -or
      -not [string]::IsNullOrWhiteSpace($parsedUri.Fragment) -or
      $parsedUri.AbsolutePath -cne '/secrets') {
      throw 'Key Vault metadata continuation URI is invalid.'
    }

    $response = Invoke-KeyVaultJson -Method 'GET' -Uri $uri -VaultName $VaultName
    $values = Get-OptionalPropertyValue -Object $response -Name 'value'
    if ($null -ne $values) {
      $items += @($values)
    }

    $uri = [string](Get-OptionalPropertyValue -Object $response -Name 'nextLink')
  }

  return $items
}

function Get-KeyVaultSecretValue {
  param(
    [Parameter(Mandatory = $true)]
    [string] $VaultName,
    [Parameter(Mandatory = $true)]
    [string] $SecretName
  )

  Assert-KeyVaultName -VaultName $VaultName
  Assert-SecretName -SecretName $SecretName
  return Invoke-KeyVaultJson -Method 'GET' -Uri "https://$VaultName.vault.azure.net/secrets/$SecretName?api-version=7.4" -VaultName $VaultName
}

function Get-OptionalPropertyValue {
  param(
    [object] $Object,
    [Parameter(Mandatory = $true)]
    [string] $Name
  )

  if ($null -eq $Object) {
    return $null
  }

  if ($Object -is [System.Collections.IDictionary]) {
    if (-not $Object.Contains($Name)) {
      return $null
    }

    return $Object[$Name]
  }

  $property = @($Object.PSObject.Properties | Where-Object { $_.Name -ceq $Name } | Select-Object -First 1)
  if ($property.Count -eq 0) {
    return $null
  }

  return $property[0].Value
}

function Get-SecretTags {
  param(
    [Parameter(Mandatory = $true)]
    [object] $Secret
  )

  $tags = Get-OptionalPropertyValue -Object $Secret -Name 'tags'
  if ($null -ne $tags) {
    return $tags
  }

  $attributes = Get-OptionalPropertyValue -Object $Secret -Name 'attributes'
  if ($null -ne $attributes) {
    return Get-OptionalPropertyValue -Object $attributes -Name 'tags'
  }

  return $null
}

function Test-Match {
  param(
    [Parameter(Mandatory = $true)]
    [object] $Secret,
    [AllowEmptyString()]
    [string] $Search,
    [AllowEmptyString()]
    [string] $DisplayName,
    [AllowEmptyString()]
    [string] $DeviceId,
    [AllowEmptyString()]
    [string] $EntraObjectId,
    [AllowEmptyString()]
    [string] $SerialNumber,
    [AllowEmptyString()]
    [string] $IntuneManagedDeviceId,
    [AllowEmptyString()]
    [string] $DefenderMachineId,
    [AllowEmptyString()]
    [string] $SecretName
  )

  $tags = Get-SecretTags -Secret $Secret
  $secretId = [string](Get-OptionalPropertyValue -Object $Secret -Name 'id')
  $secretLeaf = if ([string]::IsNullOrWhiteSpace($secretId)) { '' } else { $secretId.Split('/')[-1] }
  if (-not [string]::IsNullOrWhiteSpace($SecretName) -and $secretLeaf -ne $SecretName) {
    return $false
  }

  if (-not [string]::IsNullOrWhiteSpace($DisplayName) -and (($null -eq $tags) -or ((Get-OptionalPropertyValue -Object $tags -Name 'displayName') -ne $DisplayName))) {
    return $false
  }

  if (-not [string]::IsNullOrWhiteSpace($DeviceId) -and (($null -eq $tags) -or ((Get-OptionalPropertyValue -Object $tags -Name 'deviceId') -ne $DeviceId))) {
    return $false
  }

  if (-not [string]::IsNullOrWhiteSpace($EntraObjectId) -and (($null -eq $tags) -or ((Get-OptionalPropertyValue -Object $tags -Name 'entraObjectId') -ne $EntraObjectId))) {
    return $false
  }

  if (-not [string]::IsNullOrWhiteSpace($SerialNumber) -and (($null -eq $tags) -or ((Get-OptionalPropertyValue -Object $tags -Name 'serialNumber') -ne $SerialNumber))) {
    return $false
  }

  if (-not [string]::IsNullOrWhiteSpace($IntuneManagedDeviceId) -and (($null -eq $tags) -or ((Get-OptionalPropertyValue -Object $tags -Name 'intuneManagedDeviceId') -ne $IntuneManagedDeviceId))) {
    return $false
  }

  if (-not [string]::IsNullOrWhiteSpace($DefenderMachineId) -and (($null -eq $tags) -or ((Get-OptionalPropertyValue -Object $tags -Name 'defenderMachineId') -ne $DefenderMachineId))) {
    return $false
  }

  if ([string]::IsNullOrWhiteSpace($Search)) {
    return $true
  }

  $searchLower = $Search.ToLowerInvariant()
  $candidateValues = @($secretLeaf)
  if ($null -ne $tags) {
    $candidateValues += @(
      (Get-OptionalPropertyValue -Object $tags -Name 'displayName'),
      (Get-OptionalPropertyValue -Object $tags -Name 'deviceId'),
      (Get-OptionalPropertyValue -Object $tags -Name 'entraObjectId'),
      (Get-OptionalPropertyValue -Object $tags -Name 'serialNumber'),
      (Get-OptionalPropertyValue -Object $tags -Name 'intuneManagedDeviceId'),
      (Get-OptionalPropertyValue -Object $tags -Name 'defenderMachineId'),
      (Get-OptionalPropertyValue -Object $tags -Name 'cleanupRunId')
    )
  }

  $candidateValues = @($candidateValues | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

  foreach ($candidate in $candidateValues) {
    if ($candidate.ToLowerInvariant().Contains($searchLower)) {
      return $true
    }
  }

  return $false
}

function ConvertTo-Summary {
  param(
    [Parameter(Mandatory = $true)]
    [object] $SecretMetadata
  )

  $tags = Get-SecretTags -Secret $SecretMetadata
  $secretId = [string](Get-OptionalPropertyValue -Object $SecretMetadata -Name 'id')
  $secretName = if ([string]::IsNullOrWhiteSpace($secretId)) { $null } else { $secretId.Split('/')[-1] }
  $displayName = $null
  $deviceId = $null
  $entraObjectId = $null
  $serialNumber = $null
  $intuneManagedDeviceId = $null
  $defenderMachineId = $null
  $archivedAt = $null
  $cleanupRunId = $null
  $effectiveHeartbeatSource = $null
  $effectiveHeartbeatTimestamp = $null
  $lastSeenEntra = $null
  $lastSeenIntune = $null
  $lastSeenDefender = $null
  if ($null -ne $tags) {
    $displayName = Get-OptionalPropertyValue -Object $tags -Name 'displayName'
    $deviceId = Get-OptionalPropertyValue -Object $tags -Name 'deviceId'
    $entraObjectId = Get-OptionalPropertyValue -Object $tags -Name 'entraObjectId'
    $serialNumber = Get-OptionalPropertyValue -Object $tags -Name 'serialNumber'
    $intuneManagedDeviceId = Get-OptionalPropertyValue -Object $tags -Name 'intuneManagedDeviceId'
    $defenderMachineId = Get-OptionalPropertyValue -Object $tags -Name 'defenderMachineId'
    $archivedAt = Get-OptionalPropertyValue -Object $tags -Name 'archivedAt'
    $cleanupRunId = Get-OptionalPropertyValue -Object $tags -Name 'cleanupRunId'
    $effectiveHeartbeatSource = Get-OptionalPropertyValue -Object $tags -Name 'effectiveHeartbeatSource'
    $effectiveHeartbeatTimestamp = Get-OptionalPropertyValue -Object $tags -Name 'effectiveHeartbeatTimestamp'
    $lastSeenEntra = Get-OptionalPropertyValue -Object $tags -Name 'lastSeenEntra'
    $lastSeenIntune = Get-OptionalPropertyValue -Object $tags -Name 'lastSeenIntune'
    $lastSeenDefender = Get-OptionalPropertyValue -Object $tags -Name 'lastSeenDefender'
  }

  return [pscustomobject]@{
    SecretName = $secretName
    DisplayName = $displayName
    DeviceId = $deviceId
    EntraObjectId = $entraObjectId
    SerialNumber = $serialNumber
    IntuneManagedDeviceId = $intuneManagedDeviceId
    DefenderMachineId = $defenderMachineId
    ArchivedAt = $archivedAt
    CleanupRunId = $cleanupRunId
    EffectiveHeartbeatSource = $effectiveHeartbeatSource
    EffectiveHeartbeatTimestamp = $effectiveHeartbeatTimestamp
    LastSeenEntra = $lastSeenEntra
    LastSeenIntune = $lastSeenIntune
    LastSeenDefender = $lastSeenDefender
  }
}

function ConvertTo-ArchiveView {
  param(
    [Parameter(Mandatory = $true)]
    [string] $SecretName,
    [Parameter(Mandatory = $true)]
    [object] $ArchivePayload,
    [Parameter(Mandatory = $true)]
    [bool] $ShowRecoveryMaterial
  )

  $laps = Get-OptionalPropertyValue -Object $ArchivePayload -Name 'laps'
  $bitlocker = Get-OptionalPropertyValue -Object $ArchivePayload -Name 'bitlocker'
  $lapsCredentialCount = 0
  if ($null -ne $laps) {
    $credentials = Get-OptionalPropertyValue -Object $laps -Name 'credentials'
    if ($null -ne $credentials) {
      $lapsCredentialCount = @($credentials).Count
    }
  }
  $bitLockerKeyCount = 0
  if ($null -ne $bitlocker) {
    $bitLockerKeyCount = @($bitlocker).Count
  }

  $view = [ordered]@{
    secretName = $SecretName
    archivedAt = Get-OptionalPropertyValue -Object $ArchivePayload -Name 'archivedAt'
    cleanupContext = Get-OptionalPropertyValue -Object $ArchivePayload -Name 'cleanupContext'
    device = Get-OptionalPropertyValue -Object $ArchivePayload -Name 'device'
    heartbeats = Get-OptionalPropertyValue -Object $ArchivePayload -Name 'heartbeats'
    intune = Get-OptionalPropertyValue -Object $ArchivePayload -Name 'intune'
    defenderForEndpoint = Get-OptionalPropertyValue -Object $ArchivePayload -Name 'defenderForEndpoint'
    lapsCredentialCount = $lapsCredentialCount
    bitLockerKeyCount = $bitLockerKeyCount
  }

  if ($ShowRecoveryMaterial) {
    $view['laps'] = $laps
    $view['bitlocker'] = $bitlocker
  }

  return [pscustomobject] $view
}

function Invoke-ArchivedDeviceLookup {
  param(
    [string] $KeyVaultName = '',
    [string] $Search = '',
    [string] $DisplayName = '',
    [string] $DeviceId = '',
    [string] $EntraObjectId = '',
    [string] $SerialNumber = '',
    [string] $IntuneManagedDeviceId = '',
    [string] $DefenderMachineId = '',
    [string] $SecretName = '',
    [switch] $ShowRecoveryMaterial,
    [switch] $AsJson
  )

  Ensure-AzureCli
  if ([string]::IsNullOrWhiteSpace($KeyVaultName)) {
    $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
    $KeyVaultName = Get-DefaultKeyVaultName -RepositoryRoot $repoRoot
  }
  Assert-KeyVaultName -VaultName $KeyVaultName

  $allSecrets = @(Get-KeyVaultSecretMetadata -VaultName $KeyVaultName)
  $matches = @($allSecrets | Where-Object {
    Test-Match `
      -Secret $_ `
      -Search $Search `
      -DisplayName $DisplayName `
      -DeviceId $DeviceId `
      -EntraObjectId $EntraObjectId `
      -SerialNumber $SerialNumber `
      -IntuneManagedDeviceId $IntuneManagedDeviceId `
      -DefenderMachineId $DefenderMachineId `
      -SecretName $SecretName
  })

  if ($matches.Count -eq 0) {
    Write-Host "No archived device secrets matched the supplied search in vault '$KeyVaultName'."
    return
  }

  if (-not $ShowRecoveryMaterial) {
    $summaries = @($matches | ForEach-Object { ConvertTo-Summary -SecretMetadata $_ } | Sort-Object ArchivedAt -Descending)
    if ($AsJson) {
      $summaries | ConvertTo-Json -Depth 6
    }
    else {
      $summaries | Format-Table -AutoSize
    }

    if ($matches.Count -gt 1) {
      Write-Host 'Multiple matches were found. Narrow the search before requesting recovery material for a single record.'
    }
    else {
      Write-Host 'Metadata-only output shown. Re-run with -ShowRecoveryMaterial only for the intended single record.'
    }
    return
  }

  if ($matches.Count -gt 1) {
    throw 'Multiple archived device secrets matched the supplied search. Narrow the search before requesting recovery material.'
  }

  $matchedId = [string](Get-OptionalPropertyValue -Object $matches[0] -Name 'id')
  $secretPrefix = "https://$KeyVaultName.vault.azure.net/secrets/"
  $parsedMatchedId = $null
  try {
    $parsedMatchedId = [System.Uri]::new($matchedId)
  }
  catch {
    $parsedMatchedId = $null
  }

  if ($null -eq $parsedMatchedId -or $parsedMatchedId.Scheme -cne 'https' -or
    $parsedMatchedId.Host -ine "$KeyVaultName.vault.azure.net" -or
    -not [string]::IsNullOrWhiteSpace($parsedMatchedId.UserInfo) -or
    -not [string]::IsNullOrWhiteSpace($parsedMatchedId.Fragment) -or
    -not [string]::IsNullOrWhiteSpace($parsedMatchedId.Query) -or
    $parsedMatchedId.AbsolutePath -notmatch '^/secrets/[^/]+$' -or
    -not $matchedId.StartsWith($secretPrefix, [System.StringComparison]::OrdinalIgnoreCase)) {
    throw 'The matched archive record has an invalid secret identity.'
  }
  $secretName = $parsedMatchedId.AbsolutePath.Substring('/secrets/'.Length)
  Assert-SecretName -SecretName $secretName

  $secret = Get-KeyVaultSecretValue -VaultName $KeyVaultName -SecretName $secretName
  $secretValue = Get-OptionalPropertyValue -Object $secret -Name 'value'
  if ([string]::IsNullOrWhiteSpace([string]$secretValue)) {
    throw 'The archived secret has no payload value.'
  }

  try {
    $archivePayload = ([string]$secretValue) | ConvertFrom-Json -Depth 20 -ErrorAction Stop
  }
  catch {
    throw 'The archived secret payload could not be parsed.'
  }

  $view = ConvertTo-ArchiveView -SecretName $secretName -ArchivePayload $archivePayload -ShowRecoveryMaterial:$ShowRecoveryMaterial

  if ($AsJson) {
    $view | ConvertTo-Json -Depth 20
  }
  else {
    $view
  }
}

Invoke-ArchivedDeviceLookup `
  -KeyVaultName $KeyVaultName `
  -Search $Search `
  -DisplayName $DisplayName `
  -DeviceId $DeviceId `
  -EntraObjectId $EntraObjectId `
  -SerialNumber $SerialNumber `
  -IntuneManagedDeviceId $IntuneManagedDeviceId `
  -DefenderMachineId $DefenderMachineId `
  -SecretName $SecretName `
  -ShowRecoveryMaterial:$ShowRecoveryMaterial `
  -AsJson:$AsJson
