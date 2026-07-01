targetScope = 'resourceGroup'

@description('Automation Account name.')
param automationAccountName string

@description('Automation runtime environment name.')
param automationRuntimeEnvironmentName string

@description('Automation runbook name.')
param automationRunbookName string

@description('Automation schedule name.')
param automationScheduleName string

@description('Primary Azure location for all resources.')
param location string

@description('Common resource tags.')
param tags object = {}

@description('Key Vault name.')
param keyVaultName string

@description('Deploy the Logic App workflow that receives runbook notification events.')
param logicAppNotificationsEnabled bool = true

@description('Logic App workflow name.')
param logicAppNotificationWorkflowName string

@secure()
@description('Optional downstream webhook URL that the Logic App should forward notifications to, such as a Teams workflow trigger URL.')
param logicAppNotificationWebhookUrl string = ''

@allowed([
  'Day'
  'Hour'
])
@description('Recurring frequency for the Azure Automation schedule.')
param cleanupScheduleFrequency string

@minValue(1)
@description('Recurring interval for the Azure Automation schedule.')
param cleanupScheduleInterval int

@description('Start time for the Azure Automation schedule.')
param cleanupScheduleStartTime string

@description('Time zone used by the Azure Automation schedule.')
param cleanupScheduleTimeZone string

@description('Prefix for archived device secrets in Key Vault.')
param secretNamePrefix string

@description('Optional principal that should receive read access to archived secrets.')
param archiveReaderPrincipalId string = ''

@minValue(7)
@maxValue(90)
@description('Retention period in days for Key Vault soft delete recovery.')
param retentionInDays int

var keyVaultSecretsOfficerRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', 'b86a8fe4-44ce-4948-aee5-eccb2c155cd7')
var keyVaultSecretsUserRoleId = subscriptionResourceId('Microsoft.Authorization/roleDefinitions', '4633458b-17de-408a-b874-0445c86b69e6')
resource keyVault 'Microsoft.KeyVault/vaults@2023-07-01' = {
  name: keyVaultName
  location: location
  tags: tags
  properties: {
    enablePurgeProtection: true
    enableRbacAuthorization: true
    enabledForDeployment: false
    enabledForDiskEncryption: false
    enabledForTemplateDeployment: false
    publicNetworkAccess: 'Enabled'
    sku: {
      family: 'A'
      name: 'standard'
    }
    softDeleteRetentionInDays: retentionInDays
    tenantId: tenant().tenantId
  }
}

resource automationAccount 'Microsoft.Automation/automationAccounts@2024-10-23' = {
  name: automationAccountName
  location: location
  identity: {
    type: 'SystemAssigned'
  }
  tags: tags
  properties: {
    disableLocalAuth: false
    encryption: {
      keySource: 'Microsoft.Automation'
    }
    publicNetworkAccess: true
    sku: {
      name: 'Basic'
    }
  }
}

resource runtimeEnvironment 'Microsoft.Automation/automationAccounts/runtimeEnvironments@2024-10-23' = {
  parent: automationAccount
  name: automationRuntimeEnvironmentName
  location: location
  properties: {
    defaultPackages: {}
    description: 'PowerShell 7.6 runtime environment for the device cleanup runbook.'
    runtime: {
      language: 'PowerShell'
      version: '7.6'
    }
  }
}

resource runbook 'Microsoft.Automation/automationAccounts/runbooks@2024-10-23' = {
  parent: automationAccount
  name: automationRunbookName
  location: location
  properties: {
    description: 'Disables stale Entra devices, archives recovery material to Key Vault, and deletes eligible devices.'
    draft: {}
    logActivityTrace: 0
    logProgress: true
    logVerbose: true
    runbookType: 'PowerShell'
    runtimeEnvironment: runtimeEnvironment.name
  }
}

resource schedule 'Microsoft.Automation/automationAccounts/schedules@2024-10-23' = {
  parent: automationAccount
  name: automationScheduleName
  properties: {
    description: 'Runs the device cleanup runbook on its recurring schedule.'
    frequency: cleanupScheduleFrequency
    interval: cleanupScheduleInterval
    startTime: cleanupScheduleStartTime
    timeZone: cleanupScheduleTimeZone
  }
}

