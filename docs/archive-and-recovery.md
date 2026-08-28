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
    "managedDeviceId": "managed-device-id",
    "deviceName": "LT-12345",
    "extensionAttributeValue": "Fresh|2026-02-28T00:00:00.0000000Z"
  },
  "defenderForEndpoint": {
    "state": "Fresh",
    "lastSeen": "2026-02-28T00:00:00.0000000Z",
    "machineId": "mde-machine-id",
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

## Archive retrieval

Use `scripts\Get-ArchivedDevice.ps1` to find archived devices and inspect recovery material.

Examples:

```powershell
.\scripts\Get-ArchivedDevice.ps1 -DisplayName "PL-CL02"
.\scripts\Get-ArchivedDevice.ps1 -DeviceId "<device-guid>"
.\\scripts\\Get-ArchivedDevice.ps1 -SerialNumber "<serial-number>"
.\\scripts\\Get-ArchivedDevice.ps1 -IntuneManagedDeviceId "<managed-device-guid>"
.\\scripts\\Get-ArchivedDevice.ps1 -DefenderMachineId "<defender-machine-id>"
.\scripts\Get-ArchivedDevice.ps1 -EntraObjectId "<object-guid>" -ShowRecoveryMaterial
```

The script defaults to summary output so recovery data is not printed accidentally. Add `-ShowRecoveryMaterial` only when you need the LAPS password or BitLocker keys on screen.

Each archived secret now carries searchable metadata in both the JSON payload and Key Vault tags, including:

- Entra object ID and device ID
- Intune managed device ID and serial number when available
- Defender for Endpoint machine ID when available
- per-source last-seen timestamps
- `cleanupRunId` plus the effective heartbeat source and timestamp that drove the delete decision

## Recovery drill and SOP

Before you rely on this in production, run at least one full recovery drill with a non-critical device:

1. Trigger an archive-producing delete path in a safe test scope.
2. Locate the archived record with `scripts\Get-ArchivedDevice.ps1` by display name, device ID, serial number, or one of the source-specific IDs.
3. Confirm the summary view includes the identifiers and heartbeat evidence you expect before revealing recovery material.
4. Re-run with `-ShowRecoveryMaterial` only for the one record you intend to inspect.
5. Validate that the LAPS and BitLocker material is sufficient for your real operator process, then document where your team stores or records the recovery outcome.

This solution preserves **recovery material and cleanup evidence**, not a full device restore workflow. Re-enrollment, domain rejoin, and any downstream Intune or Defender cleanup still follow your existing operational process.
