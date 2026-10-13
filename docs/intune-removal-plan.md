# Optional Intune managed-device removal plan

## Status and boundary

This is the design contract for the post-v1 Intune cleanup option. It does not
implement an Intune write, enable a feature, change infrastructure, add a
schedule, grant a permission, read an archive, or authorize a live deletion.
Implementation and live qualification remain separate work.

The only supported removal operation in this design is the Microsoft Graph
v1.0 managed-device delete:

```http
DELETE /v1.0/deviceManagement/managedDevices/{managedDeviceId}
```

It deletes the Intune `managedDevice` record addressed by its Intune
`managedDevice.id`. It is not a remote retire or wipe action. Retire and wipe
are different `POST` device actions, require
`DeviceManagementManagedDevices.PrivilegedOperations.All`, and can affect the
enrolled endpoint. They are outside this plan.

The delete API returns `204 No Content` when the request is accepted. That
response is an API acknowledgement, not proof that a later read can no longer
find the record. An eventual implementation must keep acknowledgement and
post-delete observation as separate evidence.

## Identifier rules

Four identifiers must never be interchanged:

| Field | Meaning | Required source |
| --- | --- | --- |
| `tenantId` | Microsoft Entra tenant GUID from the Graph access-token `tid` claim and the deployed environment | Captured independently for archive, Entra deletion, discovery, and removal-plan evidence; all values must be identical |
| `entraObjectId` | Microsoft Entra directory `device.id`; current `Remove-EntraDevice` addresses `/devices/{entraObjectId}` | Archive payload/index and the exact Entra deletion attempt |
| `deviceId` | Microsoft Entra device registration identifier `device.deviceId`; Intune exposes the relationship as `managedDevice.azureADDeviceId` | Exact archived Entra device snapshot and a fresh Intune query |
| `intuneManagedDeviceId` | Intune `managedDevice.id`; the only identifier allowed in the managed-device DELETE path | Unique fresh Intune match, direct GET readback, and exact archive receipt |

Matching tenant IDs only establish that evidence came from the same tenant.
They do not establish that an Intune object belongs to this cleanup decision or
that its deletion is authorized. Display name, device name, serial number,
user, platform, and latest-heartbeat selection are corroborating fields only.
None is a unique key or an authorization signal.
`managedDeviceOwnerType` describes Intune's company/personal classification; it
does not prove that this automation owns the record or may delete it.

`New-IntuneManagedDeviceIndex` cannot identify a deletion target. It groups by
`azureADDeviceId` and retains only the row with the latest
`lastSyncDateTime`; multiple Intune records can therefore collapse to one row.
The same restriction applies to any archive heartbeat derived from that index.

## Inert removal-plan contract

Plan generation produces immutable JSON and performs no write. A future
executor must accept only this complete logical contract; a partial record is
ineligible:

