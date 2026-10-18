# Defender machine cleanup API gap and lifecycle boundaries

## Status and bounded conclusion

This is a design and API-support assessment for the post-v1 Defender for
Endpoint cleanup proposal. It does not implement an endpoint action, create an
executor, change infrastructure or defaults, grant a permission, read tenant
data, or authorize a live operation.

As reviewed in Microsoft's current primary documentation on 2026-10-13, the
published Defender for Endpoint API catalog contains no supported route to
delete a machine record. The supported exact-machine lifecycle action that is
closest in name is **offboard**, but offboarding is not record deletion and is
not selected as an automatic fallback for this proposal. Unsupported
machine-record deletion remains an explicit implementation gap.

This conclusion is bounded to the cited published API catalog and product
documentation reviewed on that date. It does not claim that no internal,
private, future, or undocumented mechanism can exist.

## Published API and permission boundaries

| Purpose | Published route | Published application permission | Product boundary and result |
| --- | --- | --- | --- |
| Inventory discovery | `GET https://api.security.microsoft.com/api/machines` | `Machine.Read.All` | Documented for Defender for Endpoint Plan 1, Plan 2, and Defender for Business; returns retained machine entities and supports filtering on `id` and `aadDeviceId` |
| Exact machine read | `GET https://api.security.microsoft.com/api/machines/{id}` | `Machine.ReadWrite.All` | The current route page documents this broad permission for application access and returns 200 with a machine or 404; this design does not reinterpret inventory permission as proof that the exact route accepts it |
| Offboard endpoint sensor | `POST https://api.security.microsoft.com/api/machines/{id}/offboard` | `Machine.Offboard` | Documented for Defender for Endpoint Plan 1 and Plan 2 on listed operating systems; requires a comment and returns a `MachineAction` |
| Read action state | `GET https://api.security.microsoft.com/api/machineactions/{id}` | `Machine.ReadWrite.All` | Returns the specific action; terminal and nonterminal states must be evaluated explicitly |
| Delete machine record | No route in the reviewed supported API catalog | No documented permission | Unsupported gap; do not invent a DELETE route or permission |

These are the requirements published on each route page, not proof of tenant
consent, effective assignment, licensing, device-group access, or live service
acceptance. The exact-machine and action-read pages currently document the
broad `Machine.ReadWrite.All` application permission even though inventory
listing documents `Machine.Read.All`. That per-route difference is a
least-privilege qualification gap. Do not grant the broader permission or
claim it is required in a real tenant until a separately authorized
implementation is chosen and the supported permission model is revalidated.

The current solution's `Machine.Read.All` assignment supports heartbeat
inventory only. It does not authorize offboarding or any other machine action.

## Offboarding is not deletion

Offboarding stops the endpoint from sending new detection, vulnerability, and
security data to Defender for Endpoint. Microsoft documents that on Windows,
the offboard API only stops the sensor service and does not remove onboarding
information from the registry as an offboarding script does. Historical data
remains available for the configured retention period, and the device profile
can remain visible in device inventory for up to 180 days.

The offboard response is a machine-action acknowledgement. A future workflow
would have to preserve these as separate outcomes:

1. the API accepted an action and returned an exact `MachineAction.id`;
2. that action later reached `Succeeded`, rather than `Pending`, `InProgress`,
   `Failed`, `TimeOut`, or `Cancelled`;
3. the endpoint sensor actually stopped reporting;
4. the service later classified the device as inactive; and
5. the retained machine profile and historical security data remained subject
   to product retention.

No one outcome proves the others. In particular, `Succeeded` does not mean the
machine record was deleted. A hostname disappearing from a view is also not
proof of deletion.

## Identifier and provenance boundaries

The following values have different meanings and must never be substituted:

| Field | Meaning | Required provenance for any future action design |
| --- | --- | --- |
| `tenantId` | Tenant GUID from the Defender access-token `tid` claim and the selected deployed environment | Captured independently for discovery, archive, Entra deletion, exact-machine read, and action evidence; every value must match |
| `entraObjectId` | Microsoft Entra directory `device.id` used by the current Entra DELETE | Exact archived Entra device and deletion receipt |
| `deviceId` | Microsoft Entra device registration `device.deviceId` | Exact archive; compared only with Defender `machine.aadDeviceId` |
| `defenderMachineId` | Defender `machine.id`, generally a 40-character service identifier and the only identifier allowed in an exact machine-action path | Unique, contemporaneous Defender result plus exact-machine read and exact archive receipt |
| `cleanupRunId` | Correlates one cleanup decision | Identical archive, Entra deletion, and future plan evidence |
| Archive receipt | Complete versioned archive and companion-index identities | Exact versions, payload hashes, readback verification, and the same tenant/run/device/machine bindings |

Matching `machine.aadDeviceId` to the archived Entra `deviceId` establishes a
service relationship. It does not establish unique ownership or destructive
authorization. `computerDnsName`, display name, IP address, machine tags,
health, onboarding status, last-seen time, and a 40-character shape are
corroborating values only.

## Current-source evidence gaps

