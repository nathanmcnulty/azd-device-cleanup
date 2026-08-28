# Configuration

## Default behavior

By default, the solution **does disable stale devices** and **does not delete devices**.

- `disableEnabled=true`
- `deleteEnabled=false`

That means a fresh deployment will start disabling devices that cross the disable threshold, but it **will not archive-and-delete anything** until you explicitly turn deletion on.

## Configuration

The default deployment wires these settings into the published runbook:

| Setting | Default | Purpose |
| --- | --- | --- |
| `cleanupScheduleFrequency` | `Day` | Runbook cadence |
| `cleanupScheduleInterval` | `1` | Every N days or hours |
| `cleanupScheduleTimeZone` | `UTC` | Schedule time zone |
| `cleanupScheduleStartTime` | computed | Defaults to 15 minutes after deployment unless overridden |
| `logicAppNotificationsEnabled` | `true` | Deploy the Logic App workflow and let the runbook send summary events to it |
| `logicAppNotificationWorkflowName` | computed | Optional Logic App workflow name override |
| `logicAppNotificationWebhookUrl` | empty | Optional secure downstream webhook URL, such as a Teams workflow trigger URL |
| `logicAppNotifyOnSuccess` | `true` | Send notifications for successful runs |
| `logicAppNotifyOnFailure` | `true` | Send notifications for failed runs |
| `logicAppNotifyOnNoAction` | `false` | Send notifications when no disable/delete candidates are found |
| `deviceDisableAfterDays` | `90` | Disable threshold based on inactivity |
| `deviceDeleteAfterDays` | `120` | Delete threshold for already-disabled devices |
| `disableEnabled` | `true` | Default action is to disable stale devices |
| `maxDeleteCount` | `20` | Safety stop for bulk deletion |
| `deleteEnabled` | `false` | **No deletion by default** |
| `exclusionDeviceGroupObjectId` | empty | Optional existing Microsoft Entra security group object ID for devices excluded from disable/delete |
| `exclusionDeviceGroupName` | empty | Optional display name override for the exclusion security group created by post-provision |
| `recoveryGroupObjectId` | empty | Optional existing assigned Microsoft Entra security group object ID for archive recovery operators |
| `recoveryGroupName` | `device-cleanup-recovery` | Group created or reused when no recovery group object ID is supplied |
| `intuneCheckInExtensionAttributeNumber` | `14` | Device extensionAttribute slot for Intune check-in state; set `0` to disable |
| `defenderCheckInExtensionAttributeNumber` | `15` | Device extensionAttribute slot for Defender check-in state from the Defender machines API; set `0` to disable that source |
| `intuneDynamicGroupEnabled` | `true` | Create or update a dynamic device group for the Intune check-in attribute |
| `intuneDynamicGroupName` | empty | Optional display name override for the Intune dynamic group |
| `intuneDynamicGroupRule` | empty | Optional membership rule override for the Intune dynamic group |
| `defenderDynamicGroupEnabled` | `true` | Create or update a dynamic device group for the Defender check-in attribute |
| `defenderDynamicGroupName` | empty | Optional display name override for the Defender dynamic group |
| `defenderDynamicGroupRule` | empty | Optional membership rule override for the Defender dynamic group |
| `advancedHuntingEnabled` | `true` | Enable optional Microsoft Graph security advanced hunting for supplemental Defender state and heartbeat signals |
| `advancedHuntingLookbackDays` | `30` | Timespan for optional Graph advanced hunting queries; maximum 30 days |
| `secretNamePrefix` | `device-cleanup` | Key Vault secret name prefix |
| `retentionInDays` | `90` | Key Vault soft-delete retention |

> [!NOTE]
> This repository currently supplies these values directly through `infra/main.parameters.json`. Edit that file in the initialized project before `azd up` or a later `azd provision`; an arbitrary `azd env set <parameter-name>` does not override a literal value in that file.

## Exclusion security group

The deployment now creates or reuses one **assigned Microsoft Entra security group** for devices that must never be disabled or deleted by the runbook.

Default name:

- `<AZURE_ENV_NAME> - Device cleanup exclusions`

Use one of these patterns:

- leave both exclusion settings empty and let post-provision create the default group
- set `exclusionDeviceGroupName` to change the created/reused group name
- set `exclusionDeviceGroupObjectId` to point at an existing group you already manage

Add excluded devices directly to that group. The runbook reads the group's direct device membership, still updates Intune and Defender extension attributes for excluded devices, and skips those devices during disable/delete candidate selection.

## Safe pilot

For a first deployment that cannot disable or delete devices, set these values in `infra/main.parameters.json`:

```json
"disableEnabled": {
  "value": false
},
"deleteEnabled": {
  "value": false
}
```

Deploy, populate and verify the exclusion group, run `scripts/preflight.ps1`, and inspect the safe job. Enable device disabling only after the selected scope is understood. Keep deletion disabled until the recovery drill succeeds.

## Notification destination

The Logic App records run history without an external connector. To forward the normalized summary, set the sensitive `logicAppNotificationWebhookUrl` Bicep parameter through an approved secret-handling deployment process. Do not commit a real webhook URL to `infra/main.parameters.json`.

## Automation

Noninteractive deployment requires an already authorized Azure/tenant identity and every required value. It does not bypass permission grants, group ownership checks, the delete lock, or the explicit `deleteEnabled` switch.