```json
{
  "schemaVersion": "1.0",
  "kind": "intune-managed-device-removal-plan",
  "planId": "9ef26913-5b45-4c26-b222-2fa37de15d41",
  "planCreatedAt": "2026-10-13T22:30:00.0000000Z",
  "cleanupRunId": "9a7250e2-65a4-466c-a873-082ac58eb814",
  "tenantId": "11111111-1111-4111-8111-111111111111",
  "entra": {
    "objectId": "22222222-2222-4222-8222-222222222222",
    "deviceId": "33333333-3333-4333-8333-333333333333",
    "deleteRequest": {
      "method": "DELETE",
      "resourcePath": "/v1.0/devices/22222222-2222-4222-8222-222222222222",
      "acknowledgedAt": "2026-10-13T22:29:31.0000000Z",
      "statusCode": 204
    },
    "absenceObservation": {
      "method": "GET",
      "resourcePath": "/v1.0/devices/22222222-2222-4222-8222-222222222222",
      "observedAt": "2026-10-13T22:29:35.0000000Z",
      "statusCode": 404
    }
  },
  "archiveReceipt": {
    "vaultResourceId": "/subscriptions/44444444-4444-4444-8444-444444444444/resourceGroups/example/providers/Microsoft.KeyVault/vaults/example-vault",
    "archiveSecretId": "https://example-vault.vault.azure.net/secrets/device-cleanup-example-22222222-2222-4222-8222-222222222222/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "archiveSecretVersion": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
    "archivePayloadSha256": "bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb",
    "indexSecretId": "https://example-vault.vault.azure.net/secrets/device-archive-index-cccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccccc/dddddddddddddddddddddddddddddddd",
    "indexSecretVersion": "dddddddddddddddddddddddddddddddd",
    "indexPayloadSha256": "eeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee",
    "verifiedAt": "2026-10-13T22:29:27.0000000Z"
  },
  "intuneTarget": {
    "managedDeviceId": "55555555-5555-4555-8555-555555555555",
    "azureADDeviceId": "33333333-3333-4333-8333-333333333333",
    "serialNumber": "EXAMPLE-SERIAL",
    "deviceName": "EXAMPLE-DEVICE",
    "managedDeviceOwnerType": "company",
    "discoveredAt": "2026-10-13T22:29:20.0000000Z",
    "collectionMatchCount": 1,
    "directReadObservedAt": "2026-10-13T22:29:21.0000000Z",
    "postEntraDeleteReadObservedAt": "2026-10-13T22:29:38.0000000Z"
  },
  "decision": {
    "eligible": true,
    "operation": "DELETE",
    "resourcePath": "/v1.0/deviceManagement/managedDevices/55555555-5555-4555-8555-555555555555"
  }
}
```

The production contract must be a closed schema: unknown properties fail
validation; GUIDs use canonical GUID-D form; timestamps are UTC strings; secret
versions are exact 32-character versions; hashes are lowercase SHA-256; and the
DELETE path is derived from the validated `intuneManagedDeviceId`, never
accepted as a free-form URI. The plan digest and an explicit authorization for
that exact tenant and target must be supplied to a later execution task. This
design does not define or synthesize the organization's approval mechanism.

## Evidence provenance and decision sequence

Each fact must carry its actual source. A summary field, log line, notification,
or plan assertion cannot substitute for the underlying service response.

1. **Fresh Intune identity proof.** Immediately before the archive, query the
   v1.0 managed-device collection for the exact Entra `deviceId` through
   `azureADDeviceId`, follow only validated Graph continuation URLs, and retain
   every exact match. There must be exactly one distinct `managedDevice.id`.
   Direct-GET that ID with at least
   `id,azureADDeviceId,serialNumber,deviceName,managedDeviceOwnerType` and
   require the same ID and Entra `deviceId`. Any mismatch or extra row refuses
   the candidate; selecting the newest row is forbidden.
2. **Archive receipt.** `Save-DeviceArchive` currently writes the archive
   first and the version-bound index second. A future implementation must add
   `tenantId` to both closed payloads and return both complete versioned secret
   IDs. It must then read those exact versions, validate the closed schemas,
   recompute the compact-payload SHA-256 values, and verify identical
   `tenantId`, `entraObjectId`, `deviceId`, `intuneManagedDeviceId`, and
   `cleanupRunId`. A latest alias, secret tags alone, an unversioned URI, a PUT
   response alone, or a reader search result is insufficient.
3. **Entra delete receipt.** Record the exact object-ID path, tenant, run,
   response code, and timestamp from the `Remove-EntraDevice` request. A 204 is
   required but is only acknowledgement. Perform a bounded direct GET of that
   same `entraObjectId`; only an observed 404 from the same tenant completes
   the prerequisite. Timeout, 403, 429 exhaustion, 5xx exhaustion, malformed
   response, or a returned object is a refusal.