| Current source | What it establishes | Why it cannot authorize a machine action |
| --- | --- | --- |
| `Get-DefenderMachines` | Reads the retained Defender machine inventory | It is inventory, not an ownership or action decision |
| `New-DefenderMachineIndex` | Keys rows by `aadDeviceId` for heartbeat enrichment | It collapses multiple rows to the newest `lastSeen`, hiding ambiguity |
| Advanced-hunting `DeviceInfo` selection | Supplies supplemental latest heartbeat and optional machine ID | It also selects latest evidence and may omit a machine ID; hunting evidence is not exact action-target discovery |
| Archive payload/index v1.0 | Can retain an optional 40-hex `defenderMachineId`, Entra identifiers, archive version, and run ID | The machine ID is nullable, the index has no tenant ID, and the recorded ID can come from a collapsed latest-heartbeat selection |
| `New-DeviceCleanupActionRecord` and `archivedDeletedDevices` summary | Is added after archive and Entra delete return | It drops archive version and index identity and contains no Defender action or state receipt |
| `Get-ArchivedDevice.ps1` | Performs bounded archive discovery and exact-version human recovery | It is not an ownership resolver, approval mechanism, or Defender action client |

Consequently, existing archive/index/summary rows cannot be upgraded into a
trustworthy Defender action plan after the fact. Missing tenant, exact archive
version, unique-target, or service-response evidence must not be reconstructed
from a hostname, latest alias, latest heartbeat, later lookup, or action label.

## Refusal matrix

| Observation | Decision | Reason |
| --- | --- | --- |
| Requested outcome is machine-record deletion | Record unsupported gap; take no action | No supported deletion route or permission appears in the reviewed published catalog |
| Caller proposes offboard as an automatic substitute | Refuse | Offboarding changes endpoint reporting and does not delete the retained record |
| Archive/index is absent, unreadable, unversioned, schema-invalid, or hash-invalid | Refuse | No exact recovery receipt exists |
| `defenderMachineId` is null or appears only in hunting/latest-heartbeat evidence | Refuse | Exact action target is not proven |
| Two machine rows share the archived `deviceId` through `aadDeviceId` | Refuse | Newest `lastSeen` must not resolve ambiguity |
| Exact machine read returns a different `id` or `aadDeviceId` | Refuse | Target changed or evidence is foreign/stale |
| Tenant, Entra object, Entra device, machine, cleanup run, or archive version differs | Refuse | Evidence is mixed across identities or runs |
| Hostname, IP, tag, last-seen, health, or onboarding state is the only match | Refuse | Corroborating metadata is not a unique identifier |
| Required published permission, supported product/license, or exact-target authorization is absent or unknown | Refuse | Technical relationship does not supply authority |
| Offboard API returns a machine action that is pending or in progress | Record acknowledged/pending | Acceptance is not terminal completion |
| Machine action fails, times out, is cancelled, cannot be read, or refers to another machine | Record failed/unknown; do not report success | Terminal success and exact binding are absent |
| Machine action succeeds but telemetry or sensor state is unverified | Record action-succeeded/outcome-unproven | Control-plane action state is not endpoint proof |
| Machine becomes inactive while its profile remains | Expected retained-profile state | Inactivity is not record deletion |

## Scope of any future offboard proposal

Offboarding may be evaluated only in a new, explicitly authorized task. It must
not be silently folded into Entra cleanup. Before that task can propose an
action, it would need to:

1. revalidate the current published API, licensing, operating-system support,
   and per-route permissions;
2. collect every exact `aadDeviceId` match without the heartbeat index and
   refuse zero, duplicate, malformed, or conflicting matches;
3. direct-read the exact `defenderMachineId` and bind its returned `id` and
   `aadDeviceId` to tenant, Entra object/device IDs, cleanup run, and exact
   versioned archive/index readback;
4. obtain explicit authorization for that exact tenant, machine ID, operation,
   and plan digest using the organization's approval process;
5. re-read and revalidate the exact target immediately before the action;
6. persist the returned action ID and poll the exact action to a terminal state
   without treating acknowledgement as completion; and
7. report endpoint reporting/inactive/retention evidence separately, without
   claiming record deletion.

This design does not choose that future operation, define an approval system,
or justify `Machine.Offboard` or `Machine.ReadWrite.All` assignment. A live
qualification would also need a concrete disposable device, supported license,
expected endpoint behavior, rollback/re-onboarding procedure, evidence
retention, and cleanup authority.

## Microsoft references

Microsoft documentation reviewed on 2026-10-13:

- [Supported Defender for Endpoint APIs](https://learn.microsoft.com/en-us/defender-endpoint/api/exposed-apis-list) is the reviewed published API catalog and documents the `api.security.microsoft.com` service base URI.
- [List machines](https://learn.microsoft.com/en-us/defender-endpoint/api/get-machines) documents `Machine.Read.All`, supported products, retained inventory, and filters including `id` and `aadDeviceId`.
- [Get machine by ID](https://learn.microsoft.com/en-us/defender-endpoint/api/get-machine-by-id) documents the exact-machine route, 200/404 results, retention boundary, and its currently published application permission.
- [Offboard machine](https://learn.microsoft.com/en-us/defender-endpoint/api/offboard-machine-api) documents the exact-ID POST, `Machine.Offboard`, supported products/operating systems, required comment, machine-action response, rate limit, and Windows sensor-service limitation.
- [Get machineAction](https://learn.microsoft.com/en-us/defender-endpoint/api/get-machineaction-object) documents exact action readback and its currently published application permission.
- [machineAction resource](https://learn.microsoft.com/en-us/defender-endpoint/api/machineaction) documents action identity, exact `machineId`, timestamps, and terminal/nonterminal states.
- [Offboard devices](https://learn.microsoft.com/en-us/defender-endpoint/offboard-machines) documents reporting cessation, inactive timing, retained historical data, and device-profile visibility for up to 180 days.
