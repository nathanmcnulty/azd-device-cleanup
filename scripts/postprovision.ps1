$ErrorActionPreference = 'Stop'

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

function Get-RequiredEnvironmentValue {
  param(
    [Parameter(Mandatory = $true)]
    [string] $Name
  )

  $value = [Environment]::GetEnvironmentVariable($Name)
  if ([string]::IsNullOrWhiteSpace($value) -and $null -eq $script:AzdEnvironmentValues) {
    $script:AzdEnvironmentValues = Get-AzdEnvironmentValues -RepositoryRoot (Resolve-Path (Join-Path $PSScriptRoot '..'))
  }

  if ([string]::IsNullOrWhiteSpace($value) -and $null -ne $script:AzdEnvironmentValues -and $script:AzdEnvironmentValues.ContainsKey($Name)) {
    $value = $script:AzdEnvironmentValues[$Name]
  }

  if ([string]::IsNullOrWhiteSpace($value)) {
    throw "Required environment value '$Name' is missing. Make sure azd provision completed successfully."
  }

  return $value
}

function Get-OptionalEnvironmentValue {
  param(
    [Parameter(Mandatory = $true)]
    [string] $Name,
    [string] $Default = ''
  )

  $value = [Environment]::GetEnvironmentVariable($Name)
  if ($null -eq $value -and $null -eq $script:AzdEnvironmentValues) {
    $script:AzdEnvironmentValues = Get-AzdEnvironmentValues -RepositoryRoot (Resolve-Path (Join-Path $PSScriptRoot '..'))
  }

  if ($null -eq $value -and $null -ne $script:AzdEnvironmentValues -and $script:AzdEnvironmentValues.ContainsKey($Name)) {
    $value = $script:AzdEnvironmentValues[$Name]
  }

  if ($null -eq $value) {
    return $Default
  }

  return $value
}

function ConvertTo-BooleanValue {
  param(
    [Parameter(Mandatory = $true)]
    [AllowEmptyString()]
    [string] $Value,
    [Parameter(Mandatory = $true)]
    [string] $Name
  )

  switch ($Value.Trim().ToLowerInvariant()) {
    '1' { return $true }
    '0' { return $false }
    'true' { return $true }
    'false' { return $false }
    'yes' { return $true }
    'no' { return $false }
    default { throw "Environment value '$Name' must be a boolean. Current value: '$Value'." }
  }
}

function Ensure-AzureCli {
  if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw 'Azure CLI is required for postprovision steps.'
  }
}

function Ensure-AzAutomationModule {
  if (-not (Get-Module -ListAvailable -Name Az.Automation)) {
    Install-Module Az.Automation -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
  }

  Import-Module Az.Automation -ErrorAction Stop
}

function Ensure-AutomationExtension {
  az extension add --name automation --upgrade --only-show-errors | Out-Null
}

function Get-RunbookContentPath {
  $repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
  $path = Join-Path $repoRoot 'runbooks/DeviceCleanup.ps1'

  if (-not (Test-Path -LiteralPath $path)) {
    throw "Runbook content file was not found at '$path'."
  }

  return (Resolve-Path $path).Path
}

function Get-GraphAccessToken {
  az account get-access-token --resource-type ms-graph --query accessToken --output tsv --only-show-errors
}

function Invoke-GraphJson {
  param(
    [Parameter(Mandatory = $true)]
    [string] $Method,
    [Parameter(Mandatory = $true)]
    [string] $Url,
    [object] $Body
  )

  $headers = @{
    Authorization = "Bearer $(Get-GraphAccessToken)"
    'Content-Type' = 'application/json'
  }

  $request = @{
    Method = $Method
    Uri = $Url
    Headers = $headers
    ErrorAction = 'Stop'
  }

  if ($PSBoundParameters.ContainsKey('Body')) {
    $request.Body = $Body | ConvertTo-Json -Depth 10 -Compress
  }

  Invoke-RestMethod @request
}

function Get-ArmAccessToken {
  az account get-access-token --resource https://management.azure.com/ --query accessToken --output tsv --only-show-errors
}

