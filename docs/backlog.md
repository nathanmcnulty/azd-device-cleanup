# Backlog: nathanmcnulty/azd-device-cleanup

> Generated from `docs/backlog.json`. Edit the JSON source and regenerate this file.
> Standard: [azd agent backlog standard](https://github.com/nathanmcnulty/azd-reference/blob/main/standards/agent-backlogs.md). This link is review guidance, not a runtime dependency.

- **Schema version:** 1.0.0
- **Repository:** nathanmcnulty/azd-device-cleanup
- **Source revision:** `2f1631f220268e86d406e1b8846de4c296ec9b07`
- **Captured:** 2026-10-04
- **Items:** 13

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

## CLEAN-013: Fix secret request URI interpolation at archive and recovery boundaries

- **Kind:** maintenance
- **Priority:** P1
- **Status:** done
- **Wave:** 1
- **Authorization:** local-only
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

PowerShell parses SecretName?api as one variable in the writer and explicit recovery URI, failing under strict mode before a request.

**Scope:**

- runbooks/DeviceCleanup.ps1
- scripts/Get-ArchivedDevice.ps1
- tests/ArchivePayloadSafety.Tests.ps1
- tests/ArchiveDiscovery.Tests.ps1
- docs/backlog.json
- docs/backlog.md

**Acceptance:**

- Writer PUT and explicit recovery GET construct the exact selected vault secret URI with API version 7.4 under strict mode.
- Production helpers execute through mocked transport; fixtures do not inject missing URI variables or mock away the interpolation boundary.

**Validation:**

- Import-Module Pester -RequiredVersion 5.7.1; Invoke-Pester -Path ./tests -PassThru
- Parse PowerShell and JSON files and compile Bicep; validate backlog and generated Markdown.

**Dependencies:**

- CLEAN-012

**Components:**

- _none_

**Sources:**

- runbooks/DeviceCleanup.ps1
- scripts/Get-ArchivedDevice.ps1

**Evidence:**

- 2026-10-07 reproduced the prior helper failure on exact base f21713c7e58b897db2124a49060a15c5a6f13f54 before transport&colon; SecretName?api was parsed as one undefined variable. Braced SecretName in both existing request expressions. Exact PUT and GET URI assertions exercise production helpers through mocked transport under strict mode; no test injects the missing variable.
- Full Pester 5.7.1 passed 32/32, zero failed/skipped/not-run; parser, JSON, Bicep and canonical backlog/generated view checks passed. Live archive creation and real recovery acceptance remain separate.

**Review and authorization note:**

Review CLEAN-013 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

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
- **Status:** done
- **Wave:** 3
- **Authorization:** local-only
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

Operators need serial, hostname and primary-user lookup without exposing recovery secrets.

**Scope:**

- runbooks/DeviceCleanup.ps1
- scripts/Get-ArchivedDevice.ps1
- scripts/postprovision.ps1
- scripts/preflight.ps1
- infra/
- tests/
- schemas/
- docs/
- azd-permissions.json

**Acceptance:**

- Index schema records stable identity plus bounded optional metadata.
- Tests distinguish duplicate hostnames and missing keys; logs never include LAPS or BitLocker recovery payloads.

**Validation:**

- Invoke-Pester ./tests with Pester 5.7.1&colon; 81/81 on PowerShell 7.6.6.
- Invoke-Pester ./tests/ArchiveDiscovery.Tests.ps1, ./tests/ArchiveIndexDiscovery.Tests.ps1, ./tests/PermissionParity.Tests.ps1 with Pester 5.7.1&colon; 44/44 on PowerShell 7.2.24.
- Parse repository PowerShell and JSON; Test-Json azd-permissions.json against canonical permission-requirements.schema.json; verify each code evidence SHA-256 over canonical UTF-8/LF source.
- az bicep build --file ./infra/main.bicep --stdout; verify semantic equality with infra/main.json; Test-AzdBacklog.ps1; Export-AzdBacklogMarkdown.ps1 -Check; git diff --check.
- 2026-10-10 JSON string repair&colon; Invoke-Pester ./tests with Pester 5.7.1 passed 86/86 on PowerShell 7.6.6; native synthetic HTTP proof distinguished DateTime conversion from preserved wire strings.

**Dependencies:**

- CLEAN-012

**Components:**

- _none_

**Sources:**

- TODO.md

**Evidence:**

- 2026-10-07 source implementation from base c7b3e6eaa2a76722fc45c61b95084c41f93bab24&colon; each successful new recovery archive receives a separate closed, bounded, version-bound metadata index before Entra deletion. Default discovery remains metadata-only; explicit UPN lookup reads bounded index values, and explicit recovery validates the exact indexed archive version. Legacy latest aliases remain visible when a newer archive has no index. Optional relationship-based primary-user collection defaults false and never changes eligibility or heartbeat selection.
- Validation&colon; PowerShell 7.6.6 / Pester 5.7.1 full suite 81/81 passed with zero failed, skipped or not-run; reader and permission suites on PowerShell 7.2.24 passed 44/44. Root independently replayed the full suite and parser, JSON, canonical permission schema and evidence hashes, Bicep, backlog rendering and diff checks. Independent exact 23-file review passed with a separate 49/49 focused replay; all ten earlier review findings were repaired. Failed r1 source and evidence were preserved.
- Qualification remains source/offline only. The selected lab managedDevices read returned HTTP 403 before the direct users relationship was reached; cause remains unknown and no new permission was granted. No deployment, device action, real recovery read or human recovery drill was performed. Production deployment, effective grants, live relationship reads and recovery acceptance remain separate qualification work.
- 2026-10-10 synthetic Key Vault lab contract failed when all four discovery/recovery lookups returned no match; its terminal receipt reports completed role, vault, tombstone and resource-group cleanup. A separate synthetic loopback HTTP proof on PowerShell 7.6.6 confirmed native Invoke-RestMethod converts ISO timestamp tags to DateTime, causing both strict legacy and index validators to refuse valid metadata. The reader now parses raw HTTP JSON with DateKind String and preserves timestamp-shaped recovery strings; 86/86 offline tests passed. This repairs the confirmed source defect but does not establish live service acceptance or a human recovery drill.

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

- 2026-10-10 bounded source implementation on base 08f5efa647f94d1414447973b6ee036a130c68b1&colon; version 1.0 scalar notification envelope, separate Adaptive Card and email formatting, three independently configured sibling HTTPS routes, secure parameters and HTTP input/output history protection. Existing generic consumers require version 1.0 migration; no new recipients, connector credentials, Graph grants or lifecycle defaults were introduced.
- Offline PowerShell 7.6.6/Pester 5.7.1 full suite passed 100/100, zero failed/skipped/not-run. Fourteen new production-bound producer/dispatcher/compiled-template cases test schema and 16KiB projection, hostile identities/counts, suppressed routes, sanitized callback retries, exact schema-variable resolution, sibling route/default/history protections and immutable vendor hashes. Registered parser/JSON/Bicep0.46.1 gates, generated ARM byte parity and canonical permission/backlog checks passed.
- notification-contracts 1.0.0 schemas are vendored at immutable Reference 6dc5841a3156b904b89f0f4ff8d97207a26ec15a; exact raw hashes are recorded in azd-components.lock.json. Generic envelope schema use is proven locally; workflow action-status outputs do not implement canonical delivery-result receipts. Request trigger explicitly enables schema validation; native draft2020-12/$defs/$ref/const/pattern acceptance/enforcement and child outputs for successful/failed/skipped routes remain unproven.
- CLEAN-007 remains proposed pending independent code review and native Workflow Definition Language proof. HTTP acknowledgements, static sibling runAfter inspection and formatting/schema tests do not prove recipient delivery, exactly-once processing, or runtime failure independence. No auth, deployment, callbacks, tenant/device writes, archive access or resources were used.
- 2026-10-11 independently reviewed native Workflow Validate comparison on exact source 03ae762107e191955227a21b4648d6d252428b99&colon; original definition returned HTTP400 with a pattern-constraint rejection diagnostic; a private copy removing only eventId and namespacedName patterns returned HTTP200, with EnableSchemaValidation retained in both. Receipt SHA256 2FFE0CA8790773FA3606B7B342B25E409868072FA9F2F422B9DDDB9336F2F1F3. Both virtual workflow IDs were404 before/after; existing group metadata and default subscription were unchanged, with no resource mutations, grants, callbacks or recipient messages. This narrows provider incompatibility but proves no deployment, runtime enforcement, routing or delivery. Production constraints remain unchanged; source review and100 offline tests passed, while a provider-compatible adapter with equivalent canonical enforcement and native proof remain outstanding.
- 2026-10-11 provider adapter on reviewed draft base b2d23b71761f9ba2a35bec850b6d66c91ae4a0b8&colon; solution-owned structural projection inlines five canonical references and const-to-enum, omits annotation-only formats from provider assertions, and executes fail-closed pre-routing C0/namespace checks preserving single-final-LF and original full-string length semantics. Canonical schema/lock, runbook functions, defaults, permission requirements and independent destination payloads remain unchanged. Fixed202 acceptance precedes independent routes; guard rejection uses400 with a validation-only receiver run; validation-action failure uses503 with no route dispatch. Trigger/temporary histories are protected. No new runtime host or components. Native structural enforcement, Unicode/codepoint boundaries, annotation acceptance, expression/response/child-status behavior, runtime independence and delivery remain unproven; CLEAN-007 stays proposed.
- Adapter offline validation&colon; PowerShell7.6.6/Pester5.7.1 full registered suite291/291 passed with zero failures/skipped/not-run. Actual compiled-expression differential cases cover both ID fields all32 C0 characters embedded/final, single-LF/CRLF/two-LF/empty, ASCII and astral full-string length boundaries, namespace grammar, annotation-only bad-format strings, closed objects/types and open nested data. Tests additionally compare complete canonical structural projection, guarded/independent route dependencies, protected history and negative expression mutations. Parser18files/JSON10files, ScriptAnalyzer zero Error findings &lpar;143 warnings retained&rpar;, pinnedBicep0.46.1 compile/checked-in ARM byte parity and canonical permission/backlog schema/view passed. This is local model/static evidence, not native service enforcement or delivery; native gates and proposed status remain.
- 2026-10-11 exact published adapter bf66961ebbbb525839fa5ab04bdde31f45d942cc definition validation returned HTTP400 &lpar;sanitized receipt SHA25608DFC1451935DEC3B652B959E959635B3E7F4AA812F5C563DE0F19875B53A3C6&rpar;; unknown provider code and generic pattern mention did not prove a rejection cause. Exact virtual workflow404 before/after, existing group/default context unchanged. Primary Microsoft documentation identifies Scope secure inputs/outputs and Compose secure outputs as unsupported; removed Scope settings and retained Compose secure inputs &lpar;documented implicit output hiding&rpar;, preserving every expression/schema/dependency and Query/HTTP/trigger protection. Native definition/deployment/runtime/history/route/delivery proof remains pending. Repair offline validation&colon; PowerShell7.6.6/Pester5.7.1 295/295 with0failed/skipped/not-run, parser/analyzer-error/JSON/canonical-schema/view/Bicep0.46.1 ARM parity. Independent repair review pending; CLEAN-007 stays proposed. No auth/cloud/source lifecycle or permission changes.

**Review and authorization note:**

Review CLEAN-007 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.

## CLEAN-008: Define archive payload-size and retention limits

- **Kind:** feature
- **Priority:** P2
- **Status:** done
- **Wave:** 3
- **Authorization:** local-only
- **Blocker:** _none_
- **Claim:** _none_

**Problem:**

Larger hunting payloads need a bounded archive policy.

**Scope:**

- tests/ArchivePayloadSafety.Tests.ps1
- docs/archive-and-recovery.md
- docs/backlog.json
- docs/backlog.md
- runbooks/DeviceCleanup.ps1

**Acceptance:**

- Document the existing 24,000-byte compact UTF-8 payload ceiling, unchanged complete-payload refusal without chunking, and retention/recovery tradeoffs.
- Oversized complete archive fails before token acquisition or PUT and prevents Entra deletion; exact-byte and multibyte fixtures prove this boundary.
- Keep existing Key Vault soft-delete retention and purge protection unchanged; distinguish deleted-secret recovery windows from active-archive expiration.

**Validation:**

- Import-Module Pester -RequiredVersion 5.7.1; Invoke-Pester -Path ./tests -PassThru
- Parse PowerShell and JSON files; az bicep build --file ./infra/main.bicep --stdout
- Validate canonical backlog JSON and generated Markdown using the reviewed Reference tools.

**Dependencies:**

- _none_

**Components:**

- _none_

**Sources:**

- TODO.md

**Evidence:**

- 2026-10-07 verified unchanged existing archive size/refusal and retention configuration on base f21713c7e58b897db2124a49060a15c5a6f13f54. Strict-mode fixtures prove exact 24,000 compact UTF-8 bytes accepted, 24,001 refused before token/PUT, multibyte counting, real Save-DeviceArchive and cleanup-job refusal with Archive failure and zero Entra DELETE calls. No truncation, chunking or retention policy was introduced.
- Registered offline parser/JSON/Bicep gates passed; Pester 5.7.1 Invoke-Pester -Path ./tests -PassThru passed 32/32, zero failed/skipped/not-run. Documented current 7-90-day soft-delete recovery window, default 90, purge protection and no automatic active-archive expiry. Source/fixture proof only; no authentication, archive reads, device actions or resources.

**Review and authorization note:**

Review CLEAN-008 against the current repository state. Its status or authorization class is not eligible for an actionable generated handoff. Do not claim or execute it without explicit selection, satisfied dependencies, and every required authorization. Never interpret this generated view as approval.
