param(
  [string] $KeyVaultName = '',
  [string] $Search = '',
  [string] $DisplayName = '',
  [string] $DeviceId = '',
  [string] $EntraObjectId = '',
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
  az account get-access-token --resource https://vault.azure.net --query accessToken --output tsv --only-show-errors
}

function Invoke-KeyVaultJson {
  param(
    [Parameter(Mandatory = $true)]
    [string] $Method,
    [Parameter(Mandatory = $true)]
    [string] $Uri
  )

  $headers = @{
    Authorization = "Bearer $(Get-KeyVaultAccessToken)"
    'Content-Type' = 'application/json'
  }

  Invoke-RestMethod -Method $Method -Uri $Uri -Headers $headers -ErrorAction Stop
}

function Get-KeyVaultSecretMetadata {
  param(
    [Parameter(Mandatory = $true)]
    [string] $VaultName
  )

  $items = @()
  $uri = "https://$VaultName.vault.azure.net/secrets?api-version=7.4"
  while (-not [string]::IsNullOrWhiteSpace($uri)) {
    $response = Invoke-KeyVaultJson -Method 'GET' -Uri $uri
    if ($response.value) {
      $items += @($response.value)
    }

    $uri = $response.nextLink
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

  return Invoke-KeyVaultJson -Method 'GET' -Uri "https://$VaultName.vault.azure.net/secrets/$SecretName?api-version=7.4"
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
    [string] $SecretName
  )

  $tags = $null
  if ($Secret.attributes.PSObject.Properties.Name -contains 'tags') {
    $tags = $Secret.attributes.tags
  }
  if (-not [string]::IsNullOrWhiteSpace($SecretName) -and $Secret.id.Split('/')[-1] -ne $SecretName) {
    return $false
  }

  if (-not [string]::IsNullOrWhiteSpace($DisplayName) -and (($null -eq $tags) -or ($tags.displayName -ne $DisplayName))) {
    return $false
  }

  if (-not [string]::IsNullOrWhiteSpace($DeviceId) -and (($null -eq $tags) -or ($tags.deviceId -ne $DeviceId))) {
    return $false
  }

  if (-not [string]::IsNullOrWhiteSpace($EntraObjectId) -and (($null -eq $tags) -or ($tags.entraObjectId -ne $EntraObjectId))) {
    return $false
  }

  if ([string]::IsNullOrWhiteSpace($Search)) {
    return $true
  }

  $searchLower = $Search.ToLowerInvariant()
  $candidateValues = @($Secret.id.Split('/')[-1])
  if ($null -ne $tags) {
    $candidateValues += @($tags.displayName, $tags.deviceId, $tags.entraObjectId)
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

  $tags = $null
  if ($SecretMetadata.attributes.PSObject.Properties.Name -contains 'tags') {
    $tags = $SecretMetadata.attributes.tags
  }
  $displayName = $null
  $deviceId = $null
  $entraObjectId = $null
  $archivedAt = $null
  if ($null -ne $tags) {
    $displayName = $tags.displayName
    $deviceId = $tags.deviceId
    $entraObjectId = $tags.entraObjectId
    $archivedAt = $tags.archivedAt
  }

  return [pscustomobject]@{
    SecretName = $SecretMetadata.id.Split('/')[-1]
    DisplayName = $displayName
    DeviceId = $deviceId
    EntraObjectId = $entraObjectId
    ArchivedAt = $archivedAt
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

  $lapsCredentialCount = 0
  if ($null -ne $ArchivePayload.laps) {
    $lapsCredentialCount = @($ArchivePayload.laps.credentials).Count
  }
  $bitLockerKeyCount = @($ArchivePayload.bitlocker).Count

  $view = [ordered]@{
    secretName = $SecretName
    archivedAt = $ArchivePayload.archivedAt
    device = $ArchivePayload.device
    heartbeats = $ArchivePayload.heartbeats
    intune = $ArchivePayload.intune
    defenderForEndpoint = $ArchivePayload.defenderForEndpoint
    lapsCredentialCount = $lapsCredentialCount
    bitLockerKeyCount = $bitLockerKeyCount
  }

  if ($ShowRecoveryMaterial) {
    $view['laps'] = $ArchivePayload.laps
    $view['bitlocker'] = $ArchivePayload.bitlocker
  }

  return [pscustomobject] $view
}

Ensure-AzureCli
$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
if ([string]::IsNullOrWhiteSpace($KeyVaultName)) {
  $KeyVaultName = Get-DefaultKeyVaultName -RepositoryRoot $repoRoot
}

$allSecrets = @(Get-KeyVaultSecretMetadata -VaultName $KeyVaultName)
$matches = @($allSecrets | Where-Object {
  Test-Match `
    -Secret $_ `
    -Search $Search `
    -DisplayName $DisplayName `
    -DeviceId $DeviceId `
    -EntraObjectId $EntraObjectId `
    -SecretName $SecretName
})

if ($matches.Count -eq 0) {
  Write-Host "No archived device secrets matched the supplied search in vault '$KeyVaultName'."
  exit 0
}

if (($matches.Count -gt 1) -and (-not $ShowRecoveryMaterial)) {
  $summaries = @($matches | ForEach-Object { ConvertTo-Summary -SecretMetadata $_ } | Sort-Object ArchivedAt -Descending)
  if ($AsJson) {
    $summaries | ConvertTo-Json -Depth 6
  }
  else {
    $summaries | Format-Table -AutoSize
  }

  Write-Host "Multiple matches were found. Re-run with -SecretName, -EntraObjectId, -DeviceId, or -ShowRecoveryMaterial for a single record."
  exit 0
}

if ($matches.Count -gt 1) {
  throw "Multiple archived device secrets matched the supplied search. Narrow the search before requesting recovery material."
}

$secretName = $matches[0].id.Split('/')[-1]
$secret = Get-KeyVaultSecretValue -VaultName $KeyVaultName -SecretName $secretName
$archivePayload = $secret.value | ConvertFrom-Json -Depth 20
$view = ConvertTo-ArchiveView -SecretName $secretName -ArchivePayload $archivePayload -ShowRecoveryMaterial:$ShowRecoveryMaterial

if ($AsJson) {
  $view | ConvertTo-Json -Depth 20
}
else {
  $view
}