function Get-LogicAppCallbackUrl {
  param(
    [Parameter(Mandatory = $true)]
    [string] $SubscriptionId,
    [Parameter(Mandatory = $true)]
    [string] $ResourceGroupName,
    [Parameter(Mandatory = $true)]
    [string] $WorkflowName
  )

  $url = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Logic/workflows/$WorkflowName/triggers/manual/listCallbackUrl?api-version=2019-05-01"
  $response = az rest --method post --url $url --output json --only-show-errors | ConvertFrom-Json
  if ($null -eq $response -or [string]::IsNullOrWhiteSpace($response.value)) {
    throw "Unable to resolve the callback URL for Logic App workflow '$WorkflowName'."
  }

  return $response.value
}

function Get-DefaultDynamicGroupName {
  param(
    [Parameter(Mandatory = $true)]
    [string] $EnvironmentName,
    [Parameter(Mandatory = $true)]
    [string] $SourceLabel
  )

  return "$EnvironmentName - $SourceLabel stale devices"
}

function Get-DefaultExclusionGroupName {
  param(
    [Parameter(Mandatory = $true)]
    [string] $EnvironmentName
  )

  return "$EnvironmentName - Device cleanup exclusions"
}

function Get-DefaultDynamicGroupRule {
  param(
    [Parameter(Mandatory = $true)]
    [int] $AttributeNumber,
    [Parameter(Mandatory = $true)]
    [string] $SourceLabel
  )

  if ($AttributeNumber -le 0) {
    throw "A positive extensionAttribute slot is required to derive the default $SourceLabel dynamic group rule."
  }

  return "device.extensionAttribute$AttributeNumber -startsWith `"Stale|`""
}

function Get-GroupMailNickname {
  param(
    [Parameter(Mandatory = $true)]
    [string] $DisplayName
  )

  $nickname = $DisplayName.ToLowerInvariant() -replace '[^a-z0-9]', '-'
  $nickname = $nickname -replace '-{2,}', '-'
  $nickname = $nickname.Trim('-')
  if ([string]::IsNullOrWhiteSpace($nickname)) {
    $nickname = 'device-cleanup-group'
  }

  if ($nickname.Length -gt 64) {
    $nickname = $nickname.Substring(0, 64).Trim('-')
  }

  if ([string]::IsNullOrWhiteSpace($nickname)) {
    return 'device-cleanup-group'
  }

  return $nickname
}

function Get-ExistingGroupByDisplayName {
  param(
    [Parameter(Mandatory = $true)]
    [string] $DisplayName
  )

  $escapedDisplayName = $DisplayName.Replace("'", "''")
  $filter = [Uri]::EscapeDataString("displayName eq '$escapedDisplayName'")
  $response = Invoke-GraphJson `
    -Method 'GET' `
    -Url "https://graph.microsoft.com/v1.0/groups?`$filter=$filter&`$select=id,displayName,description,membershipRule,membershipRuleProcessingState,groupTypes,mailEnabled,mailNickname,securityEnabled"

  return @($response.value | Where-Object { $_.displayName -eq $DisplayName })
}

function Get-GroupById {
  param(
    [Parameter(Mandatory = $true)]
    [string] $GroupId
  )

  return Invoke-GraphJson `
    -Method 'GET' `
    -Url "https://graph.microsoft.com/v1.0/groups/$GroupId?`$select=id,displayName,description,membershipRule,membershipRuleProcessingState,groupTypes,mailEnabled,mailNickname,securityEnabled"
}

function Ensure-AssignedSecurityGroup {
  param(
    [Parameter(Mandatory = $true)]
    [string] $DisplayName,
    [Parameter(Mandatory = $true)]
    [string] $Description
  )

  $existingGroups = @(Get-ExistingGroupByDisplayName -DisplayName $DisplayName)
  if ($existingGroups.Count -gt 1) {
    throw "Found multiple Microsoft Entra groups named '$DisplayName'. Resolve the duplicate groups before continuing."
  }

  $mailNickname = Get-GroupMailNickname -DisplayName $DisplayName
  if ($existingGroups.Count -eq 0) {
    $createdGroup = Invoke-GraphJson `
      -Method 'POST' `
      -Url 'https://graph.microsoft.com/v1.0/groups' `
      -Body @{
        displayName = $DisplayName
        description = $Description
        mailEnabled = $false
        mailNickname = $mailNickname
        securityEnabled = $true
      }

    Write-Host "Created exclusion security group '$DisplayName'."
    return $createdGroup
  }

  $group = $existingGroups[0]
  if (-not $group.securityEnabled -or $group.mailEnabled) {
    throw "The existing group '$DisplayName' is not a security-only Microsoft Entra group."
  }

  if (@($group.groupTypes) -contains 'DynamicMembership') {
    throw "The existing group '$DisplayName' uses dynamic membership. Use an assigned security group for cleanup exclusions."
  }

  if ($group.description -ne $Description) {
    Invoke-GraphJson `
      -Method 'PATCH' `
      -Url "https://graph.microsoft.com/v1.0/groups/$($group.id)" `
      -Body @{
        description = $Description
      } | Out-Null

    $group = Get-GroupById -GroupId $group.id
    Write-Host "Updated exclusion security group '$DisplayName'."
  }
  else {
    Write-Host "Exclusion security group '$DisplayName' is already up to date."
  }

  return $group
}

