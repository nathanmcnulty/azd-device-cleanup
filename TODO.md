# Post-v1 follow-up

> Task tracking moved to [the standardized backlog](docs/backlog.md) and its
> [canonical JSON](docs/backlog.json). All six follow-ups below are represented
> there. Keep this list as historical context; update status in the backlog.

- [ ] Add optional Intune cleanup after successful archive + Entra delete.
- [ ] Add optional Defender for Endpoint cleanup after successful archive + Entra delete.
- [ ] Add more dynamic groups, such as `NotOnboarded` and `Unmanaged`, in addition to the stale groups.
- [ ] Review additional bounded archive lookup keys after operational recovery evidence identifies a concrete need.
- [ ] Add richer Teams/email formatting and destination-specific routing on top of the Logic App notification workflow.
- [ ] Revisit archive payload size and retention guidance if advanced-hunting metadata grows in larger tenants.
