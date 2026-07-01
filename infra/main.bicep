targetScope = 'subscription'

@minLength(1)
@maxLength(64)
@description('Name of the azd environment used to derive unique resource names.')
param environmentName string

@metadata({
  azd: {
    type: 'location'
    default: 'eastus'
  }
})
@description('Primary Azure location for all resources.')
param location string

@description('Optional override for the resource group name.')
param resourceGroupName string = ''

@description('Optional override for the Automation Account name.')
param automationAccountName string = ''

@description('Optional override for the Azure Automation runtime environment name.')
param automationRuntimeEnvironmentName string = 'PowerShell76'

@description('Optional override for the Azure Automation runbook name.')
param automationRunbookName string = 'DeviceCleanup'

@description('Optional override for the Azure Automation schedule name.')
param automationScheduleName string = 'device-cleanup-daily'

@description('Optional override for the Key Vault name.')
param keyVaultName string = ''

@description('Deploy the Logic App workflow that receives runbook notification events.')
param logicAppNotificationsEnabled bool = true

@description('Optional override for the Logic App workflow name.')
param logicAppNotificationWorkflowName string = ''

@secure()
@description('Optional downstream webhook URL that the Logic App should forward notifications to, such as a Teams workflow trigger URL.')
param logicAppNotificationWebhookUrl string = ''

@description('Send notifications for successful cleanup runs.')
param logicAppNotifyOnSuccess bool = true

@description('Send notifications for failed cleanup runs.')
param logicAppNotifyOnFailure bool = true

@description('Send notifications for runs that do not find any disable or delete candidates.')
param logicAppNotifyOnNoAction bool = false

@allowed([
  'Day'
  'Hour'
])
@description('Recurring frequency for the Azure Automation schedule.')
param cleanupScheduleFrequency string = 'Day'

@minValue(1)
@description('Recurring interval for the Azure Automation schedule.')
param cleanupScheduleInterval int = 1

@description('Time zone used by the Azure Automation schedule.')
param cleanupScheduleTimeZone string = 'UTC'

@description('Start time for the Azure Automation schedule.')
param cleanupScheduleStartTime string = dateTimeAdd(utcNow('u'), 'PT15M')

@minValue(1)
@description('Disable devices that have not signed in for at least this many days.')
param deviceDisableAfterDays int = 90

@minValue(1)
@description('Delete already-disabled devices that have not signed in for at least this many days.')
param deviceDeleteAfterDays int = 120

@description('Default true so stale devices are disabled automatically after the configured threshold.')
param disableEnabled bool = true

@minValue(1)
@description('Abort the run if more than this many stale devices are found.')
param maxDeleteCount int = 20

@description('Safe default. Devices are never deleted until you explicitly set this to true.')
param deleteEnabled bool = false

@minValue(0)
@maxValue(15)
@description('Device extensionAttribute slot used for the derived Intune check-in value. Set to 0 to disable this enrichment.')
param intuneCheckInExtensionAttributeNumber int = 14

@minValue(0)
@maxValue(15)
@description('Device extensionAttribute slot used for the derived Defender for Endpoint check-in value. Set to 0 to disable this enrichment.')
param defenderCheckInExtensionAttributeNumber int = 15

@description('Optional object ID of an existing Microsoft Entra security group whose device members should be excluded from disable/delete actions. Leave empty to create or reuse a group by name.')
param exclusionDeviceGroupObjectId string = ''

@description('Optional display name override for the Microsoft Entra exclusion security group. Leave empty to use an environment-based default.')
param exclusionDeviceGroupName string = ''

@description('Create or update a Microsoft Entra dynamic device group for the Intune check-in attribute.')
param intuneDynamicGroupEnabled bool = true

@description('Optional display name override for the Intune dynamic device group. Leave empty to use an environment-based default.')
param intuneDynamicGroupName string = ''

@description('Optional membership rule override for the Intune dynamic device group. Leave empty to use the configured Intune extensionAttribute slot and stale-state rule.')
param intuneDynamicGroupRule string = ''

@description('Create or update a Microsoft Entra dynamic device group for the Defender for Endpoint check-in attribute.')
param defenderDynamicGroupEnabled bool = true

@description('Optional display name override for the Defender for Endpoint dynamic device group. Leave empty to use an environment-based default.')
param defenderDynamicGroupName string = ''

@description('Optional membership rule override for the Defender for Endpoint dynamic device group. Leave empty to use the configured Defender extensionAttribute slot and stale-state rule.')
param defenderDynamicGroupRule string = ''

@description('Enable Microsoft Graph advanced hunting queries as an additional heartbeat signal source.')
param advancedHuntingEnabled bool = true

@minValue(1)
@maxValue(90)
@description('Lookback window in days for Microsoft Graph advanced hunting heartbeat queries.')
param advancedHuntingLookbackDays int = 30

@description('Prefix for archived device secrets in Key Vault.')
param secretNamePrefix string = 'device-cleanup'

@description('Optional principal that should receive read access to archived secrets.')
param archiveReaderPrincipalId string = deployer().objectId

@minValue(7)
@maxValue(90)
@description('Retention period in days for Key Vault soft delete recovery.')
param retentionInDays int = 90

@description('Enable a CanNotDelete management lock on the deployed resource group.')
param enableDeleteLock bool = true

var resourceToken = toLower(uniqueString(subscription().id, environmentName, location))
var tags = {
  'azd-env-name': environmentName
  environment: environmentName
  'managed-by': 'azd'
  purpose: 'device-cleanup'
  workload: 'device-cleanup'
}
var rgName = empty(resourceGroupName) ? 'rg-${environmentName}' : resourceGroupName
var automationName = empty(automationAccountName) ? 'aa-${take(resourceToken, 20)}' : automationAccountName
var vaultName = empty(keyVaultName) ? 'kv-${take(resourceToken, 21)}' : keyVaultName
var logicAppWorkflowName = empty(logicAppNotificationWorkflowName) ? 'la-${take(resourceToken, 20)}-cleanup' : logicAppNotificationWorkflowName