function Resolve-ExclusionGroup {
  param(
    [Parameter(Mandatory = $true)]
    [string] $EnvironmentName,
    [AllowEmptyString()]
    [string] $ConfiguredGroupId,
    [AllowEmptyString()]
    [string] $ConfiguredGroupName
  )

  if (-not [string]::IsNullOrWhiteSpace($ConfiguredGroupId)) {
    $group = Get-GroupById -GroupId $ConfiguredGroupId
    if (-not $group.securityEnabled -or $group.mailEnabled) {
      throw "The configured exclusion group '$ConfiguredGroupId' is not a security-only Microsoft Entra group."
    }

    if (@($group.groupTypes) -contains 'DynamicMembership') {
      throw "The configured exclusion group '$ConfiguredGroupId' uses dynamic membership. Use an assigned security group for cleanup exclusions."
    }

    return $group
  }

  $resolvedGroupName = $ConfiguredGroupName
  if ([string]::IsNullOrWhiteSpace($resolvedGroupName)) {
    $resolvedGroupName = Get-DefaultExclusionGroupName -EnvironmentName $EnvironmentName
  }

  return Ensure-AssignedSecurityGroup `
    -DisplayName $resolvedGroupName `
    -Description "Managed by azd-device-cleanup environment '$EnvironmentName'. Add device objects that should be excluded from disable and delete actions."
}

