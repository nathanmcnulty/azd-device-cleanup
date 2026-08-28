# Operations

## Verify

Run the supported validator after every deployment or material configuration change:

```powershell
.\scripts\preflight.ps1
```

Use `-SkipAutomationJob` only when you deliberately cannot run the safe job. The default validation job overrides both actions to false, so it can verify discovery, enrichment, exclusions, permissions, archive infrastructure, and notification wiring without disabling or deleting a device.

## Deploy and update

The supported administrator path is:

```powershell
azd init -t nathanmcnulty/azd-device-cleanup && azd up
```

Rerun `azd up` after reviewing configuration changes. The post-provision hook reconciles workload permissions and groups, publishes the runbook, and links the schedule. Existing devices already disabled by an earlier run are not restored by rerunning the deployment.

## Logic App notifications and reporting

The deployment now creates an **Azure Logic App Consumption workflow** for cleanup reporting by default.

- The runbook posts a normalized JSON summary at the end of each successful run and whenever a run fails.
- The Logic App always records the event in workflow run history.
- If you set `logicAppNotificationWebhookUrl`, the Logic App also forwards the same JSON payload to that downstream webhook.

This keeps the Azure deployment fully automated without requiring pre-authorized connector resources. A simple first use is to point the webhook at a Teams workflow trigger, another Logic App, or any internal HTTP endpoint that should receive cleanup alerts.

The summary payload includes:

- environment, subscription, resource group, automation account, and runbook names
- `cleanupRunId` so notifications and archived device records can be correlated to the same run
- run status and severity
- candidate counts, dry-run counts, executed disable/delete counts, and excluded-device counts
- per-device execution details for disable/archive-delete actions
- failure details when a run terminates with an error, plus per-device action failures when a run partially succeeds

## Troubleshoot

Start with the preflight error and the corresponding authoritative system:

- Azure CLI context for subscription or tenant mismatches.
- Managed identity app-role assignments for Graph or Defender authorization.
- Key Vault RBAC, purge protection, and retention for archive failures.
- Exact Entra group object IDs, types, membership rules, and direct exclusion membership.
- Automation job streams for per-device restricted administrative unit or telemetry failures.
- Logic App run history for delivery failures.

If Defender sources are unavailable, the run skips disable/delete actions rather than treating missing telemetry as inactivity. Missing LAPS or BitLocker data alone does not block deletion, but archive retrieval or Key Vault write failure blocks deletion for that device.

## Operational notes

- The runbook file is `runbooks/DeviceCleanup.ps1`.
- The preflight validator is `scripts/preflight.ps1`.
- The archive retrieval helper is `scripts/Get-ArchivedDevice.ps1`.
- The Automation Account uses a system-assigned managed identity and writes archives to Key Vault through RBAC.
- Defender state uses `GET /api/machines` from the Defender for Endpoint API as the primary source, including for Defender for Business and Defender for Endpoint Plan 1 tenants where Microsoft Graph `runHuntingQuery` is unavailable. Optional Graph advanced hunting adds event evidence and can provide a fallback heartbeat only where licensed.
- The same runbook can update check-in extension attributes across `AzureAd`, `ServerAd`, `Workplace`, and null-trust device types. This was tested in the tenant used for validation.
- Devices in a restricted management administrative unit can reject extensionAttribute updates or lifecycle actions unless the Automation identity is scoped into that administrative unit. The runbook logs those per-device failures, skips the protected device, and continues processing other candidates.
- For high-value devices and the groups that protect them, consider a **restricted management administrative unit (RMAU)** so accidental cleanup or group changes require the correct scoped administrative role.
- The Defender machines API uses the tenant's configured machine-retention period. Advanced hunting is optional, limited to a maximum 30-day lookback, and provides supplemental event evidence or a fallback when the machines API is unavailable. If both Defender sources are unavailable, the run skips disable/delete actions for that run.
- If a tenant does not have the required advanced hunting licensing or data sources, set `advancedHuntingEnabled=false`; the Defender machines API can still provide the primary heartbeat and extension-attribute data.
- The resource group gets a `CanNotDelete` lock by default. Remove it before running `azd down`.
- Missing LAPS or BitLocker data does **not** block deletion.
- Archive retrieval or Key Vault write failures **do** block deletion for the affected device and produce a partial-success failure notification without stopping the remaining candidate batch.
- Archived device records now include correlation metadata (`cleanupRunId`, heartbeat source, and per-system identifiers) to make notifications and recovery lookups line up.
- The current implementation deletes only the Entra device. Intune and Defender for Endpoint cleanup can be added around the same archive record later.

## Cleanup

1. Keep deletion disabled and stop the schedule if investigating or preparing teardown.
2. Resolve the exact azd resource group:

   ```powershell
   $resourceGroup = azd env get-value AZURE_RESOURCE_GROUP
   ```

3. Delete the exact resource-group lock and remove the ARM deployment:

   ```powershell
   az lock delete --name resource-group-delete-lock --resource-group $resourceGroup
   azd down --purge --force
   ```

The Azure Automation account, its managed identity and app-role assignments, Logic App, and other ARM resources are removed. Because the Key Vault has purge protection, `--purge` cannot permanently purge it before the retention period; the soft-deleted vault and archives remain recoverable.

The following tenant state is preserved:

- disabled or deleted device outcomes;
- device extension-attribute values;
- exclusion, recovery, and dynamic groups created or reused by the hook;
- memberships and dynamic rules;
- any event already forwarded to a downstream system.

Delete only tenant objects whose exact IDs and ownership you have verified. A reused group may predate this template and must not be deleted merely because its name matches.