resource notificationWorkflow 'Microsoft.Logic/workflows@2019-05-01' = if (logicAppNotificationsEnabled) {
  name: logicAppNotificationWorkflowName
  location: location
  tags: tags
  properties: {
    definition: {
      '$schema': 'https://schema.management.azure.com/providers/Microsoft.Logic/schemas/2016-06-01/workflowdefinition.json#'
      contentVersion: '1.0.0.0'
      parameters: {
        forwardNotifications: {
          type: 'Bool'
          defaultValue: false
        }
        notificationWebhookUrl: {
          type: 'String'
          defaultValue: ''
        }
      }
      triggers: {
        manual: {
          type: 'Request'
          kind: 'Http'
          inputs: {
            schema: {
              type: 'object'
              properties: {
                environmentName: {
                  type: 'string'
                }
                subscriptionId: {
                  type: 'string'
                }
                resourceGroupName: {
                  type: 'string'
                }
                automationAccountName: {
                  type: 'string'
                }
                runbookName: {
                  type: 'string'
                }
                status: {
                  type: 'string'
                }
                severity: {
                  type: 'string'
                }
                summaryText: {
                  type: 'string'
                }
                startedAtUtc: {
                  type: 'string'
                }
                finishedAtUtc: {
                  type: 'string'
                }
                counts: {
                  type: 'object'
                }
                results: {
                  type: 'object'
                }
                failure: {
                  type: 'object'
                }
              }
              required: [
                'environmentName'
                'status'
                'severity'
                'summaryText'
                'startedAtUtc'
                'finishedAtUtc'
              ]
            }
          }
        }
      }
      actions: {
        Forward_to_downstream_webhook: {
          type: 'If'
          expression: {
            and: [
              {
                equals: [
                  '@parameters(\'forwardNotifications\')'
                  true
                ]
              }
            ]
          }
          actions: {
            Post_notification: {
              type: 'Http'
              inputs: {
                method: 'POST'
                uri: '@parameters(\'notificationWebhookUrl\')'
                headers: {
                  'Content-Type': 'application/json'
                }
                body: '@triggerBody()'
              }
            }
          }
          else: {
            actions: {}
          }
          runAfter: {}
        }
      }
      outputs: {}
    }
    parameters: {
      forwardNotifications: {
        value: !empty(logicAppNotificationWebhookUrl)
      }
      notificationWebhookUrl: {
        value: logicAppNotificationWebhookUrl
      }
    }
    state: 'Enabled'
  }
}

resource automationKeyVaultAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = {
  scope: keyVault
  name: guid(keyVault.id, automationAccount.name, 'KeyVaultSecretsOfficer')
  properties: {
    principalId: automationAccount.identity.principalId
    principalType: 'ServicePrincipal'
    roleDefinitionId: keyVaultSecretsOfficerRoleId
  }
}

resource archiveReaderAccess 'Microsoft.Authorization/roleAssignments@2022-04-01' = if (!empty(archiveReaderPrincipalId)) {
  scope: keyVault
  name: guid(keyVault.id, archiveReaderPrincipalId, 'KeyVaultSecretsUser')
  properties: {
    principalId: archiveReaderPrincipalId
    roleDefinitionId: keyVaultSecretsUserRoleId
  }
}

output AUTOMATION_ACCOUNT_NAME string = automationAccount.name
output AUTOMATION_ACCOUNT_PRINCIPAL_ID string = automationAccount.identity.principalId
output AUTOMATION_RUNBOOK_NAME string = runbook.name
output AUTOMATION_RUNTIME_ENVIRONMENT_NAME string = runtimeEnvironment.name
output AUTOMATION_SCHEDULE_NAME string = automationScheduleName
output DEVICE_ARCHIVE_KEY_VAULT_NAME string = keyVault.name
output DEVICE_SECRET_PREFIX string = secretNamePrefix
output LOGIC_APP_NOTIFICATION_WORKFLOW_NAME string = logicAppNotificationsEnabled ? notificationWorkflow.name : ''
