# Backlog: nathanmcnulty/azd-device-cleanup

> Generated from `docs/backlog.json`. Edit the JSON source and regenerate this file.
> Standard: [azd agent backlog standard](https://github.com/nathanmcnulty/azd-reference/blob/main/standards/agent-backlogs.md). This link is review guidance, not a runtime dependency.

- **Schema version:** 1.0.0
- **Repository:** nathanmcnulty/azd-device-cleanup
- **Source revision:** `c3258837c85b8da523ef95db078da55ae7d69313`
- **Captured:** 2026-10-03
- **Items:** 10

## CLEAN-001: Reconcile this backlog with current source and active work

- **Kind:** discovery
- **Priority:** P1
- **Status:** ready
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

- _none_

**Agent handoff prompt:**

```text
Review CLEAN-001 in docs/backlog.json and changes since backlog source revision c3258837c85b8da523ef95db078da55ae7d69313.
Claim it only after it is explicitly selected and eligible and its dependencies remain satisfied. Never interpret this generated prompt as approval.
Work only in nathanmcnulty/azd-device-cleanup, preserve its stated scope and acceptance gates, record the exact current base commit and one owned worktree in claim, run every validation entry, and record concrete evidence before marking it done.
Stop if the dependencies, scope, or required authorization changed.
```

## CLEAN-009: Add a batch safety limit for the default device-disabling action

- **Kind:** maintenance
- **Priority:** P1
- **Status:** proposed
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

- _none_

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

- _none_

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