function Ensure-DynamicDeviceGroup {
  param(
    [Parameter(Mandatory = $true)]
    [string] $DisplayName,
    [Parameter(Mandatory = $true)]
    [string] $MembershipRule,
    [Parameter(Mandatory = $true)]
    [string] $Description
  )

  $existingGroups = @(Get-ExistingGroupByDisplayName -DisplayName $DisplayName)
  if ($existingGroups.Count -gt 1) {
    throw "Found multiple Microsoft Entra groups named '$DisplayName'. Resolve the duplicate groups before continuing."
  }

  $mailNickname = Get-GroupMailNickname -DisplayName $DisplayName
  if ($existingGroups.Count -eq 0) {
    Invoke-GraphJson `
      -Method 'POST' `
      -Url 'https://graph.microsoft.com/v1.0/groups' `
      -Body @{
        displayName = $DisplayName
        description = $Description
        groupTypes = @('DynamicMembership')
        membershipRule = $MembershipRule
        membershipRuleProcessingState = 'On'
        mailEnabled = $false
        mailNickname = $mailNickname
        securityEnabled = $true
      } | Out-Null

    Write-Host "Created dynamic device group '$DisplayName'."
    return
  }

  $group = $existingGroups[0]
  if (-not $group.securityEnabled -or $group.mailEnabled) {
    throw "The existing group '$DisplayName' is not a security-only Microsoft Entra group."
  }

  if (@($group.groupTypes) -notcontains 'DynamicMembership') {
    throw "The existing group '$DisplayName' is not configured for dynamic membership."
  }

  $patch = @{}
  if ($group.description -ne $Description) {
    $patch.description = $Description
  }

  if ($group.membershipRule -ne $MembershipRule) {
    $patch.membershipRule = $MembershipRule
  }

  if ($group.membershipRuleProcessingState -ne 'On') {
    $patch.membershipRuleProcessingState = 'On'
  }

  if ($patch.Count -eq 0) {
    Write-Host "Dynamic device group '$DisplayName' is already up to date."
    return
  }

  Invoke-GraphJson `
    -Method 'PATCH' `
    -Url "https://graph.microsoft.com/v1.0/groups/$($group.id)" `
    -Body $patch | Out-Null

  Write-Host "Updated dynamic device group '$DisplayName'."
}

function Connect-AzPowerShellFromCli {
  param(
    [Parameter(Mandatory = $true)]
    [string] $SubscriptionId,
    [Parameter(Mandatory = $true)]
    [string] $TenantId
  )

  Disable-AzContextAutosave -Scope Process | Out-Null
  Connect-AzAccount `
    -AccessToken (Get-ArmAccessToken) `
    -AccountId 'AzureCliToken' `
    -Subscription $SubscriptionId `
    -Tenant $TenantId `
    -SkipValidation `
    -Force | Out-Null
}

function Ensure-DeleteLock {
  param(
    [Parameter(Mandatory = $true)]
    [string] $SubscriptionId,
    [Parameter(Mandatory = $true)]
    [string] $ResourceGroupName
  )

  $headers = @{
    Authorization = "Bearer $(Get-ArmAccessToken)"
    'Content-Type' = 'application/json'
  }

  $body = @{
    properties = @{
      level = 'CanNotDelete'
      notes = 'Protects device cleanup resources from accidental deletion. Remove this lock before running azd down.'
    }
  } | ConvertTo-Json -Depth 10 -Compress

  Invoke-RestMethod `
    -Method 'PUT' `
    -Uri "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Authorization/locks/resource-group-delete-lock?api-version=2020-05-01" `
    -Headers $headers `
    -Body $body `
    -ErrorAction Stop | Out-Null
}

function Get-RenderedRunbookPath {
  param(
    [Parameter(Mandatory = $true)]
    [string] $RunbookTemplatePath,
    [Parameter(Mandatory = $true)]
    [hashtable] $Replacements
  )

  $content = Get-Content -LiteralPath $RunbookTemplatePath -Raw
  foreach ($key in $Replacements.Keys) {
    $content = $content.Replace($key, $Replacements[$key])
  }

  $tempFile = New-TemporaryFile
  $renderedPath = [System.IO.Path]::ChangeExtension($tempFile.FullName, '.ps1')
  Move-Item -LiteralPath $tempFile.FullName -Destination $renderedPath -Force
  Set-Content -LiteralPath $renderedPath -Value $content -Encoding utf8
  return $renderedPath
}

function Wait-ForServicePrincipal {
  param(
    [Parameter(Mandatory = $true)]
    [string] $PrincipalId
  )

  for ($attempt = 1; $attempt -le 12; $attempt++) {
    $principal = az ad sp show --id $PrincipalId --only-show-errors 2>$null
    if ($LASTEXITCODE -eq 0 -and $principal) {
      return
    }

    if ($attempt -eq 12) {
      throw "Managed identity service principal $PrincipalId was not available in Microsoft Entra after waiting."
    }

    Start-Sleep -Seconds 10
  }
}

$graphAppId = '00000003-0000-0000-c000-000000000000'
$defenderAppId = 'fc780465-2017-40d4-a0c5-307022471b92'
$principalId = Get-RequiredEnvironmentValue -Name 'AUTOMATION_ACCOUNT_PRINCIPAL_ID'

function Get-ServicePrincipalInfo {
  param(
    [Parameter(Mandatory = $true)]
    [string] $AppId
  )

  $servicePrincipal = az ad sp show --id $AppId --query '{id:id,appId:appId,displayName:displayName,appRoles:appRoles}' --output json --only-show-errors | ConvertFrom-Json
  if ($null -eq $servicePrincipal) {
    throw "Could not resolve service principal for appId '$AppId'."
  }

  return $servicePrincipal
}

function Ensure-AppRoleAssignments {
  param(
    [Parameter(Mandatory = $true)]
    [string] $PrincipalId,
    [Parameter(Mandatory = $true)]
    [object] $ResourceServicePrincipal,
    [Parameter(Mandatory = $true)]
    [string[]] $PermissionNames,
    [Parameter(Mandatory = $true)]
    [System.Collections.ArrayList] $ExistingAssignments
  )

  foreach ($permissionName in $PermissionNames) {
    $appRole = $ResourceServicePrincipal.appRoles | Where-Object {
      $_.value -eq $permissionName -and $_.allowedMemberTypes -contains 'Application'
    } | Select-Object -First 1

    if (-not $appRole) {
      throw "Could not resolve app role '$permissionName' on resource '$($ResourceServicePrincipal.displayName)'."
    }

    $alreadyAssigned = $ExistingAssignments | Where-Object {
      $_.resourceId -eq $ResourceServicePrincipal.id -and $_.appRoleId -eq $appRole.id
    } | Select-Object -First 1

    if ($alreadyAssigned) {
      Write-Host "App role already assigned: $($ResourceServicePrincipal.displayName) / $permissionName"
      continue
    }

    $body = @{
      principalId = $PrincipalId
      resourceId  = $ResourceServicePrincipal.id
      appRoleId   = $appRole.id
    }

    Invoke-GraphJson `
      -Method 'POST' `
      -Url "https://graph.microsoft.com/v1.0/servicePrincipals/$PrincipalId/appRoleAssignments" `
      -Body $body | Out-Null

    [void] $ExistingAssignments.Add([pscustomobject]@{
        resourceId = $ResourceServicePrincipal.id
        appRoleId = $appRole.id
      })

    Write-Host "Assigned app role: $($ResourceServicePrincipal.displayName) / $permissionName"
  }
}

