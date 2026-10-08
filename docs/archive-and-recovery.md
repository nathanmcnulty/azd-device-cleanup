# Archive and recovery

## Secret naming and lookup

Secrets use this shape:

`device-cleanup-<sanitized-display-name>-<entra-object-id>`

Each secret also gets tags for:

- `displayName`
- `deviceId`
- `entraObjectId`
- `archivedAt`
- `cleanupSource`

Every newly successful archive version also gets a companion metadata-index secret named `device-archive-index-<sha256>`, where the hash covers the complete normalized versioned archive URI. The index has a distinct content type and schema, and its tags contain bounded lookup hints without a UPN. The archive succeeds first, the index succeeds second, and device deletion occurs only after both writes. An index failure can therefore leave a recoverable orphan archive version, but it cannot permit deletion.

The fixed index value includes only the archive name, exact 32-hex version and canonical public-vault URI, bounded device identifiers, display name, serial number, archived time, cleanup run ID, and bounded primary-user state, ID, and UPN. Entra object IDs, Entra device IDs, Intune managed-device IDs, and primary-user IDs use GUID-D syntax; Defender machine IDs use the service's 40-hex syntax. Arbitrary device, heartbeat, LAPS, BitLocker, or recovery objects are rejected. The compact index value is limited to 8,192 UTF-8 bytes; scalar lengths are validated and never silently truncated.

## Archive schema

Each archived device is stored as a JSON secret like:

```json
{
  "schemaVersion": "1.0",
  "archivedAt": "2026-06-29T00:00:00Z",
  "sources": {
    "entra": true,
    "intune": true,
    "defenderForEndpoint": true
  },
  "device": {
    "entraObjectId": "2df5508d-1bb5-4fe0-b4c6-5f8b9d9dc1f1",
    "deviceId": "4a5adf6d-17d2-4c74-9a08-9ca3a6e4ef1e",
    "displayName": "LT-12345",
    "accountEnabled": false,
    "operatingSystem": "Windows",
    "operatingSystemVersion": "11",
    "trustType": "AzureAd",
    "approximateLastSignInDateTime": "2026-03-01T02:30:00Z"
  },
  "intune": {
    "state": "Fresh",
    "lastSyncDateTime": "2026-02-28T00:00:00.0000000Z",
    "managedDeviceId": "93fbeef1-3dca-4ee5-b986-89183f4c2868",
    "deviceName": "LT-12345",
    "extensionAttributeValue": "Fresh|2026-02-28T00:00:00.0000000Z"
  },
  "defenderForEndpoint": {
    "state": "Fresh",
    "lastSeen": "2026-02-28T00:00:00.0000000Z",
    "machineId": "1e5bc9d7e413ddd7902c2932e418702b84d0cc07",
    "deviceName": "LT-12345",
    "sensorHealthState": "Active",
    "onboardingStatus": "Onboarded",
    "extensionAttributeValue": "Fresh|2026-02-28T00:00:00.0000000Z"
  },
  "heartbeats": {
    "effective": {
      "state": "Fresh",
      "timestamp": "2026-02-28T00:00:00.0000000Z",
      "source": "AdvancedHunting:DeviceLogonEvents",
      "inactiveDays": 2
    },
    "entra": {
      "timestamp": "2026-02-01T00:00:00.0000000Z"
    },
    "intune": {
      "timestamp": "2026-02-28T00:00:00.0000000Z",
      "state": "Fresh",
      "sourceFound": true
    },
    "defenderForEndpoint": {
      "timestamp": "2026-02-28T00:00:00.0000000Z",
      "state": "Fresh",
      "sourceFound": true
    },
    "advancedHunting": [
      {
        "sourceTable": "DeviceInfo",
        "timestamp": "2026-02-28T00:00:00.0000000Z",
        "deviceName": "LT-12345",
        "record": {
          "SourceTable": "DeviceInfo"
        }
      }
    ]
  },
  "laps": {
    "deviceName": "LT-12345",
    "lastBackupDateTime": "2026-02-28T00:00:00Z",
    "refreshDateTime": "2026-03-30T00:00:00Z",
    "credentials": [
      {
        "accountName": "Administrator",
        "accountSid": "S-1-5-21-...",
        "backupDateTime": "2026-02-28T00:00:00Z",
        "password": "RecoveredPassword!"
      }
    ]
  },
  "bitlocker": [
    {
      "id": "7ea6d694-819d-4d95-85a8-50f4ad39b0cb",
      "deviceId": "4a5adf6d-17d2-4c74-9a08-9ca3a6e4ef1e",
      "createdDateTime": "2026-01-15T04:22:00Z",
      "volumeType": "operatingSystemVolume",
      "key": "111111-222222-333333-444444-555555-666666-777777-888888"
    }
  ]
}
```

## Payload and retention boundaries

