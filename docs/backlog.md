# Backlog: nathanmcnulty/azd-device-cleanup

> Generated from `docs/backlog.json`. Edit the JSON source and regenerate this file.
> Standard: [azd agent backlog standard](https://github.com/nathanmcnulty/azd-reference/blob/main/standards/agent-backlogs.md). This link is review guidance, not a runtime dependency.

- **Schema version:** 1.0.0
- **Repository:** nathanmcnulty/azd-device-cleanup
- **Source revision:** `2f1631f220268e86d406e1b8846de4c296ec9b07`
- **Captured:** 2026-10-04
- **Items:** 12

## CLEAN-001: Reconcile this backlog with current source and active work

- **Kind:** discovery
- **Priority:** P1
- **Status:** done
- **Wave:** 0
- **Authorization:** local-only
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

Plans and implementation evidence are spread across files; the captured source can change while other tasks work.

**Scope:**

- docs/backlog.json
- docs/backlog.md
- Existing roadmap, execution status, open issues and pull requests &lpar;read-only&rpar;

**Acceptance:**

- Classify each candidate as implemented, still open, superseded or awaiting evidence; retain source links and reasons.
- Inspect dirty state, remotes, worktrees and local environment presence without reading secrets; avoid duplicate work with active owners.
- Resolve the actual offline validation commands and record exact current default-branch/working-tree provenance; do not copy historical live passes to newer code.

**Validation:**

- git status --short
- git remote -v
- git worktree list --porcelain
- Read the applicable instructions and validation workflow; read gh issue list and gh pr list for the named repository using nathanmcnulty. Do not create or modify issues/PRs.

**Dependencies:**

- _none_

**Components:**

- _none_

**Sources:**

- README.md
- TODO.md

**Evidence:**

- 2026-10-04 read-only reconciliation against current main 2f1631f220268e86d406e1b8846de4c296ec9b07&colon; inspected canonical dirty state, remotes, worktrees and environment-path presence without reading values; active/unowned branches remain untouched. Reviewed current issue/PR inventory, roadmap/TODO task sources and .github/workflows/validate.yml; kept live and optional-feature gates proposed.
- Invoke-Pester ./tests -CI&colon; 11/11 passed, including seven batch-cap/exact-override cases, Defender unavailable-data and inert preflight cases. Validation used offline fixtures only; no cloud, tenant, recipient or endpoint action was performed.

**Review and authorization note:**

Review CLEAN-001 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

## CLEAN-011: Keep preflight validation inert

- **Kind:** maintenance
- **Priority:** P1
- **Status:** done
- **Wave:** 0
- **Authorization:** local-only
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

Read-only reconciliation identified a resolved current-main defect missing from the captured task inventory.

**Scope:**

- scripts/preflight.ps1
- runbooks/DeviceCleanup.ps1
- tests/PreflightInertJob.Tests.ps1

**Acceptance:**

- Record exact merged source and regression coverage for the linked issue.
- Preserve live-service and deployment acceptance as separate gates.

**Validation:**

- Invoke-Pester ./tests -CI

**Dependencies:**

- _none_

**Components:**

- _none_

**Sources:**

- https&colon;//github.com/nathanmcnulty/azd-device-cleanup/issues/12
- https&colon;//github.com/nathanmcnulty/azd-device-cleanup/pull/13

**Evidence:**

- Merged PR &num;13 resolves issue &num;12 at 2f1631f220268e86d406e1b8846de4c296ec9b07; implementation is present in current main 2f1631f220268e86d406e1b8846de4c296ec9b07.
- Invoke-Pester ./tests -CI&colon; 11/11 passed, including seven batch-cap/exact-override cases, Defender unavailable-data and inert preflight cases. This is source/fixture evidence only; no live authentication, deployment, tenant mutation, device action or delivery is claimed.

**Review and authorization note:**

Review CLEAN-011 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

## CLEAN-009: Add a batch safety limit for the default device-disabling action

- **Kind:** maintenance
- **Priority:** P1
- **Status:** done
- **Wave:** 1
- **Authorization:** local-only
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

Open GitHub report captured 2026-10-03. Reproduce against the current source and reconcile active PRs before changing code; the issue remains the detailed trigger/evidence reference.

**Scope:**

- Paths and trigger cited in the linked issue
- Focused offline regression tests
- docs/

**Acceptance:**

- Classify the report as still reproducible, already fixed, superseded or requiring live evidence; record the exact current revision.
- For a reproducible defect, demonstrate the linked trigger with an offline regression and apply the smallest fix preserving tenant/target/ownership and failure semantics.
- For a feature, produce a bounded design with compatibility, optional permissions, acceptance and rollout gates before implementation; no live mutation or automatic issue closure.

**Validation:**

- Read the issue body and current source/PRs; capture the exact reproduction and existing registered offline validation command.
- Use deterministic fixtures for the described trigger and negative boundary; retain current-source results. Do not rerun production or tenant operations to reproduce it.

**Dependencies:**

- _none_

**Components:**

- _none_

**Sources:**

- https&colon;//github.com/nathanmcnulty/azd-device-cleanup/issues/9
- README.md

**Evidence:**

- Source implementation is present in current main 2f1631f220268e86d406e1b8846de4c296ec9b07; resolved revision 79a6da5b984998cdb77fc37af63f42a606d00d0e via merged https&colon;//github.com/nathanmcnulty/azd-device-cleanup/pull/11.
- Invoke-Pester ./tests -CI&colon; 11/11 passed, including seven batch-cap/exact-override cases, Defender unavailable-data and inert preflight cases. This completes only the bounded source/fixture acceptance; live-service, recovery, release and endpoint gates remain separate.

**Review and authorization note:**

Review CLEAN-009 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

## CLEAN-010: Defender inventory HTTP 404 bypasses the unavailable-data safety gate

- **Kind:** maintenance
- **Priority:** P1
- **Status:** done
- **Wave:** 1
- **Authorization:** local-only
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

Open GitHub report captured 2026-10-03. Reproduce against the current source and reconcile active PRs before changing code; the issue remains the detailed trigger/evidence reference.

**Scope:**

- Paths and trigger cited in the linked issue
- Focused offline regression tests
- docs/

**Acceptance:**

- Classify the report as still reproducible, already fixed, superseded or requiring live evidence; record the exact current revision.
- For a reproducible defect, demonstrate the linked trigger with an offline regression and apply the smallest fix preserving tenant/target/ownership and failure semantics.
- For a feature, produce a bounded design with compatibility, optional permissions, acceptance and rollout gates before implementation; no live mutation or automatic issue closure.

**Validation:**

- Read the issue body and current source/PRs; capture the exact reproduction and existing registered offline validation command.
- Use deterministic fixtures for the described trigger and negative boundary; retain current-source results. Do not rerun production or tenant operations to reproduce it.

**Dependencies:**

- _none_

**Components:**

- _none_

**Sources:**

- https&colon;//github.com/nathanmcnulty/azd-device-cleanup/issues/8
- README.md

**Evidence:**

- Verified merged PR https&colon;//github.com/nathanmcnulty/azd-device-cleanup/pull/10 at 21877b299e9dfdb5dbada68dab0273357deb4f7c on 2026-10-03. Independent quality task reports two behavioral Pester regressions; live recovery and deletion readiness remain separate.

**Review and authorization note:**

Review CLEAN-010 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

## CLEAN-012: Keep archive discovery metadata-only until explicit recovery

- **Kind:** maintenance
- **Priority:** P1
- **Status:** done
- **Wave:** 1
- **Authorization:** local-only
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

A single default lookup fetches the recovery JSON; optional missing tags also throw under strict mode. Discovery must remain safe before expanding the index.

**Scope:**

- scripts/Get-ArchivedDevice.ps1
- tests/ArchiveDiscovery.Tests.ps1
- docs/archive-and-recovery.md
- docs/backlog.json
- docs/backlog.md

**Acceptance:**

- Default single and multiple matches use metadata only; only explicit recovery for one exact match reads a value.
- Missing optional tags do not throw or falsely satisfy selectors; duplicate hostnames retain separate stable identities.
- Token acquisition and retrieval failures fail closed without exposing response bodies or recovery payloads.
- Metadata continuation requests remain on the selected vault collection route and refuse repeated pages before reading recovery values.

**Validation:**

- Parse all PowerShell files using the registered validate workflow command.
- Import-Module Pester -RequiredVersion 5.7.1; Invoke-Pester -Path ./tests -PassThru
- Parse all JSON files; az bicep build --file ./infra/main.bicep --stdout
- Run canonical Test-AzdBacklog.ps1 and Export-AzdBacklogMarkdown.ps1 -Check against the exact reviewed reference revision.

**Dependencies:**

- _none_

**Components:**

- _none_

**Sources:**

- scripts/Get-ArchivedDevice.ps1
- CLEAN-006

**Evidence:**

- 2026-10-07 implemented against exact current-main base 95ec50bfe96a6a704359a70dd97ea92008a23840&colon; every default match is metadata-only; explicit unique recovery alone fetches a value. Duplicate hostnames, absent optional tags, token/native failure sanitization and selected-vault collection-only pagination are covered by production-bound offline fixtures.
- Registered offline validation&colon; PowerShell parser and JSON parsing passed; Import-Module Pester -RequiredVersion 5.7.1; Invoke-Pester -Path ./tests -PassThru passed 26/26 with zero failed, skipped or not-run; az bicep build --file ./infra/main.bicep --stdout passed. No Azure authentication, resources, tenant/device actions or archive reads were used. Primary-user indexing &lpar;CLEAN-006&rpar; and human recovery acceptance &lpar;CLEAN-002&rpar; remain proposed.

**Review and authorization note:**

Review CLEAN-012 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

## CLEAN-002: Prove recovery before expanding disable or deletion scope

- **Kind:** verification
- **Priority:** P1
- **Status:** proposed
- **Wave:** 2
- **Authorization:** tenant-write
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

Default scheduling can disable devices; deletion remains gated by a real archive/recovery drill.

**Scope:**

- docs/
- scripts/preflight.ps1

**Acceptance:**

- Prepare inert pilot flags and exact exclusions before separately authorized deployment.
- Prove protected-device behavior, archive access and recovery using redacted evidence outside Git.
- Keep deletion off until the human drill succeeds; tenant cleanup remains exact-ID and separately authorized.

**Validation:**

- Use the offline commands in the registered validation workflow; record the exact commands, revision and results before implementation is complete.
- After separate authorization, retain redacted exact-target live evidence and cleanup results outside public Git. Do not execute live operations from this backlog alone.

**Dependencies:**

- _none_

**Components:**

- _none_

**Sources:**

- AGENTS.md
- README.md

**Evidence:**

- _none_

**Review and authorization note:**

Review CLEAN-002 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

## CLEAN-003: Design optional Intune cleanup after successful archive and Entra deletion

- **Kind:** discovery
- **Priority:** P2
- **Status:** proposed
- **Wave:** 3
- **Authorization:** local-only
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

Post-v1 proposes Intune removal; Graph success and archival are strict prerequisites.

**Scope:**

- scripts/
- infra/
- docs/
- azd-permissions.json

**Acceptance:**

- Removal plan identifies exact owned Intune object and archive receipt.
- Absent archive, failed Entra deletion or ambiguous match prevents action; implementation and live deletion are separate tasks.

**Validation:**

- Use the offline commands in the registered validation workflow; record the exact commands, revision and results before implementation is complete.

**Dependencies:**

- _none_

**Components:**

- _none_

**Sources:**

- TODO.md

**Evidence:**

- _none_

**Review and authorization note:**

Review CLEAN-003 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

## CLEAN-004: Design optional Defender cleanup after successful archive and Entra deletion

- **Kind:** discovery
- **Priority:** P2
- **Status:** proposed
- **Wave:** 3
- **Authorization:** local-only
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

Post-v1 proposes MDE removal with separate consent and API boundaries.

**Scope:**

- scripts/
- infra/
- docs/
- azd-permissions.json

**Acceptance:**

- Document supported exact-device API and least permission requirements from current primary sources.
- No inferred hostname match or implied destructive authorization; unsupported API is recorded as a gap.

**Validation:**

- Use the offline commands in the registered validation workflow; record the exact commands, revision and results before implementation is complete.

**Dependencies:**

- _none_

**Components:**

- _none_

**Sources:**

- TODO.md

**Evidence:**

- _none_

**Review and authorization note:**

Review CLEAN-004 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

## CLEAN-005: Add optional NotOnboarded and Unmanaged dynamic-group proposals

- **Kind:** feature
- **Priority:** P2
- **Status:** proposed
- **Wave:** 3
- **Authorization:** local-only
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

The existing stale groups do not express these additional cohorts.

**Scope:**

- scripts/
- infra/
- docs/
- azd-permissions.json

**Acceptance:**

- Preview membership and valid rule syntax from fixtures before any group creation.
- Disabled options require no extra Graph permissions and are explicitly excluded from default disabling.

**Validation:**

- Use the offline commands in the registered validation workflow; record the exact commands, revision and results before implementation is complete.

**Dependencies:**

- _none_

**Components:**

- _none_

**Sources:**

- TODO.md

**Evidence:**

- _none_

**Review and authorization note:**

Review CLEAN-005 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

## CLEAN-006: Expand archive discovery keys and tagging

- **Kind:** feature
- **Priority:** P2
- **Status:** proposed
- **Wave:** 3
- **Authorization:** local-only
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

Operators need serial, hostname and primary-user lookup without exposing recovery secrets.

**Scope:**

- scripts/
- infra/
- docs/
- azd-permissions.json

**Acceptance:**

- Index schema records stable identity plus bounded optional metadata.
- Tests distinguish duplicate hostnames and missing keys; logs never include LAPS or BitLocker recovery payloads.

**Validation:**

- Use the offline commands in the registered validation workflow; record the exact commands, revision and results before implementation is complete.

**Dependencies:**

- CLEAN-012

**Components:**

- _none_

**Sources:**

- TODO.md

**Evidence:**

- _none_

**Review and authorization note:**

Review CLEAN-006 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

## CLEAN-007: Add destination-specific Teams/email notification formatting

- **Kind:** feature
- **Priority:** P2
- **Status:** proposed
- **Wave:** 3
- **Authorization:** local-only
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

The existing Logic App route can offer clearer operator actions.

**Scope:**

- scripts/
- infra/
- docs/
- azd-permissions.json

**Acceptance:**

- Use a bounded notification envelope with per-destination formatting and secret-free links.
- Route failures remain independent; formatting tests do not imply message delivery.

**Validation:**

- Use the offline commands in the registered validation workflow; record the exact commands, revision and results before implementation is complete.

**Dependencies:**

- _none_

**Components:**

- notification-contracts

**Sources:**

- TODO.md

**Evidence:**

- _none_

**Review and authorization note:**

Review CLEAN-007 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

## CLEAN-008: Define archive payload-size and retention limits

- **Kind:** feature
- **Priority:** P2
- **Status:** proposed
- **Wave:** 3
- **Authorization:** local-only
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

Larger hunting payloads need a bounded archive policy.

**Scope:**

- scripts/
- infra/
- docs/
- azd-permissions.json

**Acceptance:**

- Document limits, redaction, chunking or refusal behavior and retention/recovery tradeoffs.
- Oversized payload fails without triggering deletion; fixtures verify exact evidence completeness.

**Validation:**

- Use the offline commands in the registered validation workflow; record the exact commands, revision and results before implementation is complete.

**Dependencies:**

- _none_

**Components:**

- _none_

**Sources:**

- TODO.md

**Evidence:**

- _none_

**Review and authorization note:**

Review CLEAN-008 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.