4. **Post-Entra Intune revalidation.** After the Entra absence observation,
   direct-GET the exact archived `intuneManagedDeviceId`. Require that the
   returned `id` and `azureADDeviceId` still equal the pre-archive discovery,
   and refuse a conflicting serial number, device name, or ownership
   classification. A 404 means there is no Intune action to take, but it cannot
   be reported as this workflow's successful removal. A missing or cleared
   relationship, 403, timeout, or exhausted transient failure refuses the
   plan. Do not rediscover a replacement by name, serial number, or newest
   heartbeat after the Entra device is gone.
5. **Plan binding.** Bind all evidence to one `tenantId`, `cleanupRunId`,
   `entraObjectId`, `deviceId`, `intuneManagedDeviceId`, exact archive version,
   and exact index version. Build the plan immediately from these observations.
   Evidence from another run, another archive version, a previous discovery,
   or an unknown timestamp cannot be combined. A later executor must re-read
   the exact managed-device ID and re-check the bindings before any DELETE; a
   changed, missing, ambiguous, foreign, or unreadable target refuses action.
6. **Execution evidence.** If separately implemented and authorized, record
   the Intune DELETE acknowledgement. Then perform bounded direct-GET
   observation. Preserve `204` and later `404` separately. A 204 without a
   post-delete 404 is `acknowledged-unproven`; it must not be reported as a
   proven removal or retried blindly.

The plan is single use. Any failed prerequisite, changed identifier, changed
archive bytes, replayed `cleanupRunId`, or elapsed execution window invalidates
it. The implementation task must choose and test a short maximum plan age based
on observed service behavior; this design intentionally does not invent a
production duration without live qualification.

## Refusal matrix

| Observation | Decision | Reason |
| --- | --- | --- |
| Archive or index is absent, unversioned, unreadable, schema-invalid, or hash-invalid | Refuse | There is no complete exact-version recovery receipt |
| Archive and index exist but tenant, run, Entra object, device, or Intune ID differs | Refuse | Evidence is mixed, foreign, or stale |
| Archive contains no `intuneManagedDeviceId` | Refuse | The intended Intune object was not archived |
| Entra DELETE is absent, failed, or returned anything except 204 | Refuse | Required prior operation was not acknowledged |
| Entra DELETE returned 204 but direct GET is not an observed 404 | Refuse | Acknowledgement is not proven state |
| Intune query returns zero exact matches | Refuse | There is no target; do not reinterpret this as success |
| Intune query returns two rows with the same `azureADDeviceId` | Refuse | Ownership is ambiguous; newest heartbeat cannot choose |
| Exact Intune target returns 404 after Entra deletion | Record `already-absent`, no action | Absence is observed, but this workflow did not remove it |
| Collection match and direct GET IDs differ | Refuse | Target changed or collection evidence is stale |
| Intune row has a different or missing `azureADDeviceId` | Refuse | Relationship to the archived Entra registration is unproven |
| Serial number or display name differs while IDs match | Refuse pending investigation | Corroborating evidence conflicts; do not erase the conflict |
| All IDs match, but evidence is from another tenant or cleanup run | Refuse | Same shape does not establish common provenance |
| All technical checks pass, but exact-target execution authorization is absent | Refuse | Relationship and tenant membership are not authorization |
| Intune DELETE returns 204 and later direct GET returns 403/timeout/5xx | Record `acknowledged-unproven` | The API accepted a request, but absence is unproven |
| Intune DELETE returns 204 and bounded direct GET returns 404 | Record `proven-absent` | Both request acknowledgement and observed state are present |

## Current-source mapping and implementation gaps