resource rg 'Microsoft.Resources/resourceGroups@2024-03-01' = {
  name: rgName
  location: location
  tags: tags
}

module resources './resources.bicep' = {
  name: 'device-cleanup-resources'
  scope: rg
  params: {
    automationAccountName: automationName
    automationRunbookName: automationRunbookName
    automationRuntimeEnvironmentName: automationRuntimeEnvironmentName
    automationScheduleName: automationScheduleName
    archiveReaderPrincipalId: archiveReaderPrincipalId
    cleanupScheduleFrequency: cleanupScheduleFrequency
    cleanupScheduleInterval: cleanupScheduleInterval
    cleanupScheduleStartTime: cleanupScheduleStartTime
    cleanupScheduleTimeZone: cleanupScheduleTimeZone
    keyVaultName: vaultName
    logicAppNotificationWebhookUrl: logicAppNotificationWebhookUrl
    logicAppNotificationWorkflowName: logicAppWorkflowName
    logicAppNotificationsEnabled: logicAppNotificationsEnabled
    location: location
    retentionInDays: retentionInDays
    secretNamePrefix: secretNamePrefix
    tags: tags
  }
}

output AZURE_LOCATION string = location
output AZURE_RESOURCE_GROUP string = rg.name
output AZURE_SUBSCRIPTION_ID string = subscription().subscriptionId
output AZURE_TENANT_ID string = tenant().tenantId
output AUTOMATION_ACCOUNT_NAME string = resources.outputs.AUTOMATION_ACCOUNT_NAME
output AUTOMATION_ACCOUNT_PRINCIPAL_ID string = resources.outputs.AUTOMATION_ACCOUNT_PRINCIPAL_ID
output AUTOMATION_RUNBOOK_NAME string = resources.outputs.AUTOMATION_RUNBOOK_NAME
output AUTOMATION_RUNTIME_ENVIRONMENT_NAME string = resources.outputs.AUTOMATION_RUNTIME_ENVIRONMENT_NAME
output AUTOMATION_SCHEDULE_NAME string = resources.outputs.AUTOMATION_SCHEDULE_NAME
output ADVANCED_HUNTING_ENABLED string = advancedHuntingEnabled ? 'true' : 'false'
output ADVANCED_HUNTING_LOOKBACK_DAYS string = string(advancedHuntingLookbackDays)
output CLEANUP_SCHEDULE_FREQUENCY string = cleanupScheduleFrequency
output CLEANUP_SCHEDULE_INTERVAL string = string(cleanupScheduleInterval)
output CLEANUP_SCHEDULE_START_TIME string = cleanupScheduleStartTime
output CLEANUP_SCHEDULE_TIME_ZONE string = cleanupScheduleTimeZone
output DEVICE_ARCHIVE_KEY_VAULT_NAME string = resources.outputs.DEVICE_ARCHIVE_KEY_VAULT_NAME
output DEVICE_DELETE_AFTER_DAYS string = string(deviceDeleteAfterDays)
output DEVICE_DELETE_ENABLED string = deleteEnabled ? 'true' : 'false'
output DEVICE_DISABLE_AFTER_DAYS string = string(deviceDisableAfterDays)
output DEVICE_DISABLE_ENABLED string = disableEnabled ? 'true' : 'false'
output EXCLUSION_DEVICE_GROUP_NAME string = exclusionDeviceGroupName
output EXCLUSION_DEVICE_GROUP_OBJECT_ID string = exclusionDeviceGroupObjectId
output DEFENDER_DYNAMIC_GROUP_ENABLED string = defenderDynamicGroupEnabled ? 'true' : 'false'
output DEFENDER_DYNAMIC_GROUP_NAME string = defenderDynamicGroupName
output DEFENDER_DYNAMIC_GROUP_RULE string = defenderDynamicGroupRule
output DEFENDER_CHECKIN_ATTRIBUTE_NUMBER string = string(defenderCheckInExtensionAttributeNumber)
output DEVICE_MAX_DELETE_COUNT string = string(maxDeleteCount)
output DEVICE_SECRET_PREFIX string = resources.outputs.DEVICE_SECRET_PREFIX
output ENABLE_DELETE_LOCK string = enableDeleteLock ? 'true' : 'false'
output INTUNE_DYNAMIC_GROUP_ENABLED string = intuneDynamicGroupEnabled ? 'true' : 'false'
output INTUNE_DYNAMIC_GROUP_NAME string = intuneDynamicGroupName
output INTUNE_DYNAMIC_GROUP_RULE string = intuneDynamicGroupRule
output INTUNE_CHECKIN_ATTRIBUTE_NUMBER string = string(intuneCheckInExtensionAttributeNumber)
output LOGIC_APP_NOTIFICATIONS_ENABLED string = logicAppNotificationsEnabled ? 'true' : 'false'
output LOGIC_APP_NOTIFICATION_WORKFLOW_NAME string = resources.outputs.LOGIC_APP_NOTIFICATION_WORKFLOW_NAME
output LOGIC_APP_NOTIFY_ON_FAILURE string = logicAppNotifyOnFailure ? 'true' : 'false'
output LOGIC_APP_NOTIFY_ON_NO_ACTION string = logicAppNotifyOnNoAction ? 'true' : 'false'
output LOGIC_APP_NOTIFY_ON_SUCCESS string = logicAppNotifyOnSuccess ? 'true' : 'false'
