param(
  [string] $KeyVaultName = '',
  [string] $Search = '',
  [string] $DisplayName = '',
  [string] $DeviceId = '',
  [string] $EntraObjectId = '',
  [string] $SerialNumber = '',
  [string] $IntuneManagedDeviceId = '',
  [string] $DefenderMachineId = '',
  [string] $PrimaryUserId = '',
  [string] $PrimaryUserPrincipalName = '',
  [string] $ArchiveVersion = '',
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
      $parsedUri.AbsolutePath -notmatch '^/secrets(?:/[A-Za-z0-9-]+(?:/[a-fA-F0-9]{32})?)?$' -or
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
  $VaultName = $VaultName.ToLowerInvariant()
  $items = @()
  $uri = "https://$VaultName.vault.azure.net/secrets?api-version=7.4"
  $visitedUris = @{}
  $pageCount = 0
  while (-not [string]::IsNullOrWhiteSpace($uri)) {
    if ($pageCount -ge 20) { throw 'Key Vault metadata pagination exceeded its page limit.' }
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
    $pageCount++
    $values = Get-OptionalPropertyValue -Object $response -Name 'value'
    if ($null -ne $values) {
      $items += @($values)
      if ($items.Count -gt 5000) { throw 'Key Vault metadata listing exceeded its item limit.' }
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
    [string] $SecretName,
    [AllowEmptyString()]
    [string] $Version = '',
    [AllowEmptyString()]
    [string] $ExpectedContentType = ''
  )

  Assert-KeyVaultName -VaultName $VaultName
  Assert-SecretName -SecretName $SecretName
  $VaultName = $VaultName.ToLowerInvariant()
  if (-not [string]::IsNullOrWhiteSpace($Version) -and $Version -notmatch '^[a-fA-F0-9]{32}$') {
    throw 'The archive secret version is invalid.'
  }
  $versionPath = if ([string]::IsNullOrWhiteSpace($Version)) { '' } else { "/$($Version.ToLowerInvariant())" }
  $response = Invoke-KeyVaultJson -Method 'GET' -Uri "https://$VaultName.vault.azure.net/secrets/${SecretName}${versionPath}?api-version=7.4" -VaultName $VaultName
  return Assert-KeyVaultSecretResponse -Response $response -VaultName $VaultName -SecretName $SecretName -Version $Version -ExpectedContentType $ExpectedContentType
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

function Assert-KeyVaultSecretResponse {
  param(
    [Parameter(Mandatory = $true)][object]$Response,
    [Parameter(Mandatory = $true)][string]$VaultName,
    [Parameter(Mandatory = $true)][string]$SecretName,
    [AllowEmptyString()][string]$Version = '',
    [AllowEmptyString()][string]$ExpectedContentType = ''
  )

  Assert-KeyVaultName -VaultName $VaultName
  Assert-SecretName -SecretName $SecretName
  $VaultName = $VaultName.ToLowerInvariant()
  $id = [string](Get-OptionalPropertyValue -Object $Response -Name 'id')
  $parsed = $null
  try { $parsed = [Uri]::new($id) } catch { $parsed = $null }
  if ($null -eq $parsed -or $parsed.Scheme -cne 'https' -or $parsed.Port -ne 443 -or
      $parsed.Host -ine "$VaultName.vault.azure.net" -or -not [string]::IsNullOrWhiteSpace($parsed.UserInfo) -or
      -not [string]::IsNullOrWhiteSpace($parsed.Query) -or -not [string]::IsNullOrWhiteSpace($parsed.Fragment) -or
      $parsed.AbsolutePath -notmatch '^/secrets/([A-Za-z0-9-]+)/([a-fA-F0-9]{32})$' -or $Matches[1] -cne $SecretName) {
    throw 'Key Vault secret response identity is invalid.'
  }
  $returnedVersion = $Matches[2].ToLowerInvariant()
  if (-not [string]::IsNullOrWhiteSpace($Version) -and $returnedVersion -cne $Version.ToLowerInvariant()) {
    throw 'Key Vault secret response identity is invalid.'
  }
  if (-not [string]::IsNullOrWhiteSpace($ExpectedContentType) -and
      [string](Get-OptionalPropertyValue -Object $Response -Name 'contentType') -cne $ExpectedContentType) {
    throw 'Key Vault secret response content type is invalid.'
  }
  return $Response
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

function Get-ArchiveIndexName {
  param([Parameter(Mandatory = $true)][string] $ArchiveSecretId)
  $bytes = [Text.Encoding]::UTF8.GetBytes($ArchiveSecretId)
  $sha = [Security.Cryptography.SHA256]::Create()
  try { $hash = ([BitConverter]::ToString($sha.ComputeHash($bytes))).Replace('-', '').ToLowerInvariant() }
  finally { $sha.Dispose() }
  return "device-archive-index-$hash"
}

function Get-SecretNameFromMetadata {
  param([Parameter(Mandatory = $true)][object]$Secret, [Parameter(Mandatory = $true)][string]$VaultName)
  Assert-KeyVaultName -VaultName $VaultName
  $VaultName = $VaultName.ToLowerInvariant()
  $id = [string](Get-OptionalPropertyValue -Object $Secret -Name 'id')
  $parsed = $null
  try { $parsed = [Uri]::new($id) } catch { return $null }
  if ($parsed.Scheme -cne 'https' -or $parsed.Port -ne 443 -or $parsed.Host -ine "$VaultName.vault.azure.net" -or
      -not [string]::IsNullOrWhiteSpace($parsed.UserInfo) -or -not [string]::IsNullOrWhiteSpace($parsed.Query) -or
      -not [string]::IsNullOrWhiteSpace($parsed.Fragment) -or $parsed.AbsolutePath -notmatch '^/secrets/([A-Za-z0-9-]+)$') {
    return $null
  }
  return $Matches[1]
}

function Test-IsReservedIndexMetadata {
  param([Parameter(Mandatory = $true)][object]$Secret)
  $id = [string](Get-OptionalPropertyValue -Object $Secret -Name 'id')
  return $id -match '^https://[^/?#]+/secrets/device-archive-index-'
}

function Get-ValidatedIndexTagSummary {
  param(
    [Parameter(Mandatory = $true)][object]$SecretMetadata,
    [Parameter(Mandatory = $true)][string]$VaultName
  )
  $VaultName = $VaultName.ToLowerInvariant()
  $indexName = Get-SecretNameFromMetadata -Secret $SecretMetadata -VaultName $VaultName
  if ([string]::IsNullOrWhiteSpace($indexName) -or $indexName -notmatch '^device-archive-index-[a-f0-9]{64}$') { return $null }
  try { $metadataUri = [Uri]::new([string](Get-OptionalPropertyValue -Object $SecretMetadata -Name 'id')) } catch { return $null }
  if ($metadataUri.Host -ine "$VaultName.vault.azure.net") { return $null }
  $contentType = [string](Get-OptionalPropertyValue -Object $SecretMetadata -Name 'contentType')
  if ($contentType -cne 'application/vnd.azd-device-cleanup.archive-index+json;v=1') { return $null }
  $tags = Get-SecretTags -Secret $SecretMetadata
  if ($null -eq $tags -or
      (Get-OptionalPropertyValue -Object $tags -Name 'kind') -cne 'device-archive-index' -or
      (Get-OptionalPropertyValue -Object $tags -Name 'schemaVersion') -cne '1.0' -or
      $null -ne (Get-OptionalPropertyValue -Object $tags -Name 'primaryUserPrincipalName')) { return $null }

  $archiveName = [string](Get-OptionalPropertyValue -Object $tags -Name 'archiveSecretName')
  $version = [string](Get-OptionalPropertyValue -Object $tags -Name 'archiveSecretVersion')
  $hash = [string](Get-OptionalPropertyValue -Object $tags -Name 'archiveIdHash')
  if ($archiveName.Length -lt 1 -or $archiveName.Length -gt 127 -or $archiveName -notmatch '^[A-Za-z0-9-]+$' -or
      $version -notmatch '^[a-f0-9]{32}$' -or $hash -notmatch '^[a-f0-9]{64}$') { return $null }
  $archiveId = "https://$VaultName.vault.azure.net/secrets/$archiveName/$version"
  $expectedIndexName = Get-ArchiveIndexName -ArchiveSecretId $archiveId
  if ($indexName -cne $expectedIndexName -or $hash -cne $indexName.Substring('device-archive-index-'.Length)) { return $null }

  $state = [string](Get-OptionalPropertyValue -Object $tags -Name 'primaryUserState')
  if ($state -notin @('Disabled','MappingMissing','MappingAmbiguous','None','Single','Multiple','Unavailable','Overflow','Conflict')) { return $null }
  $primaryId = Get-OptionalPropertyValue -Object $tags -Name 'primaryUserId'
  if ($state -eq 'Single') {
    if ([string]::IsNullOrWhiteSpace([string]$primaryId) -or ([string]$primaryId).Length -gt 128 -or
        [string]$primaryId -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') { return $null }
  }
  elseif ($null -ne $primaryId) { return $null }

  $bounds = @{
    displayName=256; deviceId=128; entraObjectId=128; serialNumber=256; intuneManagedDeviceId=128
    defenderMachineId=128; archivedAt=64; cleanupRunId=128; primaryUserId=128
  }
  foreach ($name in $bounds.Keys) {
    $value = Get-OptionalPropertyValue -Object $tags -Name $name
    if ($null -ne $value -and ($value -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$value) -or ([string]$value).Length -gt $bounds[$name])) { return $null }
  }
  if ([string]::IsNullOrWhiteSpace([string](Get-OptionalPropertyValue -Object $tags -Name 'entraObjectId')) -or
      [string]::IsNullOrWhiteSpace([string](Get-OptionalPropertyValue -Object $tags -Name 'archivedAt')) -or
      [string]::IsNullOrWhiteSpace([string](Get-OptionalPropertyValue -Object $tags -Name 'cleanupRunId'))) { return $null }
  $entraId = [string](Get-OptionalPropertyValue -Object $tags -Name 'entraObjectId')
  $deviceId = Get-OptionalPropertyValue -Object $tags -Name 'deviceId'
  $intuneId = Get-OptionalPropertyValue -Object $tags -Name 'intuneManagedDeviceId'
  $defenderId = Get-OptionalPropertyValue -Object $tags -Name 'defenderMachineId'
  if ($entraId -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' -or
      ($null -ne $deviceId -and [string]$deviceId -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') -or
      ($null -ne $intuneId -and [string]$intuneId -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') -or
      ($null -ne $defenderId -and [string]$defenderId -notmatch '^[0-9a-f]{40}$')) { return $null }

  return [pscustomobject]@{
    RecordType='IndexedExactVersion'; SecretName=$archiveName; ArchiveVersion=$version; IndexSecretName=$indexName
    DisplayName=Get-OptionalPropertyValue -Object $tags -Name 'displayName'
    DeviceId=Get-OptionalPropertyValue -Object $tags -Name 'deviceId'
    EntraObjectId=Get-OptionalPropertyValue -Object $tags -Name 'entraObjectId'
    SerialNumber=Get-OptionalPropertyValue -Object $tags -Name 'serialNumber'
    IntuneManagedDeviceId=Get-OptionalPropertyValue -Object $tags -Name 'intuneManagedDeviceId'
    DefenderMachineId=Get-OptionalPropertyValue -Object $tags -Name 'defenderMachineId'
    ArchivedAt=Get-OptionalPropertyValue -Object $tags -Name 'archivedAt'
    CleanupRunId=Get-OptionalPropertyValue -Object $tags -Name 'cleanupRunId'
    PrimaryUserState=$state; PrimaryUserId=$primaryId; PrimaryUserPrincipalName=$null
    IndexMetadata=$SecretMetadata
  }
}

function ConvertFrom-ValidatedArchiveIndex {
  param(
    [Parameter(Mandatory = $true)][object]$SecretResponse,
    [Parameter(Mandatory = $true)][object]$TagSummary,
    [Parameter(Mandatory = $true)][string]$VaultName
  )
  $VaultName = $VaultName.ToLowerInvariant()
  $SecretResponse = Assert-KeyVaultSecretResponse -Response $SecretResponse -VaultName $VaultName -SecretName $TagSummary.IndexSecretName -ExpectedContentType 'application/vnd.azd-device-cleanup.archive-index+json;v=1'
  $raw = [string](Get-OptionalPropertyValue -Object $SecretResponse -Name 'value')
  if ([string]::IsNullOrWhiteSpace($raw) -or [Text.Encoding]::UTF8.GetByteCount($raw) -gt 8192) { throw 'The archive metadata index is invalid.' }
  $required = @('schemaVersion','kind','archiveSecretName','archiveSecretVersion','archiveSecretId','entraObjectId','deviceId','displayName','serialNumber','intuneManagedDeviceId','defenderMachineId','archivedAt','cleanupRunId','primaryUserState','primaryUserId','primaryUserPrincipalName')
  $document = $null
  try {
    $options = [System.Text.Json.JsonDocumentOptions]::new()
    $options.MaxDepth = 5
    $document = [System.Text.Json.JsonDocument]::Parse($raw, $options)
    if ($document.RootElement.ValueKind -ne [System.Text.Json.JsonValueKind]::Object) { throw 'invalid root' }
    $properties = @($document.RootElement.EnumerateObject())
    $names = @($properties | ForEach-Object Name)
    if ($names.Count -ne $required.Count -or @($required | Where-Object { $names -cnotcontains $_ }).Count -ne 0) { throw 'invalid properties' }
    $parsed = [ordered]@{}
    foreach ($property in $properties) {
      if ($property.Value.ValueKind -eq [System.Text.Json.JsonValueKind]::Null) { $parsed[$property.Name] = $null }
      elseif ($property.Value.ValueKind -eq [System.Text.Json.JsonValueKind]::String) { $parsed[$property.Name] = $property.Value.GetString() }
      else { throw 'invalid value type' }
    }
    $value = [pscustomobject]$parsed
  }
  catch { throw 'The archive metadata index is invalid.' }
  finally { if ($null -ne $document) { $document.Dispose() } }
  if ($value.schemaVersion -cne '1.0' -or $value.kind -cne 'device-archive-index') { throw 'The archive metadata index is invalid.' }
  $bounds = @{
    archiveSecretName=127; archiveSecretVersion=32; archiveSecretId=512; entraObjectId=128; deviceId=128; displayName=256
    serialNumber=256; intuneManagedDeviceId=128; defenderMachineId=128; archivedAt=64; cleanupRunId=128
    primaryUserState=32; primaryUserId=128; primaryUserPrincipalName=320
  }
  foreach ($name in $bounds.Keys) {
    $item = $value.$name
    if ($null -ne $item -and ($item -isnot [string] -or [string]::IsNullOrWhiteSpace([string]$item) -or ([string]$item).Length -gt $bounds[$name])) { throw 'The archive metadata index is invalid.' }
  }
  foreach ($name in @('archiveSecretName','archiveSecretVersion','archiveSecretId','entraObjectId','archivedAt','cleanupRunId','primaryUserState')) {
    if ($null -eq $value.$name) { throw 'The archive metadata index is invalid.' }
  }
  if ($value.entraObjectId -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$' -or
      ($null -ne $value.deviceId -and $value.deviceId -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') -or
      ($null -ne $value.intuneManagedDeviceId -and $value.intuneManagedDeviceId -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') -or
      ($null -ne $value.defenderMachineId -and $value.defenderMachineId -notmatch '^[0-9a-f]{40}$')) { throw 'The archive metadata index is invalid.' }
  $expectedId = "https://$VaultName.vault.azure.net/secrets/$($TagSummary.SecretName)/$($TagSummary.ArchiveVersion)"
  if ($value.archiveSecretName -cne $TagSummary.SecretName -or $value.archiveSecretVersion -cne $TagSummary.ArchiveVersion -or
      $value.archiveSecretId -cne $expectedId -or (Get-ArchiveIndexName -ArchiveSecretId $expectedId) -cne $TagSummary.IndexSecretName) { throw 'The archive metadata index is invalid.' }
  foreach ($pair in @{ entraObjectId='EntraObjectId'; deviceId='DeviceId'; displayName='DisplayName'; serialNumber='SerialNumber'; intuneManagedDeviceId='IntuneManagedDeviceId'; defenderMachineId='DefenderMachineId'; archivedAt='ArchivedAt'; cleanupRunId='CleanupRunId'; primaryUserState='PrimaryUserState'; primaryUserId='PrimaryUserId' }.GetEnumerator()) {
    if ($value.($pair.Key) -cne $TagSummary.($pair.Value)) { throw 'The archive metadata index is invalid.' }
  }
  if ($value.primaryUserState -eq 'Single') {
    if ($null -eq $value.primaryUserId -or $value.primaryUserId -notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$') { throw 'The archive metadata index is invalid.' }
    if ($null -ne $value.primaryUserPrincipalName -and $value.primaryUserPrincipalName -notmatch '^[^\s@]+@[^\s@]+$') { throw 'The archive metadata index is invalid.' }
  }
  elseif ($null -ne $value.primaryUserId -or $null -ne $value.primaryUserPrincipalName) { throw 'The archive metadata index is invalid.' }
  return $value
}

function Test-SummaryMatch {
  param(
    [Parameter(Mandatory = $true)][object]$Summary,
    [string]$Search='', [string]$DisplayName='', [string]$DeviceId='', [string]$EntraObjectId='',
    [string]$SerialNumber='', [string]$IntuneManagedDeviceId='', [string]$DefenderMachineId='',
    [string]$PrimaryUserId='', [string]$PrimaryUserPrincipalName='', [string]$ArchiveVersion='', [string]$SecretName=''
  )
  foreach ($pair in @(
      @('DisplayName',$DisplayName), @('DeviceId',$DeviceId), @('EntraObjectId',$EntraObjectId), @('SerialNumber',$SerialNumber),
      @('IntuneManagedDeviceId',$IntuneManagedDeviceId), @('DefenderMachineId',$DefenderMachineId), @('PrimaryUserId',$PrimaryUserId),
      @('PrimaryUserPrincipalName',$PrimaryUserPrincipalName), @('ArchiveVersion',$ArchiveVersion), @('SecretName',$SecretName)
    )) {
    if (-not [string]::IsNullOrWhiteSpace([string]$pair[1]) -and $Summary.($pair[0]) -ne $pair[1]) { return $false }
  }
  if ([string]::IsNullOrWhiteSpace($Search)) { return $true }
  $needle = $Search.ToLowerInvariant()
  foreach ($candidate in @($Summary.SecretName,$Summary.DisplayName,$Summary.DeviceId,$Summary.EntraObjectId,$Summary.SerialNumber,$Summary.IntuneManagedDeviceId,$Summary.DefenderMachineId,$Summary.CleanupRunId)) {
    if (-not [string]::IsNullOrWhiteSpace([string]$candidate) -and ([string]$candidate).ToLowerInvariant().Contains($needle)) { return $true }
  }
  return $false
}

function ConvertTo-Summary {
  param(
    [Parameter(Mandatory = $true)]
    [object] $SecretMetadata,
    [Parameter(Mandatory = $true)]
    [string] $VaultName
  )

  $tags = Get-SecretTags -Secret $SecretMetadata
  $secretName = Get-SecretNameFromMetadata -Secret $SecretMetadata -VaultName $VaultName
  if ([string]::IsNullOrWhiteSpace($secretName)) { return $null }
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
    $legacyBounds = [ordered]@{
      displayName=256; deviceId=128; entraObjectId=128; serialNumber=256; intuneManagedDeviceId=128; defenderMachineId=128
      archivedAt=64; cleanupRunId=128; effectiveHeartbeatSource=64; effectiveHeartbeatTimestamp=64
      lastSeenEntra=64; lastSeenIntune=64; lastSeenDefender=64
    }
    $validated = @{}
    foreach ($name in $legacyBounds.Keys) {
      $candidate = Get-OptionalPropertyValue -Object $tags -Name $name
      if ($null -ne $candidate -and ($candidate -isnot [string] -or [string]::IsNullOrWhiteSpace($candidate) -or $candidate.Length -gt $legacyBounds[$name])) { return $null }
      $validated[$name] = $candidate
    }
    $displayName = $validated.displayName
    $deviceId = $validated.deviceId
    $entraObjectId = $validated.entraObjectId
    $serialNumber = $validated.serialNumber
    $intuneManagedDeviceId = $validated.intuneManagedDeviceId
    $defenderMachineId = $validated.defenderMachineId
    $archivedAt = $validated.archivedAt
    $cleanupRunId = $validated.cleanupRunId
    $effectiveHeartbeatSource = $validated.effectiveHeartbeatSource
    $effectiveHeartbeatTimestamp = $validated.effectiveHeartbeatTimestamp
    $lastSeenEntra = $validated.lastSeenEntra
    $lastSeenIntune = $validated.lastSeenIntune
    $lastSeenDefender = $validated.lastSeenDefender
  }

  return [pscustomobject]@{
    RecordType = 'LegacyLatestAlias'
    SecretName = $secretName
    ArchiveVersion = $null
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
    PrimaryUserState = $null
    PrimaryUserId = $null
    PrimaryUserPrincipalName = $null
    IndexSecretName = $null
    IndexMetadata = $null
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
    [string] $PrimaryUserId = '',
    [string] $PrimaryUserPrincipalName = '',
    [string] $ArchiveVersion = '',
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
  $KeyVaultName = $KeyVaultName.Trim().ToLowerInvariant()

  if (-not [string]::IsNullOrWhiteSpace($ArchiveVersion) -and $ArchiveVersion -notmatch '^[a-fA-F0-9]{32}$') {
    throw 'ArchiveVersion must be a 32-character hexadecimal Key Vault version.'
  }
  $allSecrets = @(Get-KeyVaultSecretMetadata -VaultName $KeyVaultName)
  $reserved = @($allSecrets | Where-Object { Test-IsReservedIndexMetadata -Secret $_ })
  if ($reserved.Count -gt 1000) { throw 'Archive metadata index listing exceeded its item limit.' }
  $summaries = @()
  foreach ($metadata in $allSecrets) {
    if (Test-IsReservedIndexMetadata -Secret $metadata) { continue }
    $legacySummary = ConvertTo-Summary -SecretMetadata $metadata -VaultName $KeyVaultName
    if ($null -ne $legacySummary) { $summaries += $legacySummary }
  }
  foreach ($metadata in $reserved) {
    $summary = Get-ValidatedIndexTagSummary -SecretMetadata $metadata -VaultName $KeyVaultName
    if ($null -ne $summary) { $summaries += $summary }
  }

  if (-not [string]::IsNullOrWhiteSpace($PrimaryUserPrincipalName)) {
    foreach ($summary in @($summaries | Where-Object RecordType -eq 'IndexedExactVersion')) {
      $indexSecret = Get-KeyVaultSecretValue -VaultName $KeyVaultName -SecretName $summary.IndexSecretName -ExpectedContentType 'application/vnd.azd-device-cleanup.archive-index+json;v=1'
      $indexValue = ConvertFrom-ValidatedArchiveIndex -SecretResponse $indexSecret -TagSummary $summary -VaultName $KeyVaultName
      $summary.PrimaryUserPrincipalName = $indexValue.primaryUserPrincipalName
    }
  }

  $matches = @($summaries | Where-Object {
      Test-SummaryMatch -Summary $_ -Search $Search -DisplayName $DisplayName -DeviceId $DeviceId -EntraObjectId $EntraObjectId `
        -SerialNumber $SerialNumber -IntuneManagedDeviceId $IntuneManagedDeviceId -DefenderMachineId $DefenderMachineId `
        -PrimaryUserId $PrimaryUserId -PrimaryUserPrincipalName $PrimaryUserPrincipalName -ArchiveVersion $ArchiveVersion -SecretName $SecretName
    })

  if ($matches.Count -eq 0) {
    Write-Host "No archived device secrets matched the supplied search in vault '$KeyVaultName'."
    return
  }

  if (-not $ShowRecoveryMaterial) {
    $outputSummaries = @($matches | Sort-Object ArchivedAt -Descending | Select-Object RecordType,SecretName,ArchiveVersion,DisplayName,DeviceId,EntraObjectId,SerialNumber,IntuneManagedDeviceId,DefenderMachineId,ArchivedAt,CleanupRunId,PrimaryUserState,PrimaryUserId,PrimaryUserPrincipalName)
    if ($AsJson) {
      $outputSummaries | ConvertTo-Json -Depth 6
    }
    else {
      $outputSummaries | Format-Table -AutoSize
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

  $selected = $matches[0]
  $secretName = [string]$selected.SecretName
  if ([string]::IsNullOrWhiteSpace($secretName)) { throw 'The matched archive record has an invalid secret identity.' }
  Assert-SecretName -SecretName $secretName
  $selectedVersion = ''
  if ($selected.RecordType -eq 'IndexedExactVersion') {
    $indexSecret = Get-KeyVaultSecretValue -VaultName $KeyVaultName -SecretName $selected.IndexSecretName -ExpectedContentType 'application/vnd.azd-device-cleanup.archive-index+json;v=1'
    $indexValue = ConvertFrom-ValidatedArchiveIndex -SecretResponse $indexSecret -TagSummary $selected -VaultName $KeyVaultName
    $selectedVersion = [string]$indexValue.archiveSecretVersion
  }
  $secret = Get-KeyVaultSecretValue -VaultName $KeyVaultName -SecretName $secretName -Version $selectedVersion -ExpectedContentType 'application/json'
  $secret = Assert-KeyVaultSecretResponse -Response $secret -VaultName $KeyVaultName -SecretName $secretName -Version $selectedVersion -ExpectedContentType 'application/json'
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
  -PrimaryUserId $PrimaryUserId `
  -PrimaryUserPrincipalName $PrimaryUserPrincipalName `
  -ArchiveVersion $ArchiveVersion `
  -SecretName $SecretName `
  -ShowRecoveryMaterial:$ShowRecoveryMaterial `
  -AsJson:$AsJson