Archive writes use compact JSON and count the serialized value as UTF-8 bytes.
The runbook refuses a payload above the conservative 24,000-byte writer limit
before acquiring a Key Vault token or issuing the secret `PUT`. The limit is
checked on bytes rather than PowerShell character count, so multibyte metadata
is accounted for correctly. The service's Key Vault secret value limit is
[25 KB](https://learn.microsoft.com/en-us/azure/key-vault/secrets/about-secrets);
the runbook keeps its existing lower ceiling unchanged.

The current behavior is refusal rather than chunking or truncation. All
archive evidence is assembled in one payload, and a refusal fails the archive
phase. The cleanup job does not issue the subsequent Entra device `DELETE`
when archive serialization or the Key Vault write fails. Review the archive-size
failure and correct source data before retrying; do not silently discard
required recovery evidence to fit the limit. An archive failure does not
authorize deletion. Recovery material belongs to the payload rather than
discovery tags; default discovery does not fetch that payload.

Key Vault soft-delete retention is a configurable 7–90-day recovery window,
with a default of 90 days, and purge protection remains enabled. This setting
controls recovery of deleted secrets; it is not an automatic archive expiry or
pruning policy. The solution does not silently delete or purge archived
records when that window elapses.

## Archive retrieval

Use `scripts\Get-ArchivedDevice.ps1` to find archived devices. Retrieval is
metadata-only by default, including when exactly one record matches; the
default path never reads the Key Vault secret value.

Examples:

```powershell
.\scripts\Get-ArchivedDevice.ps1 -DisplayName "PL-CL02"
.\scripts\Get-ArchivedDevice.ps1 -DeviceId "<device-guid>"
.\scripts\Get-ArchivedDevice.ps1 -SerialNumber "<serial-number>"
.\scripts\Get-ArchivedDevice.ps1 -IntuneManagedDeviceId "<managed-device-guid>"
.\scripts\Get-ArchivedDevice.ps1 -DefenderMachineId "<defender-machine-id>"
.\scripts\Get-ArchivedDevice.ps1 -PrimaryUserId "<entra-user-object-id>"
.\scripts\Get-ArchivedDevice.ps1 -PrimaryUserPrincipalName "user@example.com"
.\scripts\Get-ArchivedDevice.ps1 -ArchiveVersion "<32-hex-key-vault-version>" -ShowRecoveryMaterial
.\scripts\Get-ArchivedDevice.ps1 -EntraObjectId "<object-guid>" -ShowRecoveryMaterial
```

Add `-ShowRecoveryMaterial` only when you need the LAPS password or BitLocker
keys on screen. That switch is explicit recovery authorization for one
unambiguous record. If a search matches multiple records, the script fails
before reading any secret value; narrow the search first. Duplicate hostnames
and UPNs remain separate records and are never treated as a unique identity.

Ordinary discovery lists Key Vault metadata and performs zero secret-value reads. Valid structurally bound indexes appear as `IndexedExactVersion`; the current unversioned archive metadata remains visible as a `LegacyLatestAlias`. The alias is retained because a newer archive version can exist without an index after a failed second write. Malformed reserved-prefix secrets and legacy rows with a foreign vault authority, UserInfo, a nondefault port, nested tag values, or oversized scalars are quarantined. An explicit UPN selector reads only bounded index values. Indexed recovery revalidates the index schema, tags, hash, selected vault, archive name, and exact version before reading that exact archive version; every index and archive value response must return the requested public-vault identity and expected content type, and indexed recovery never falls back to latest.

Each archived secret now carries searchable metadata in both the JSON payload and Key Vault tags, including:

- Entra object ID and device ID
- Intune managed device ID and serial number when available
- Defender for Endpoint machine ID when available
- per-source last-seen timestamps
- `cleanupRunId` plus the effective heartbeat source and timestamp that drove the delete decision

The archive reader supports the recorded metadata keys and bounded selectors.
Primary-user lookup is optional and disabled by default. When enabled, the runbook resolves the exact candidate Entra device ID to a bounded Intune managed-device filter and reads that managed device's direct users relationship. It does not use the scalar managed-device UPN field and never chooses the first user from ambiguous data. States such as `None`, `Single`, `Multiple`, mapping ambiguity, overflow, conflict, and unavailability are retained without inventing an identity. Missing optional fields never match selectors.

## Recovery drill and SOP

Before you rely on this in production, run at least one full recovery drill with a non-critical device:

1. Trigger an archive-producing delete path in a safe test scope.
2. Locate the archived record with `scripts\Get-ArchivedDevice.ps1` by display name, device ID, serial number, or one of the source-specific IDs.
3. Confirm the summary view includes the identifiers and heartbeat evidence you expect before revealing recovery material.
4. Re-run with `-ShowRecoveryMaterial` only for the one record you intend to inspect.
5. Validate that the LAPS and BitLocker material is sufficient for your real operator process, then document where your team stores or records the recovery outcome.

This solution preserves **recovery material and cleanup evidence**, not a full device restore workflow. Re-enrollment, domain rejoin, and any downstream Intune or Defender cleanup still follow your existing operational process.