function Remove-AppRoleAssignments {
  param(
    [Parameter(Mandatory = $true)]
    [string] $PrincipalId,
    [Parameter(Mandatory = $true)]
    [object] $ResourceServicePrincipal,
    [Parameter(Mandatory = $true)]
    [string[]] $PermissionNames,
    [Parameter(Mandatory = $true)]
    [System.Collections.ArrayList] $ExistingAssignments
  )

  foreach ($permissionName in $PermissionNames) {
    $appRole = $ResourceServicePrincipal.appRoles | Where-Object {
      $_.value -eq $permissionName -and $_.allowedMemberTypes -contains 'Application'
    } | Select-Object -First 1

    if (-not $appRole) {
      continue
    }

    $matchingAssignments = @($ExistingAssignments | Where-Object {
        $_.resourceId -eq $ResourceServicePrincipal.id -and $_.appRoleId -eq $appRole.id
      })

    foreach ($assignment in $matchingAssignments) {
      Invoke-GraphJson `
        -Method 'DELETE' `
        -Url "https://graph.microsoft.com/v1.0/servicePrincipals/$PrincipalId/appRoleAssignments/$($assignment.id)" | Out-Null
      Write-Host "Removed app role: $($ResourceServicePrincipal.displayName) / $permissionName"
    }
  }
}

Ensure-AzureCli
Ensure-AutomationExtension
Ensure-AzAutomationModule
Wait-ForServicePrincipal -PrincipalId $principalId

$graphSp = Get-ServicePrincipalInfo -AppId $graphAppId
$defenderSp = Get-ServicePrincipalInfo -AppId $defenderAppId
$existingAssignments = [System.Collections.ArrayList]::new()
foreach ($assignment in @((Invoke-GraphJson -Method 'GET' -Url "https://graph.microsoft.com/v1.0/servicePrincipals/$principalId/appRoleAssignments").value)) {
  [void] $existingAssignments.Add($assignment)
}

$defenderCheckInAttributeNumber = [int](Get-RequiredEnvironmentValue -Name 'DEFENDER_CHECKIN_ATTRIBUTE_NUMBER')
$defenderApiEnabled = $defenderCheckInAttributeNumber -gt 0
$advancedHuntingEnabled = ConvertTo-BooleanValue -Name 'ADVANCED_HUNTING_ENABLED' -Value (Get-RequiredEnvironmentValue -Name 'ADVANCED_HUNTING_ENABLED')
$graphPermissionNames = @(
  'Device.Read.All',
  'Device.ReadWrite.All',
  'Group.Read.All',
  'GroupMember.Read.All',
  'DeviceLocalCredential.Read.All',
  'BitlockerKey.Read.All',
  'DeviceManagementManagedDevices.Read.All'
)
if ($advancedHuntingEnabled) {
  $graphPermissionNames += 'ThreatHunting.Read.All'
}

Ensure-AppRoleAssignments -PrincipalId $principalId -ResourceServicePrincipal $graphSp -PermissionNames $graphPermissionNames -ExistingAssignments $existingAssignments

if (-not $advancedHuntingEnabled) {
  Remove-AppRoleAssignments -PrincipalId $principalId -ResourceServicePrincipal $graphSp -PermissionNames @(
    'ThreatHunting.Read.All'
  ) -ExistingAssignments $existingAssignments
}

if ($defenderApiEnabled) {
  Ensure-AppRoleAssignments -PrincipalId $principalId -ResourceServicePrincipal $defenderSp -PermissionNames @(
    'Machine.Read.All'
  ) -ExistingAssignments $existingAssignments
}
else {
  Remove-AppRoleAssignments -PrincipalId $principalId -ResourceServicePrincipal $defenderSp -PermissionNames @(
    'Machine.Read.All'
  ) -ExistingAssignments $existingAssignments
}

