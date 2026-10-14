# Optional device dynamic-group proposals

`scripts/New-DeviceDynamicGroupProposal.ps1` produces an offline proposal from
administrator-provided JSON fixtures. It does not query Microsoft Graph,
Defender for Endpoint, or Intune. It does not write a device attribute, create
or update a group, grant a permission, or feed the cleanup lifecycle.

The proposal covers two narrowly defined cohorts:

| Proposal | Canonical predicate | Positive source evidence |
| --- | --- | --- |
| Unmanaged | <code>device.extensionAttributeN -eq "Unmanaged&#124;none"</code> | A complete, fresh Intune managed-device fixture contains no record whose `azureADDeviceId` exactly equals the Entra device `deviceId`. |
| NotOnboarded | `device.extensionAttributeN -eq "CanBeOnboarded"` | A complete, fresh Defender machine fixture contains exactly one record whose `aadDeviceId` exactly equals the Entra device `deviceId`, whose machine ID is valid, and whose `onboardingStatus` is exactly `CanBeOnboarded`. |

Microsoft documents `extensionAttribute1` through `extensionAttribute15` as
supported device dynamic-membership properties. Microsoft also documents
`CanBeOnboarded` as a Defender machine onboarding status. The Defender machines
collection contains machines that have communicated with the service and is
limited by configured retention. For that reason, an absent machine or absent
advanced-hunting row is unknown, not proof that a device is not onboarded.

- [Dynamic membership rules for devices](https://learn.microsoft.com/entra/identity/users/groups-dynamic-membership#rules-for-devices)
- [Defender machine resource](https://learn.microsoft.com/defender-endpoint/api/machine)
- [Defender machines collection and retention](https://learn.microsoft.com/defender-endpoint/api/get-machines)

## Run an offline preview

Preview mode requires the administrator to supply the tenant, attribute slot,
attribute owner label, evidence hash, maximum evidence age, and reference time.
The tool does not select those policy values.

```powershell
pwsh -NoProfile -File .\scripts\New-DeviceDynamicGroupProposal.ps1 `
  -Mode Preview `
  -Kind Unmanaged `
  -FixturePath .\tests\fixtures\device-group-proposal-intune.json `
  -TenantId 11111111-1111-1111-1111-111111111111 `
  -AttributeNumber 14 `
  -AttributeOwner fixture-admin/intune-state `
  -EvidenceSha256 aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa `
  -MaximumEvidenceAgeHours 24 `
  -ReferenceTimeUtc 2026-10-13T13:00:00Z
```

Without `-Mode Preview`, the command returns a disabled, inert result before it
tries to resolve a fixture. Disabled mode has an empty permission list and no
attribute, group, or lifecycle action.

The fixture contract is deliberately small:

- `schemaVersion` is `1.0` and `kind` is
  `device-dynamic-group-proposal-fixture`.
- `tenantId` must equal the administrator input.
- `source.type` is `IntuneManagedDevices` or `DefenderMachines` for the selected
  proposal.
- `source.collectionState` must be `Complete`. `Unavailable`, `NoData`, and
  incomplete or unknown values refuse all positive classifications.
- `source.collectedAtUtc` must fall within the administrator-selected maximum
  age at the explicit UTC reference time.
- `source.sha256` must equal the administrator input.
- Each device has a unique, valid Entra `entraObjectId` and `deviceId` pair.
- An optional `existingAttribute` records its slot, value, declared owner,
  observation time, and source hash.

The tenant, owner, hash, and timestamps are declarations in a provided fixture.
Matching them proves only that the fixture is internally consistent with the
command inputs. It does not authenticate a service capture, establish tenant
ownership, grant authorization, or prove that any attribute was written.
The machine-readable fixture shape is
[`schemas/device-dynamic-group-proposal-fixture.schema.json`](../schemas/device-dynamic-group-proposal-fixture.schema.json).

## Interpret the result

The report labels its trust source `provided-fixture` and keeps two previews:

- `prospective` classifies what a future publisher could write from the source
  fixture.
- `existingAttribute` evaluates only the fixture's declared current attribute.

An included prospective device with a missing, stale, differently owned, or
different current attribute remains `Unknown` in the existing-attribute
preview. The tool never converts a prospective result into a claim of current
group membership.

Both previews use `Included`, `Excluded`, or `Unknown`. Tenant mismatch,
unavailable or incomplete collection, `NoData`, stale or future evidence,
source-hash mismatch, missing or duplicate Entra identifiers, malformed or
ambiguous source records, and unrecognized Defender onboarding states all
produce `Unknown`. For NotOnboarded, zero source matches also produces
`Unknown` because service visibility and retention prevent an absence claim.
Results contain normalized identifiers and bounded reason codes rather than raw
provider responses.

The generated rule is parsed back through an allowlist that accepts only the
two canonical equality predicates. This is offline syntax validation for the
generated proposal. Microsoft Entra service validation is separate, requires
administrator access and service state, and can return `Unknown` for rule or
network failures. See [Validate dynamic membership rules](https://learn.microsoft.com/entra/identity/users/groups-dynamic-rule-validation).

## Production gaps

Every preview reports `publisherPresent=false`, `groupCreationReady=false`, and
`groupCreationReason=ProposalOnly`. Creating a real NotOnboarded group first
requires a separately authorized publisher that owns the administrator-selected
slot, preserves exact tenant and device bindings, and defines how it clears or
expires prior values after source failures or state changes. No such publisher
is implemented here.

The offline maximum age rejects stale fixture evidence only. A Microsoft Entra
dynamic-membership rule does not enforce that fixture age or expire an existing
attribute value. A future implementation must resolve that behavior and then
perform Microsoft Entra service-side rule validation before any group creation.
Group creation permissions, tenant licensing, attribute writes, service reads,
and group creation remain separate authorization and implementation work.

Proposal membership is informational. It is not an exclusion, disabling, or
deletion input. The cleanup runbook continues to select lifecycle actions only
from its existing effective-heartbeat and account-state logic.