| Current source | What it establishes | What it cannot establish |
| --- | --- | --- |
| `Save-DeviceArchive` archive payload | Entra object/device IDs, cleanup run, and selected Intune snapshot | Tenant ID, exact-version readback, payload digest, or later Entra/Intune state |
| `device-archive-index` v1.0 | Exact archive secret version and optional Intune managed-device ID | Tenant binding, index version in the returned receipt, or successful readback |
| `New-IntuneManagedDeviceIndex` | Heartbeat enrichment keyed by `azureADDeviceId` | Unique Intune ownership; duplicates are collapsed |
| `Get-PrimaryArchiveUser` | A bounded fresh relationship lookup with duplicate refusal for its own optional purpose | Removal authorization; primary user identity is not device ownership |
| `Remove-EntraDevice` | A DELETE request against exact `entraObjectId` when no exception is returned | Response receipt details or post-delete absence |
| `New-DeviceCleanupActionRecord` and `archivedDeletedDevices` job summary | Added only after `Save-DeviceArchive` and `Remove-EntraDevice` return; preserves run ID, secret name, and recovery-material counts | Drops `SecretVersion` and `IndexSecretName`, has no tenant or service-response receipt, and cannot prove exact-version archive recovery or post-delete state |
| `Get-ArchivedDevice.ps1` | Strict metadata discovery and exact archive-version recovery | Automatic approval or a cleanup target; it is a human recovery reader |

An implementation change therefore needs a new closed plan schema and offline
fixtures, tenant-bound archive/index schema evolution, exact-version archive
readback, a deletion receipt plus Entra absence observation, non-collapsing
Intune discovery, direct target readback, single-use execution checks, and
separate acknowledgement/absence reporting. It must not reuse the heartbeat
index as a target selector.

In particular, an existing `archivedDeletedDevices` row and archive-index v1.0
record cannot be upgraded into a trustworthy removal plan after the fact. The
row lost the archive version and index name, while the index has no tenant ID
and permits a null Intune ID. A future dedicated collector must create the
complete tenant-bound receipt from contemporaneous service responses. It must
never infer missing historical success, tenant, version, or target fields from
labels, latest aliases, heartbeat order, or later lookups.

No infrastructure or default changes are justified by this design. The
existing managed identity has Intune read-only application permission for the
current heartbeat and optional archive-user features. Future managed-device
DELETE implementation requires the application permission
`DeviceManagementManagedDevices.ReadWrite.All`; it requires administrator
consent and an active Intune license for the tenant. The permission must remain
absent until implementation and live deletion are separately authorized.
Delegated implementations would additionally be constrained by the signed-in
user's Intune authority and scope; this Automation design is app-only.

## Microsoft references

Microsoft documentation reviewed on 2026-10-13:

- [Delete managedDevice](https://learn.microsoft.com/en-us/graph/api/intune-devices-manageddevice-delete?view=graph-rest-1.0) documents the v1.0 DELETE path, `DeviceManagementManagedDevices.ReadWrite.All`, active Intune tenant licensing, and 204 response.
- [Get managedDevice](https://learn.microsoft.com/en-us/graph/api/intune-devices-manageddevice-get?view=graph-rest-1.0) documents direct read and the least-privileged `DeviceManagementManagedDevices.Read.All` application permission.
- [List managedDevices](https://learn.microsoft.com/en-us/graph/api/intune-devices-manageddevice-list?view=graph-rest-1.0) documents collection read and the active Intune license requirement.
- [managedDevice resource](https://learn.microsoft.com/en-us/graph/api/resources/intune-devices-manageddevice?view=graph-rest-1.0) distinguishes `managedDevice.id`, `azureADDeviceId`, and device actions.
- [Retire](https://learn.microsoft.com/en-us/graph/api/intune-devices-manageddevice-retire?view=graph-rest-1.0) and [wipe](https://learn.microsoft.com/en-us/graph/api/intune-devices-manageddevice-wipe?view=graph-rest-1.0) document separate POST actions and their privileged-operations permission.
- [Microsoft Graph permissions reference](https://learn.microsoft.com/en-us/graph/permissions-reference) documents that both Intune read and read/write application permissions require administrator consent and that read/write excludes high-impact operations such as wipe.
- [Microsoft Graph application permissions](https://learn.microsoft.com/en-us/graph/permissions-overview#application-permissions) documents app-only authority and administrator consent.