$subscriptionId = Get-RequiredEnvironmentValue -Name 'AZURE_SUBSCRIPTION_ID'
$tenantId = Get-RequiredEnvironmentValue -Name 'AZURE_TENANT_ID'
$null = az account set --subscription $subscriptionId --only-show-errors
$environmentName = Get-RequiredEnvironmentValue -Name 'AZURE_ENV_NAME'
$resourceGroupName = Get-RequiredEnvironmentValue -Name 'AZURE_RESOURCE_GROUP'
$automationAccountName = Get-RequiredEnvironmentValue -Name 'AUTOMATION_ACCOUNT_NAME'
$runbookName = Get-RequiredEnvironmentValue -Name 'AUTOMATION_RUNBOOK_NAME'
$scheduleName = Get-RequiredEnvironmentValue -Name 'AUTOMATION_SCHEDULE_NAME'
$keyVaultName = Get-RequiredEnvironmentValue -Name 'DEVICE_ARCHIVE_KEY_VAULT_NAME'
$secretNamePrefix = Get-RequiredEnvironmentValue -Name 'DEVICE_SECRET_PREFIX'
$deviceDisableAfterDays = Get-RequiredEnvironmentValue -Name 'DEVICE_DISABLE_AFTER_DAYS'
$deviceDeleteAfterDays = Get-RequiredEnvironmentValue -Name 'DEVICE_DELETE_AFTER_DAYS'
$deviceMaxDeleteCount = Get-RequiredEnvironmentValue -Name 'DEVICE_MAX_DELETE_COUNT'
$deviceDisableEnabled = Get-RequiredEnvironmentValue -Name 'DEVICE_DISABLE_ENABLED'
$deviceDeleteEnabled = Get-RequiredEnvironmentValue -Name 'DEVICE_DELETE_ENABLED'
$exclusionDeviceGroupName = Get-OptionalEnvironmentValue -Name 'EXCLUSION_DEVICE_GROUP_NAME'
$exclusionDeviceGroupObjectId = Get-OptionalEnvironmentValue -Name 'EXCLUSION_DEVICE_GROUP_OBJECT_ID'
$intuneCheckInAttributeNumber = Get-RequiredEnvironmentValue -Name 'INTUNE_CHECKIN_ATTRIBUTE_NUMBER'
$defenderCheckInAttributeNumber = Get-RequiredEnvironmentValue -Name 'DEFENDER_CHECKIN_ATTRIBUTE_NUMBER'
$intuneDynamicGroupEnabled = Get-RequiredEnvironmentValue -Name 'INTUNE_DYNAMIC_GROUP_ENABLED'
$intuneDynamicGroupName = Get-OptionalEnvironmentValue -Name 'INTUNE_DYNAMIC_GROUP_NAME'
$intuneDynamicGroupRule = Get-OptionalEnvironmentValue -Name 'INTUNE_DYNAMIC_GROUP_RULE'
$defenderDynamicGroupEnabled = Get-RequiredEnvironmentValue -Name 'DEFENDER_DYNAMIC_GROUP_ENABLED'
$defenderDynamicGroupName = Get-OptionalEnvironmentValue -Name 'DEFENDER_DYNAMIC_GROUP_NAME'
$defenderDynamicGroupRule = Get-OptionalEnvironmentValue -Name 'DEFENDER_DYNAMIC_GROUP_RULE'
$advancedHuntingLookbackDays = Get-RequiredEnvironmentValue -Name 'ADVANCED_HUNTING_LOOKBACK_DAYS'
$logicAppNotificationsEnabled = Get-RequiredEnvironmentValue -Name 'LOGIC_APP_NOTIFICATIONS_ENABLED'
$logicAppNotificationWorkflowName = Get-OptionalEnvironmentValue -Name 'LOGIC_APP_NOTIFICATION_WORKFLOW_NAME'
$logicAppNotifyOnSuccess = Get-RequiredEnvironmentValue -Name 'LOGIC_APP_NOTIFY_ON_SUCCESS'
$logicAppNotifyOnFailure = Get-RequiredEnvironmentValue -Name 'LOGIC_APP_NOTIFY_ON_FAILURE'
$logicAppNotifyOnNoAction = Get-RequiredEnvironmentValue -Name 'LOGIC_APP_NOTIFY_ON_NO_ACTION'
$enableDeleteLock = Get-RequiredEnvironmentValue -Name 'ENABLE_DELETE_LOCK'
$logicAppNotificationCallbackUrl = ''
$deleteLockIsEnabled = ConvertTo-BooleanValue -Name 'ENABLE_DELETE_LOCK' -Value $enableDeleteLock
$logicAppNotificationsAreEnabled = ConvertTo-BooleanValue -Name 'LOGIC_APP_NOTIFICATIONS_ENABLED' -Value $logicAppNotificationsEnabled
if ($logicAppNotificationsAreEnabled) {
  if ([string]::IsNullOrWhiteSpace($logicAppNotificationWorkflowName)) {
    throw "Logic App notifications are enabled, but LOGIC_APP_NOTIFICATION_WORKFLOW_NAME is empty."
  }

  $logicAppNotificationCallbackUrl = Get-LogicAppCallbackUrl `
    -SubscriptionId $subscriptionId `
    -ResourceGroupName $resourceGroupName `
    -WorkflowName $logicAppNotificationWorkflowName
}

$resolvedExclusionGroup = Resolve-ExclusionGroup `
  -EnvironmentName $environmentName `
  -ConfiguredGroupId $exclusionDeviceGroupObjectId `
  -ConfiguredGroupName $exclusionDeviceGroupName
$resolvedExclusionGroupId = $resolvedExclusionGroup.id
$resolvedExclusionGroupName = $resolvedExclusionGroup.displayName
$runbookTemplatePath = Get-RunbookContentPath
$renderedRunbookPath = Get-RenderedRunbookPath -RunbookTemplatePath $runbookTemplatePath -Replacements @{
  '__DEVICE_ARCHIVE_KEY_VAULT_NAME__' = $keyVaultName
  '__DEVICE_SECRET_PREFIX__' = $secretNamePrefix
  '__DEVICE_DISABLE_AFTER_DAYS__' = $deviceDisableAfterDays
  '__DEVICE_DELETE_AFTER_DAYS__' = $deviceDeleteAfterDays
  '__DEVICE_MAX_DELETE_COUNT__' = $deviceMaxDeleteCount
  '__DEVICE_DISABLE_ENABLED__' = $deviceDisableEnabled
  '__DEVICE_DELETE_ENABLED__' = $deviceDeleteEnabled
  '__EXCLUSION_DEVICE_GROUP_ID__' = $resolvedExclusionGroupId
  '__INTUNE_CHECKIN_ATTRIBUTE_NUMBER__' = $intuneCheckInAttributeNumber
  '__DEFENDER_CHECKIN_ATTRIBUTE_NUMBER__' = $defenderCheckInAttributeNumber
  '__ADVANCED_HUNTING_ENABLED__' = $advancedHuntingEnabled
  '__ADVANCED_HUNTING_LOOKBACK_DAYS__' = $advancedHuntingLookbackDays
  '__LOGIC_APP_NOTIFICATIONS_ENABLED__' = $logicAppNotificationsEnabled
  '__LOGIC_APP_NOTIFICATION_CALLBACK_URL__' = $logicAppNotificationCallbackUrl
  '__LOGIC_APP_NOTIFY_ON_SUCCESS__' = $logicAppNotifyOnSuccess
  '__LOGIC_APP_NOTIFY_ON_FAILURE__' = $logicAppNotifyOnFailure
  '__LOGIC_APP_NOTIFY_ON_NO_ACTION__' = $logicAppNotifyOnNoAction
  '__AZURE_ENV_NAME__' = $environmentName
  '__AZURE_SUBSCRIPTION_ID__' = $subscriptionId
  '__AZURE_RESOURCE_GROUP__' = $resourceGroupName
  '__AUTOMATION_ACCOUNT_NAME__' = $automationAccountName
  '__AUTOMATION_RUNBOOK_NAME__' = $runbookName
}

try {
  Connect-AzPowerShellFromCli -SubscriptionId $subscriptionId -TenantId $tenantId

  az automation runbook replace-content `
    --automation-account-name $automationAccountName `
    --resource-group $resourceGroupName `
    --subscription $subscriptionId `
    --name $runbookName `
    --content "@$renderedRunbookPath" `
    --only-show-errors | Out-Null

  az automation runbook publish `
    --automation-account-name $automationAccountName `
    --resource-group $resourceGroupName `
    --subscription $subscriptionId `
    --name $runbookName `
    --only-show-errors | Out-Null

  $existingScheduledRunbook = Get-AzAutomationScheduledRunbook `
    -ResourceGroupName $resourceGroupName `
    -AutomationAccountName $automationAccountName `
    -RunbookName $runbookName `
    -ScheduleName $scheduleName `
    -ErrorAction SilentlyContinue

  if ($null -eq $existingScheduledRunbook) {
    Register-AzAutomationScheduledRunbook `
      -ResourceGroupName $resourceGroupName `
      -AutomationAccountName $automationAccountName `
      -RunbookName $runbookName `
      -ScheduleName $scheduleName `
      -Parameters @{
        keyvaultName = $keyVaultName
        SecretNamePrefix = $secretNamePrefix
        DisableAfterDays = $deviceDisableAfterDays
        DeleteAfterDays = $deviceDeleteAfterDays
        MaxDeleteCount = $deviceMaxDeleteCount
        DisableEnabled = $deviceDisableEnabled
        DeleteEnabled = $deviceDeleteEnabled
        IntuneCheckInAttributeNumber = $intuneCheckInAttributeNumber
        DefenderCheckInAttributeNumber = $defenderCheckInAttributeNumber
        AdvancedHuntingEnabled = $advancedHuntingEnabled
        AdvancedHuntingLookbackDays = $advancedHuntingLookbackDays
      } | Out-Null
  }

  if (ConvertTo-BooleanValue -Name 'INTUNE_DYNAMIC_GROUP_ENABLED' -Value $intuneDynamicGroupEnabled) {
    $resolvedIntuneGroupName = $intuneDynamicGroupName
    if ([string]::IsNullOrWhiteSpace($resolvedIntuneGroupName)) {
      $resolvedIntuneGroupName = Get-DefaultDynamicGroupName -EnvironmentName $environmentName -SourceLabel 'Intune'
    }

    $resolvedIntuneGroupRule = $intuneDynamicGroupRule
    if ([string]::IsNullOrWhiteSpace($resolvedIntuneGroupRule)) {
      $resolvedIntuneGroupRule = Get-DefaultDynamicGroupRule -AttributeNumber ([int] $intuneCheckInAttributeNumber) -SourceLabel 'Intune'
    }

    Ensure-DynamicDeviceGroup `
      -DisplayName $resolvedIntuneGroupName `
      -MembershipRule $resolvedIntuneGroupRule `
      -Description "Managed by azd-device-cleanup environment '$environmentName'. Default purpose: devices whose Intune-derived extension attribute is stale. Membership rule: $resolvedIntuneGroupRule"
  }

  if (ConvertTo-BooleanValue -Name 'DEFENDER_DYNAMIC_GROUP_ENABLED' -Value $defenderDynamicGroupEnabled) {
    $resolvedDefenderGroupName = $defenderDynamicGroupName
    if ([string]::IsNullOrWhiteSpace($resolvedDefenderGroupName)) {
      $resolvedDefenderGroupName = Get-DefaultDynamicGroupName -EnvironmentName $environmentName -SourceLabel 'Defender'
    }

    $resolvedDefenderGroupRule = $defenderDynamicGroupRule
    if ([string]::IsNullOrWhiteSpace($resolvedDefenderGroupRule)) {
      $resolvedDefenderGroupRule = Get-DefaultDynamicGroupRule -AttributeNumber ([int] $defenderCheckInAttributeNumber) -SourceLabel 'Defender'
    }

    Ensure-DynamicDeviceGroup `
      -DisplayName $resolvedDefenderGroupName `
      -MembershipRule $resolvedDefenderGroupRule `
      -Description "Managed by azd-device-cleanup environment '$environmentName'. Default purpose: devices whose Defender-derived extension attribute is stale. Membership rule: $resolvedDefenderGroupRule"
  }

  if ($deleteLockIsEnabled) {
    Ensure-DeleteLock -SubscriptionId $subscriptionId -ResourceGroupName $resourceGroupName
  }
}
finally {
  Remove-Item -LiteralPath $renderedRunbookPath -ErrorAction SilentlyContinue
}

Write-Host "Runbook '$runbookName' published and linked to schedule '$scheduleName'. ExclusionGroup='$resolvedExclusionGroupName' ($resolvedExclusionGroupId)."
