# Identity and authentication

## Administrator authority

The deployment operator needs Azure resource deployment and role-assignment authority in the selected subscription, plus feature-operation authority to create or update the configured Entra groups. A separate **Global Administrator or Privileged Role Administrator** must grant or assign the Microsoft Graph application permissions listed below. The Defender application permission follows its own Defender consent path. The scripts fail when the selected Azure CLI context cannot perform the required operation; they do not switch accounts or tenants automatically.

## Authentication flow

The deployment and operational helpers reuse the selected Azure CLI session. If sign-in is required, use standard `azd auth login`, `az login`, `Connect-AzAccount`, or the normal browser/operating-system broker flow. Never use device-code authentication. Tokens are acquired in process for the intended resource and must not be printed, logged, or supplied to an agent.

## Required API application permissions

The Automation Account managed identity needs these **Microsoft Graph** app roles:

- `Device.Read.All`
- `Device.ReadWrite.All`
- `Group.Read.All`
- `GroupMember.Read.All`
- `DeviceManagementManagedDevices.Read.All` when `intuneCheckInExtensionAttributeNumber` is greater than `0` or `primaryArchiveUserCollectionEnabled=true`
- `ThreatHunting.Read.All` when `advancedHuntingEnabled=true`
- `DeviceLocalCredential.Read.All`
- `BitlockerKey.Read.All`

The identity also needs the Defender for Endpoint application permission `Machine.Read.All` when `defenderCheckInExtensionAttributeNumber` is greater than `0`. `scripts/postprovision.ps1` and `scripts/postprovision.sh` assign the required roles after infrastructure provisioning. `ThreatHunting.Read.All` is assigned only when `advancedHuntingEnabled=true`. The Intune read role is removed only when both Intune heartbeat enrichment and primary-user collection are disabled. Primary-user collection does not require `User.Read.All`; it uses the managed-device users relationship under the existing Intune read role. `Machine.Read.All` is assigned when the Defender extension attribute is enabled and removed when that source is disabled. Without the required Graph app-role consent/assignment, postprovision can leave the Azure resources present but cannot complete workload setup, and the runbook's Graph-backed cleanup paths will not work at runtime.

The Intune primary-user relationship is optional and can be incomplete or unavailable in a tenant. Code and offline fixtures establish the bounded request and failure behavior only. A bounded read-only check on 2026-10-07 reached the selected lab tenant's `managedDevices` collection and received HTTP 403 before the direct users route could be reached. Access and visibility qualification therefore remains blocked; the evidence does not identify whether permission, licensing, role, or another tenant condition caused the response, and it does not establish that the relationship route is unsupported.

The code-evidence hashes in `azd-permissions.json` use canonical UTF-8 bytes with LF line endings, matching Git-cleaned committed content across Windows and non-Windows checkouts.

## Access model and RBAC guidance

Use separate access paths for automation and human recovery:

- The Automation Account managed identity should keep only the write access it needs for cleanup and archive creation.
- Post-provisioning creates or reuses the assigned `device-cleanup-recovery` security group, or accepts `recoveryGroupObjectId`, and grants it `Key Vault Secrets User` only on the archive vault.
- Add human operators who may retrieve LAPS or BitLocker material to that recovery group. Use PIM for Groups or another approval process when eligible access is required; Azure RBAC assignment alone does not make group membership eligible.
- The deployment does not grant the deploying user direct secret access. Existing environments upgraded from an earlier version should review and remove any obsolete direct `Key Vault Secrets User` assignments after confirming group-based recovery access.
- Treat archive read access as a privileged recovery action and review it regularly.
- If high-value devices or exclusion groups need tighter control, place them behind a restricted management administrative unit (RMAU) and scope recovery permissions accordingly.

## Security boundaries

- The Automation Account system-assigned managed identity performs device reads/writes and archive creation.
- Human archive access is granted through the assigned recovery group with `Key Vault Secrets User` on the archive vault.
- The deploying user is not granted direct secret-read access.
- The exclusion, recovery, and dynamic groups may be created or reused by name. Treat a name match as a discovered tenant object and verify its exact object ID and existing ownership before deployment or cleanup.
- The optional downstream webhook is a bearer secret. Configure and handle it as a secret; do not place it in documentation, logs, or agent prompts.
- Restricted management administrative units can block operations unless the workload identity has the required scoped authority. The runbook records the per-device failure and continues.
