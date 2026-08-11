param(
  [switch] $SkipAutomationJob,
  [int] $AutomationJobTimeoutMinutes = 15
)

$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Ensure-AzureCli {
  if (-not (Get-Command az -ErrorAction SilentlyContinue)) {
    throw 'Azure CLI is required to run preflight validation.'
  }
}

function Ensure-AzAutomationModule {
  if (-not (Get-Module -ListAvailable -Name Az.Automation)) {
    Install-Module Az.Automation -Scope CurrentUser -Force -AllowClobber -ErrorAction Stop
  }

  Import-Module Az.Automation -ErrorAction Stop
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

function Get-RequiredEnvironmentValue {
  param(
    [Parameter(Mandatory = $true)]
    [hashtable] $EnvironmentValues,
    [Parameter(Mandatory = $true)]
    [string] $Name
  )

  if (-not $EnvironmentValues.ContainsKey($Name) -or [string]::IsNullOrWhiteSpace($EnvironmentValues[$Name])) {
    throw "Required environment value '$Name' is missing. Run azd provision first."
  }

  return $EnvironmentValues[$Name]
}

function Get-OptionalEnvironmentValue {
  param(
    [Parameter(Mandatory = $true)]
    [hashtable] $EnvironmentValues,
    [Parameter(Mandatory = $true)]
    [string] $Name,
    [string] $Default = ''
  )

  if (-not $EnvironmentValues.ContainsKey($Name)) {
    return $Default
  }

  return $EnvironmentValues[$Name]
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

function Get-DefaultExclusionGroupName {
  param(
    [Parameter(Mandatory = $true)]
    [string] $EnvironmentName
  )

  return "$EnvironmentName - Device cleanup exclusions"
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

function Connect-AzPowerShellFromCli {
  param(
    [Parameter(Mandatory = $true)]
    [string] $SubscriptionId,
    [Parameter(Mandatory = $true)]
    [string] $TenantId
  )

  Disable-AzContextAutosave -Scope Process | Out-Null
  $armToken = az account get-access-token --resource https://management.azure.com/ --query accessToken --output tsv --only-show-errors
  Connect-AzAccount `
    -AccessToken $armToken `
    -AccountId 'AzureCliToken' `
    -Subscription $SubscriptionId `
    -Tenant $TenantId `
    -SkipValidation `
    -Force | Out-Null
}

function Get-ServicePrincipalInfo {
  param(
    [Parameter(Mandatory = $true)]
    [string] $AppId
  )

  $servicePrincipal = az ad sp show --id $AppId --query '{id:id,displayName:displayName,appRoles:appRoles}' --output json --only-show-errors | ConvertFrom-Json
  if ($null -eq $servicePrincipal) {
    throw "Could not resolve service principal for appId '$AppId'."
  }

  return $servicePrincipal
}

function Assert-AppRoleAssignments {
  param(
    [Parameter(Mandatory = $true)]
    [string] $PrincipalId,
    [Parameter(Mandatory = $true)]
    [object] $ResourceServicePrincipal,
    [Parameter(Mandatory = $true)]
    [string[]] $RequiredRoles
  )

  $assignments = @((Invoke-GraphJson -Method 'GET' -Url "https://graph.microsoft.com/v1.0/servicePrincipals/$PrincipalId/appRoleAssignments?`$select=resourceId,appRoleId").value)
  $missingRoles = @()
  foreach ($roleName in $RequiredRoles) {
    $appRole = $ResourceServicePrincipal.appRoles | Where-Object {
      $_.value -eq $roleName -and $_.allowedMemberTypes -contains 'Application'
    } | Select-Object -First 1

    if (-not $appRole) {
      throw "Could not resolve required app role '$roleName' on resource '$($ResourceServicePrincipal.displayName)'."
    }

    $match = $assignments | Where-Object {
      $_.resourceId -eq $ResourceServicePrincipal.id -and $_.appRoleId -eq $appRole.id
    } | Select-Object -First 1

    if (-not $match) {
      $missingRoles += $roleName
    }
  }

  if ($missingRoles.Count -gt 0) {
    throw "Managed identity is missing required app roles on '$($ResourceServicePrincipal.displayName)': $($missingRoles -join ', ')"
  }
}

function Get-GroupById {
  param(
    [Parameter(Mandatory = $true)]
    [string] $GroupId
  )

  Invoke-GraphJson -Method 'GET' -Url "https://graph.microsoft.com/v1.0/groups/$GroupId?`$select=id,displayName,description,membershipRule,membershipRuleProcessingState,groupTypes,mailEnabled,securityEnabled"
}

function Get-GroupByDisplayName {
  param(
    [Parameter(Mandatory = $true)]
    [string] $DisplayName
  )

  $escapedDisplayName = $DisplayName.Replace("'", "''")
  $filter = [Uri]::EscapeDataString("displayName eq '$escapedDisplayName'")
  $response = Invoke-GraphJson -Method 'GET' -Url "https://graph.microsoft.com/v1.0/groups?`$filter=$filter&`$select=id,displayName,description,membershipRule,membershipRuleProcessingState,groupTypes,mailEnabled,securityEnabled"
  return @($response.value | Where-Object { $_.displayName -eq $DisplayName })
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
    return Get-GroupById -GroupId $ConfiguredGroupId
  }

  $resolvedName = $ConfiguredGroupName
  if ([string]::IsNullOrWhiteSpace($resolvedName)) {
    $resolvedName = Get-DefaultExclusionGroupName -EnvironmentName $EnvironmentName
  }

  $groups = @(Get-GroupByDisplayName -DisplayName $resolvedName)
  if ($groups.Count -ne 1) {
    throw "Expected exactly one exclusion group named '$resolvedName', found $($groups.Count)."
  }

  return $groups[0]
}

function Resolve-DynamicGroup {
  param(
    [Parameter(Mandatory = $true)]
    [string] $EnvironmentName,
    [Parameter(Mandatory = $true)]
    [string] $SourceLabel,
    [AllowEmptyString()]
    [string] $ConfiguredName
  )

  $resolvedName = $ConfiguredName
  if ([string]::IsNullOrWhiteSpace($resolvedName)) {
    $resolvedName = Get-DefaultDynamicGroupName -EnvironmentName $EnvironmentName -SourceLabel $SourceLabel
  }

  $groups = @(Get-GroupByDisplayName -DisplayName $resolvedName)
  if ($groups.Count -ne 1) {
    throw "Expected exactly one dynamic group named '$resolvedName', found $($groups.Count)."
  }

  return $groups[0]
}

function Assert-KeyVaultRoleAssignment {
  param(
    [Parameter(Mandatory = $true)]
    [string] $PrincipalId,
    [Parameter(Mandatory = $true)]
    [string] $VaultName
  )

  $vaultId = az keyvault show --name $VaultName --query id --output tsv --only-show-errors
  $assignments = @(az role assignment list --assignee-object-id $PrincipalId --scope $vaultId --query "[].roleDefinitionName" --output tsv --only-show-errors)
  if ($assignments -notcontains 'Key Vault Secrets Officer') {
    throw "Managed identity does not have the 'Key Vault Secrets Officer' role on vault '$VaultName'."
  }
}

function Assert-KeyVaultConfiguration {
  param(
    [Parameter(Mandatory = $true)]
    [string] $VaultName,
    [AllowEmptyString()]
    [string] $ExpectedRetentionInDays
  )

  $vault = az keyvault show --name $VaultName --query '{enableRbacAuthorization:properties.enableRbacAuthorization,enablePurgeProtection:properties.enablePurgeProtection,softDeleteRetentionInDays:properties.softDeleteRetentionInDays}' --output json --only-show-errors | ConvertFrom-Json
  if (-not $vault.enableRbacAuthorization) {
    throw "Key Vault '$VaultName' is not using Azure RBAC for data-plane authorization."
  }

  if (-not $vault.enablePurgeProtection) {
    throw "Key Vault '$VaultName' does not have purge protection enabled."
  }

  if (-not [string]::IsNullOrWhiteSpace($ExpectedRetentionInDays)) {
    $expectedRetention = [int] $ExpectedRetentionInDays
    if ([int] $vault.softDeleteRetentionInDays -ne $expectedRetention) {
      throw "Key Vault '$VaultName' soft-delete retention is $($vault.softDeleteRetentionInDays) day(s), expected $expectedRetention."
    }
  }
}

function Assert-DeleteLock {
  param(
    [Parameter(Mandatory = $true)]
    [string] $ResourceGroupName
  )

  $locks = @(az lock list --resource-group $ResourceGroupName --query "[?level=='CanNotDelete']" --output json --only-show-errors | ConvertFrom-Json)
  if ($locks.Count -eq 0) {
    throw "Resource group '$ResourceGroupName' is expected to have a CanNotDelete lock, but none was found."
  }
}

function Get-LogicAppWorkflow {
  param(
    [Parameter(Mandatory = $true)]
    [string] $SubscriptionId,
    [Parameter(Mandatory = $true)]
    [string] $ResourceGroupName,
    [Parameter(Mandatory = $true)]
    [string] $WorkflowName
  )

  $url = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Logic/workflows/${WorkflowName}?api-version=2019-05-01"
  return az rest --method get --url $url --output json --only-show-errors | ConvertFrom-Json
}

function Get-LogicAppRuns {
  param(
    [Parameter(Mandatory = $true)]
    [string] $SubscriptionId,
    [Parameter(Mandatory = $true)]
    [string] $ResourceGroupName,
    [Parameter(Mandatory = $true)]
    [string] $WorkflowName
  )

  $url = "https://management.azure.com/subscriptions/$SubscriptionId/resourceGroups/$ResourceGroupName/providers/Microsoft.Logic/workflows/${WorkflowName}/runs?api-version=2019-05-01"
  $response = az rest --method get --url $url --output json --only-show-errors | ConvertFrom-Json
  return @($response.value)
}

function Wait-ForLogicAppRun {
  param(
    [Parameter(Mandatory = $true)]
    [string] $SubscriptionId,
    [Parameter(Mandatory = $true)]
    [string] $ResourceGroupName,
    [Parameter(Mandatory = $true)]
    [string] $WorkflowName,
    [Parameter(Mandatory = $true)]
    [datetime] $SinceUtc,
    [int] $TimeoutSeconds = 90
  )

  $deadline = (Get-Date).ToUniversalTime().AddSeconds($TimeoutSeconds)
  do {
    $runs = @(Get-LogicAppRuns -SubscriptionId $SubscriptionId -ResourceGroupName $ResourceGroupName -WorkflowName $WorkflowName)
    $matchingRun = $runs |
      Where-Object {
        $properties = $_.properties
        $null -ne $properties -and
        $null -ne $properties.startTime -and
        ([datetime]::Parse($properties.startTime).ToUniversalTime() -ge $SinceUtc)
      } |
      Sort-Object { [datetime]::Parse($_.properties.startTime).ToUniversalTime() } -Descending |
      Select-Object -First 1

    if ($null -ne $matchingRun) {
      $status = $matchingRun.properties.status
      if ($status -in @('Succeeded', 'Failed', 'Cancelled', 'Skipped', 'TimedOut', 'Aborted')) {
        return $matchingRun
      }
    }

    Start-Sleep -Seconds 5
  } while ((Get-Date).ToUniversalTime() -lt $deadline)

  return $null
}

function Get-InterestingAutomationMessages {
  param(
    [Parameter(Mandatory = $true)]
    [string] $ResourceGroupName,
    [Parameter(Mandatory = $true)]
    [string] $AutomationAccountName,
    [Parameter(Mandatory = $true)]
    [string] $JobId
  )

  $interestingPatterns = @(
    'Starting device cleanup run',
    'Loading excluded devices',
    'Loaded [0-9]+ excluded device',
    'Loading Microsoft Graph advanced hunting heartbeat data',
    'Loaded [0-9]+ advanced hunting heartbeat row',
    'Updated extension attributes on',
    'Excluded [0-9]+ device',
    'Found [0-9]+ disable candidate',
    'Dry run: would disable',
    'Dry run: would archive'
  )

  $lines = @()
  foreach ($output in @(Get-AzAutomationJobOutput -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -Id $JobId -Stream Any)) {
    $record = Get-AzAutomationJobOutputRecord -ResourceGroupName $ResourceGroupName -AutomationAccountName $AutomationAccountName -JobId $JobId -Id $output.StreamRecordId
    $message = $null
    if ($record.Value -is [string]) {
      $message = $record.Value
    }
    elseif ($record.Value.PSObject.Properties.Name -contains 'Message') {
      $message = $record.Value.Message
    }
    elseif ($record.Value.PSObject.Properties.Name -contains 'value') {
      $message = $record.Value.value
    }

    if ([string]::IsNullOrWhiteSpace($message)) {
      continue
    }

    foreach ($pattern in $interestingPatterns) {
      if ($message -match $pattern) {
        $lines += $message
        break
      }
    }
  }

  return $lines
}

$repoRoot = Resolve-Path (Join-Path $PSScriptRoot '..')
Ensure-AzureCli
Ensure-AzAutomationModule
$envValues = Get-AzdEnvironmentValues -RepositoryRoot $repoRoot

$subscriptionId = Get-RequiredEnvironmentValue -EnvironmentValues $envValues -Name 'AZURE_SUBSCRIPTION_ID'
$tenantId = Get-RequiredEnvironmentValue -EnvironmentValues $envValues -Name 'AZURE_TENANT_ID'
$null = az account set --subscription $subscriptionId --only-show-errors
$environmentName = Get-RequiredEnvironmentValue -EnvironmentValues $envValues -Name 'AZURE_ENV_NAME'
$resourceGroupName = Get-RequiredEnvironmentValue -EnvironmentValues $envValues -Name 'AZURE_RESOURCE_GROUP'
$automationAccountName = Get-RequiredEnvironmentValue -EnvironmentValues $envValues -Name 'AUTOMATION_ACCOUNT_NAME'
$runbookName = Get-RequiredEnvironmentValue -EnvironmentValues $envValues -Name 'AUTOMATION_RUNBOOK_NAME'
$automationPrincipalId = Get-RequiredEnvironmentValue -EnvironmentValues $envValues -Name 'AUTOMATION_ACCOUNT_PRINCIPAL_ID'
$keyVaultName = Get-RequiredEnvironmentValue -EnvironmentValues $envValues -Name 'DEVICE_ARCHIVE_KEY_VAULT_NAME'
$deviceArchiveRetentionInDays = Get-OptionalEnvironmentValue -EnvironmentValues $envValues -Name 'DEVICE_ARCHIVE_RETENTION_IN_DAYS'
$advancedHuntingEnabled = ConvertTo-BooleanValue -Name 'ADVANCED_HUNTING_ENABLED' -Value (Get-RequiredEnvironmentValue -EnvironmentValues $envValues -Name 'ADVANCED_HUNTING_ENABLED')
$intuneDynamicGroupEnabled = ConvertTo-BooleanValue -Name 'INTUNE_DYNAMIC_GROUP_ENABLED' -Value (Get-RequiredEnvironmentValue -EnvironmentValues $envValues -Name 'INTUNE_DYNAMIC_GROUP_ENABLED')
$defenderDynamicGroupEnabled = ConvertTo-BooleanValue -Name 'DEFENDER_DYNAMIC_GROUP_ENABLED' -Value (Get-RequiredEnvironmentValue -EnvironmentValues $envValues -Name 'DEFENDER_DYNAMIC_GROUP_ENABLED')
$intuneCheckInAttributeNumber = [int](Get-RequiredEnvironmentValue -EnvironmentValues $envValues -Name 'INTUNE_CHECKIN_ATTRIBUTE_NUMBER')
$defenderCheckInAttributeNumber = [int](Get-RequiredEnvironmentValue -EnvironmentValues $envValues -Name 'DEFENDER_CHECKIN_ATTRIBUTE_NUMBER')
$logicAppNotificationsEnabled = ConvertTo-BooleanValue -Name 'LOGIC_APP_NOTIFICATIONS_ENABLED' -Value (Get-RequiredEnvironmentValue -EnvironmentValues $envValues -Name 'LOGIC_APP_NOTIFICATIONS_ENABLED')
$logicAppNotificationWorkflowName = Get-OptionalEnvironmentValue -EnvironmentValues $envValues -Name 'LOGIC_APP_NOTIFICATION_WORKFLOW_NAME'
$enableDeleteLock = ConvertTo-BooleanValue -Name 'ENABLE_DELETE_LOCK' -Value (Get-RequiredEnvironmentValue -EnvironmentValues $envValues -Name 'ENABLE_DELETE_LOCK')
$exclusionGroupObjectId = Get-OptionalEnvironmentValue -EnvironmentValues $envValues -Name 'EXCLUSION_DEVICE_GROUP_OBJECT_ID'
$exclusionGroupName = Get-OptionalEnvironmentValue -EnvironmentValues $envValues -Name 'EXCLUSION_DEVICE_GROUP_NAME'
$intuneDynamicGroupName = Get-OptionalEnvironmentValue -EnvironmentValues $envValues -Name 'INTUNE_DYNAMIC_GROUP_NAME'
$intuneDynamicGroupRule = Get-OptionalEnvironmentValue -EnvironmentValues $envValues -Name 'INTUNE_DYNAMIC_GROUP_RULE'
$defenderDynamicGroupName = Get-OptionalEnvironmentValue -EnvironmentValues $envValues -Name 'DEFENDER_DYNAMIC_GROUP_NAME'
$defenderDynamicGroupRule = Get-OptionalEnvironmentValue -EnvironmentValues $envValues -Name 'DEFENDER_DYNAMIC_GROUP_RULE'

Connect-AzPowerShellFromCli -SubscriptionId $subscriptionId -TenantId $tenantId

$graphSp = Get-ServicePrincipalInfo -AppId '00000003-0000-0000-c000-000000000000'
$defenderSp = Get-ServicePrincipalInfo -AppId 'fc780465-2017-40d4-a0c5-307022471b92'
$requiredGraphRoles = @(
  'Device.Read.All',
  'Device.ReadWrite.All',
  'Group.Read.All',
  'GroupMember.Read.All',
  'DeviceLocalCredential.Read.All',
  'BitlockerKey.Read.All',
  'DeviceManagementManagedDevices.Read.All'
)
if ($advancedHuntingEnabled) {
  $requiredGraphRoles += 'ThreatHunting.Read.All'
}
Assert-AppRoleAssignments -PrincipalId $automationPrincipalId -ResourceServicePrincipal $graphSp -RequiredRoles $requiredGraphRoles
if ($defenderCheckInAttributeNumber -gt 0) {
  Assert-AppRoleAssignments -PrincipalId $automationPrincipalId -ResourceServicePrincipal $defenderSp -RequiredRoles @(
    'Machine.Read.All'
  )
}
Assert-KeyVaultRoleAssignment -PrincipalId $automationPrincipalId -VaultName $keyVaultName
Assert-KeyVaultConfiguration -VaultName $keyVaultName -ExpectedRetentionInDays $deviceArchiveRetentionInDays

$runbook = Get-AzAutomationRunbook -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName -Name $runbookName
if ($runbook.State -ne 'Published') {
  throw "Runbook '$runbookName' is not published. Current state: $($runbook.State)"
}

$exclusionGroup = Resolve-ExclusionGroup -EnvironmentName $environmentName -ConfiguredGroupId $exclusionGroupObjectId -ConfiguredGroupName $exclusionGroupName
if (-not $exclusionGroup.securityEnabled -or $exclusionGroup.mailEnabled) {
  throw "Exclusion group '$($exclusionGroup.displayName)' is not a security-only Microsoft Entra group."
}

if (@($exclusionGroup.groupTypes) -contains 'DynamicMembership') {
  throw "Exclusion group '$($exclusionGroup.displayName)' uses dynamic membership. Use an assigned security group for exclusions."
}

if ($intuneDynamicGroupEnabled) {
  $intuneDynamicGroup = Resolve-DynamicGroup -EnvironmentName $environmentName -SourceLabel 'Intune' -ConfiguredName $intuneDynamicGroupName
  if (-not $intuneDynamicGroup.securityEnabled -or $intuneDynamicGroup.mailEnabled) {
    throw "Intune dynamic group '$($intuneDynamicGroup.displayName)' is not a security-only Microsoft Entra group."
  }

  if (@($intuneDynamicGroup.groupTypes) -notcontains 'DynamicMembership' -or $intuneDynamicGroup.membershipRuleProcessingState -ne 'On') {
    throw "Intune dynamic group '$($intuneDynamicGroup.displayName)' is not configured as an active dynamic membership group."
  }

  $expectedIntuneRule = $intuneDynamicGroupRule
  if ([string]::IsNullOrWhiteSpace($expectedIntuneRule)) {
    $expectedIntuneRule = Get-DefaultDynamicGroupRule -AttributeNumber $intuneCheckInAttributeNumber -SourceLabel 'Intune'
  }

  if ($intuneDynamicGroup.membershipRule.Trim() -ne $expectedIntuneRule.Trim()) {
    throw "Intune dynamic group '$($intuneDynamicGroup.displayName)' membership rule drifted. Current='$($intuneDynamicGroup.membershipRule)' Expected='$expectedIntuneRule'."
  }
}

if ($defenderDynamicGroupEnabled) {
  $defenderDynamicGroup = Resolve-DynamicGroup -EnvironmentName $environmentName -SourceLabel 'Defender' -ConfiguredName $defenderDynamicGroupName
  if (-not $defenderDynamicGroup.securityEnabled -or $defenderDynamicGroup.mailEnabled) {
    throw "Defender dynamic group '$($defenderDynamicGroup.displayName)' is not a security-only Microsoft Entra group."
  }

  if (@($defenderDynamicGroup.groupTypes) -notcontains 'DynamicMembership' -or $defenderDynamicGroup.membershipRuleProcessingState -ne 'On') {
    throw "Defender dynamic group '$($defenderDynamicGroup.displayName)' is not configured as an active dynamic membership group."
  }

  $expectedDefenderRule = $defenderDynamicGroupRule
  if ([string]::IsNullOrWhiteSpace($expectedDefenderRule)) {
    $expectedDefenderRule = Get-DefaultDynamicGroupRule -AttributeNumber $defenderCheckInAttributeNumber -SourceLabel 'Defender'
  }

  if ($defenderDynamicGroup.membershipRule.Trim() -ne $expectedDefenderRule.Trim()) {
    throw "Defender dynamic group '$($defenderDynamicGroup.displayName)' membership rule drifted. Current='$($defenderDynamicGroup.membershipRule)' Expected='$expectedDefenderRule'."
  }
}

if ($enableDeleteLock) {
  Assert-DeleteLock -ResourceGroupName $resourceGroupName
}

if ($logicAppNotificationsEnabled) {
  if ([string]::IsNullOrWhiteSpace($logicAppNotificationWorkflowName)) {
    throw 'Logic App notifications are enabled, but LOGIC_APP_NOTIFICATION_WORKFLOW_NAME is empty.'
  }

  $logicAppWorkflow = Get-LogicAppWorkflow -SubscriptionId $subscriptionId -ResourceGroupName $resourceGroupName -WorkflowName $logicAppNotificationWorkflowName
  if ($logicAppWorkflow.properties.state -ne 'Enabled') {
    throw "Logic App workflow '$logicAppNotificationWorkflowName' is not enabled. Current state: $($logicAppWorkflow.properties.state)"
  }
}

Write-Host "Preflight checks passed for permissions, Key Vault RBAC/configuration, runbook publish state, Microsoft Entra groups and rules, delete-lock protection, and Logic App configuration."

if (-not $SkipAutomationJob) {
  $automationValidationStartedAtUtc = (Get-Date).ToUniversalTime()
  $job = Start-AzAutomationRunbook -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName -Name $runbookName -Parameters @{
    DisableEnabled = 'false'
    DeleteEnabled = 'false'
    AdvancedHuntingEnabled = if ($advancedHuntingEnabled) { 'true' } else { 'false' }
    NotifyOnNoAction = if ($logicAppNotificationsEnabled) { 'true' } else { 'false' }
  }

  $deadline = (Get-Date).ToUniversalTime().AddMinutes($AutomationJobTimeoutMinutes)
  do {
    Start-Sleep -Seconds 10
    $currentJob = Get-AzAutomationJob -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName -Id $job.JobId
  } while (($currentJob.Status -notin @('Completed', 'Failed', 'Stopped', 'Suspended')) -and ((Get-Date).ToUniversalTime() -lt $deadline))

  if ($currentJob.Status -notin @('Completed', 'Failed', 'Stopped', 'Suspended')) {
    throw "Preflight automation job '$($job.JobId)' did not finish within $AutomationJobTimeoutMinutes minute(s)."
  }

  $interestingMessages = @(Get-InterestingAutomationMessages -ResourceGroupName $resourceGroupName -AutomationAccountName $automationAccountName -JobId $job.JobId)
  foreach ($message in $interestingMessages) {
    Write-Host $message
  }

  if ($currentJob.Status -ne 'Completed') {
    throw "Preflight automation job '$($job.JobId)' ended with status $($currentJob.Status). Exception: $($currentJob.Exception)"
  }

  if ($logicAppNotificationsEnabled) {
    $logicAppRun = Wait-ForLogicAppRun `
      -SubscriptionId $subscriptionId `
      -ResourceGroupName $resourceGroupName `
      -WorkflowName $logicAppNotificationWorkflowName `
      -SinceUtc $automationValidationStartedAtUtc
    if ($null -eq $logicAppRun) {
      throw "The Automation validation run completed, but no Logic App notification run was observed for workflow '$logicAppNotificationWorkflowName'."
    }

    if ($logicAppRun.properties.status -ne 'Succeeded') {
      throw "Logic App workflow '$logicAppNotificationWorkflowName' received the notification, but the workflow run ended with status '$($logicAppRun.properties.status)'."
    }

    Write-Host "Logic App notification validation succeeded. WorkflowRun=$($logicAppRun.name)"
  }

  Write-Host "Safe automation validation succeeded. JobId=$($job.JobId)"
}
