# Optional notification routes

The cleanup runbook sends a bounded version 1.0 notification envelope to the existing Logic App. The producer selects scalar target/run metadata, terminal status, severity and eleven bounded counts. It excludes per-device results, display names, archive pointers, recovery material, raw failure text and callback addresses. The compact UTF-8 payload is limited to 16 KiB. Its review link uses the fixed Azure portal origin and selected Automation resource path, with no bearer query or recovery link.

Three optional routes run as independent sibling actions:

| Secure Bicep parameter | Payload | Configuration owner |
| --- | --- | --- |
| `logicAppNotificationWebhookUrl` | Entire version 1.0 envelope | Existing downstream receiver; migrate receivers that expected the previous raw summary. |
| `logicAppTeamsWebhookUrl` | Adaptive Card message in `data.teams` | Existing Teams Workflow receiver and its destination. |
| `logicAppEmailWebhookUrl` | `subject`, `text`, `html` in `data.email` | Existing email workflow; its owner selects recipients and sending credentials. |

All three URLs default empty. Existing notification enablement/class defaults, device thresholds and disabling/deletion defaults are unchanged. This feature creates no recipients, connector credentials, Graph grants or sending permissions. Populate only selected HTTPS routes through approved secret-handling deployment input; never commit real URLs. Setting `logicAppNotificationsEnabled=false` removes the workflow and suppresses runbook notifications. Disabling one route does not require extra scopes or prevent the other routes from executing.

The workflow uses secure URL parameters and hides HTTP action inputs and outputs. Each enabled route independently posts its payload; a failure in one route has no dependency on another. Workflow outputs contain only each child HTTP action status, defaulting to `Skipped`; they are diagnostics, not canonical delivery receipts. The producer's callback validates HTTPS, refuses credentials/fragments and redirects, sets a timeout, and retries at most three times. Callback errors are sanitized before notification logging.

An HTTP acknowledgement means the request was accepted by that endpoint; it proves neither recipient-visible delivery nor exactly-once processing. Retries may duplicate an accepted request when the response is lost. Receivers should deduplicate the stable `eventId` (`cleanup.<run-guid>`) if their workflow requires it. Review the selected Logic App and receiver run history separately; this feature does not poll destinations or certify delivery. Teams rendering, email sending, Workflow Definition Language expression execution and cross-route runtime failures still require separate authorized native validation.

The local `notification-contracts` 1.0.0 schemas are vendored from immutable reference revision `6dc5841a3156b904b89f0f4ff8d97207a26ec15a`, recorded with exact file hashes in `azd-components.lock.json`. Deployment has no runtime reference dependency. The actual produced envelope is schema-tested; the generic delivery-result schema is retained for future adapters, but the workflow's action-status outputs do not claim to implement it. The generic trigger schema does not replace the trusted runbook producer's bounded projection; owners of the secret callback must not submit arbitrary untrusted formatting payloads.

The Request trigger explicitly enables structural schema validation and accepts POST. The solution-owned `infra/notification-schema.json` inlines the canonical schema's five local references and expresses `schemaVersion` as a one-value enum. Unsupported patterns are enforced by `Check_patterns` actions in `infra/notification-actions.json` before any route can execute. Date/UUID `format` keywords are annotations under the current canonical default dialect and local evaluator, so they are not provider assertions. The canonical files and immutable lock remain unchanged. Tests account for every structural assertion and compare actual compiled pattern expressions with the canonical validator; they do not prove native schema or Workflow Definition Language behavior.

The pattern actions retain the canonical evaluator's single-final-LF allowance for both IDs and namespace strings. They remove at most one final LF from temporary predicate strings only, require nonempty C0-free content for IDs, and check the exact ASCII namespace grammar. Original input strings remain unchanged for routing and full-string length validation. Embedded LF, CRLF, two final LFs, LF-only IDs, and other C0 controls are rejected. Literal percent sequences, spaces, DEL and Unicode in IDs retain canonical acceptance. Native Unicode/codepoint length semantics still need explicit boundary qualification; the adapter must not silently narrow valid Unicode if provider lengths differ.

All route actions depend on a successful common validation stage and fixed HTTP202 acceptance response; the three destination results remain independent. A pattern rejection returns fixed HTTP400 after creating a validation-only receiver run, with zero destination actions permitted. Structural trigger failures can reject before activation, subject to native proof. A validation-action failure or timeout takes a separate fixed HTTP503 response and cannot dispatch. The Request trigger and Query/HTTP actions explicitly configure secure inputs and outputs. The temporary Pattern_inputs Compose configures secure inputs only, which Microsoft documents as also hiding its outputs; Scope carries no secure-data settings because that action type supports neither setting. Native protected-history readback remains mandatory. [Microsoft's secure-data guide](https://learn.microsoft.com/en-us/azure/logic-apps/logic-apps-securing-a-logic-app) documents these trigger/action protections. Fixed statuses contain no provider errors, raw bodies, destinations or tokens.

The adapter cannot claim universal HTTP400 plus zero receiver runs: action-based rejection necessarily creates a run. Native proof must separately establish structural rejection, pattern rejection, validation failure, format-annotation acceptance, Unicode/full-string boundaries, actual response timing, route independence, body projections, child statuses and zero sink work on rejection. The test-only expression model evaluates exact compiled primitives with ordinal string operations and UTF16 indexing; it is explicitly not the native service engine. No new runtime host, Integration Account, validator API, permissions or recipients are introduced.

Native definition validation on 2026-10-11 compared exact source revision `03ae762107e191955227a21b4648d6d252428b99` with a private diagnostic copy using the location-scoped Workflow Validate API. Azure returned HTTP 400 for the original definition with a pattern-constraint rejection diagnostic, and HTTP 200 for a copy removing only the `eventId` and `namespacedName` pattern constraints. Both copies retained `EnableSchemaValidation`. This identifies a provider incompatibility with the pattern-containing definition; it does not prove which pattern alone causes rejection or establish support for the remaining schema keywords. The diagnostic copy is not an accepted production implementation. Preserve equivalent canonical contract enforcement before changing the deployed schema.

The independently reviewed diagnostic used an existing lab resource group and created no resources, grants, callbacks or recipient messages. Both virtual workflow IDs returned HTTP 404 before and after; resource-group metadata and the default subscription remained unchanged. Its sanitized receipt SHA-256 is `2FFE0CA8790773FA3606B7B342B25E409868072FA9F2F422B9DDDB9336F2F1F3`. Definition validation does not establish deployment, runtime request rejection, expression execution, route independence or delivery. This historical diagnostic predates the provider adapter; the current adapter remains a draft pending native enforcement proof.

Offline tests invoke the real producer and dispatcher with secret canaries, inspect the freshly compiled production workflow (resolving its constant ARM variables), and verify sibling routing, secure parameters/action histories, defaults and immutable schema hashes. The adapter adds canonical differential cases, complete projection mapping, fail-closed dependencies and expression-mutation checks. Earlier independent source review and 100-test evidence remain historical. The earlier full registered suite passed 291/291 tests on PowerShell 7.6.6/Pester 5.7.1, with parser/JSON/canonical-schema/view checks and Bicep 0.46.1 ARM byte parity. CLEAN-007 remains proposed pending independent adapter review and native workflow proof. These tests do not prove live service acceptance, rendering or message delivery.


The exact published adapter revision `bf66961ebbbb525839fa5ab04bdde31f45d942cc` also returned HTTP400 from Workflow Validate (receipt SHA256 `08DFC1451935DEC3B652B959E959635B3E7F4AA812F5C563DE0F19875B53A3C6`). The closed diagnostic recorded an unknown provider code and a generic pattern mention; it did not establish the rejection cause. The sole virtual workflow returned404 before/after, with existing-group metadata and default context unchanged. Subsequent primary-document review identified unsupported secure-data settings on Scope and Compose. This compatibility repair removes Scope settings and uses Compose secure inputs alone while preserving Query/HTTP/trigger protections and every expression, schema assertion and dispatch dependency. It addresses a documented configuration incompatibility, not a proven HTTP400 cause; native definition/deployment and protected-history acceptance are still pending. The amended registered suite passes295/295 on PowerShell7.6.6, with no failed/skipped/not-run tests and fresh Bicep0.46.1 ARM parity; independent review of this repair is pending. No native calls were made during this repair.

## Repaired definition acceptance

The exact repaired definition from `49f0c712bab7ad72e78593addaee4df4b5e9a8f6`
passed Azure Workflow Validate with HTTP 200. Its definition SHA-256 is
`8CC937243A3D1753ADA4AC927B5C3515CAD5BFC8C3C11A36B7B102373D8FCD1C`.
The independently reviewed diagnostic used no resource mutations; the exact
virtual workflow was absent before and after, and the group/default context
was unchanged. Earlier HTTP 400 receipts remain preserved; their specific
cause is unproven.

This is definition acceptance. Native schema and pattern enforcement, Unicode
code-point boundaries, protected history, route status/output expressions,
sibling failure independence, and recipient-visible delivery still need proof.
CLEAN-007 remains proposed.

## Synthetic setup attempt and cleanup

The independently reviewed synthetic attempt on 2026-10-11 created three owned
workflows from source `49f0c712bab7ad72e78593addaee4df4b5e9a8f6`. All three
received successful PUT/version acknowledgments and matching public GET checks,
including the source definition's empty secure defaults. This confirms the
tested setup projection, not readback of hidden route values.

Execution stopped with `EndpointRejected` at `CreateExactCandidate` before any
runtime case or candidate invocation. The cause remains unproven. The receipt
records zero cases, candidate invocations and receiver runs; it supplies no
native schema/pattern/Unicode enforcement, route status/output, sibling failure
independence, projection, protected-history or recipient-delivery evidence.

The reviewed cleanup recorded one acknowledged exact owned-group DELETE and
four exact final HTTP404 observations, with the default context unchanged.
Twenty-one inherited role assignments were counted and untouched; zero owned
or outside assignments were recorded. These are the bound harness's observations,
not an independent fresh API read or a broader resource-absence claim.

Receipt SHA-256: `39F96EE62B1D2E4EC0D1CAE1A1777330FFC2EC8380362EFA5B679466DE3DA471`.
Independent terminal review SHA-256:
`F0CB4BD8008A37CB810BCEA89D87A98373CFC809AD1BF851AE92462C80B01006`.
Prior failed artifacts remain preserved. CLEAN-007 remains proposed with its
original acceptance gates and the runtime/delivery proof still outstanding.

## Partial runtime observation

A second independently reviewed attempt on 2026-10-11 used the unchanged
source `49f0c712bab7ad72e78593addaee4df4b5e9a8f6`. One RouteA candidate
callback returned HTTP202 and produced a native-version-bound run with
`observedAccepted=true`. Exact scoped action history recorded
`Post_notification=Failed`, `Post_teams=Succeeded` and `Post_email=Skipped`.

The attempt then stopped with `UnclassifiedRuntimeFailure` before output and
projection qualification. Its cause remains unproven; the reused
`CandidateCallback` stage does not identify the failing operation. RouteA is
incomplete and nineteen cases did not run. Child/output status and
receiver-attempt evidence arrays are empty. `receiverRuns=0` is a stale
pre-case counter, not proof of zero actual receiver work. No receiver hashes,
full native contract suite, output/projection acceptance, recipient delivery
or protected-history proof was obtained.

Reviewed cleanup recorded one acknowledged exact owned-group DELETE and four
exact final HTTP404 observations, with the default context unchanged.
Twenty-one inherited roles were counted and untouched; zero owned/outside
roles were recorded. These are bound harness observations, not independent
fresh API readbacks or a broader absence claim.

Receipt SHA-256: `302E37A758DF74758CF5C30516A7A53699B9BE476293119FF944CC6CE5BA920B`.
Independent terminal review SHA-256:
`BA55A55665499C05754C485ADD67D0E556EF84AB61A4AE1EE49D972C9BFB7B2B`.
The earlier attempts remain preserved. CLEAN-007 remains proposed with its
original acceptance and remaining native/runtime/delivery gates.

## Output availability in the third attempt

The third independently reviewed synthetic attempt on 2026-10-11 retained one
RouteA HTTP202/native-version-bound accepted run and all three exact child
statuses: `Post_notification=Failed`, `Post_teams=Succeeded` and
`Post_email=Skipped`. Source `49f0c712bab7ad72e78593addaee4df4b5e9a8f6`
remained unchanged.

At `NativeOutputValidation`, the strict gate stopped with
`OutputStatusUnavailable`. The `envelopeRouteStatus` map/entry and String type
were present, its value field was missing, and no error field was present.
These flags describe availability only. They do not establish why the value
was missing, a hidden value, protected history, or the cause of the previous
unclassified failure. No protected content was fetched to bypass this gate.

Output and receiver-attempt evidence arrays remained empty, no receiver hashes
qualified, and nineteen cases did not run. `receiverAccounting` was
`NotEnumeratedAfterDispatch`; its zero receiver counter is stale rather than
proof of zero receiver work. RouteA and full native acceptance are incomplete.

Reviewed cleanup recorded one acknowledged exact owned-group DELETE, four
exact final HTTP404 observations and unchanged default context, with
twenty-one inherited roles untouched and zero owned/outside roles recorded.
These are scoped bound harness observations, not independent fresh API reads
or a broader absence claim.

Receipt SHA-256: `6B2543D9F6F32DB9F6C6DE31368CC7FC8C79042A63826D4DF3BB52C91E6ED1AD`.
Independent terminal review SHA-256:
`700A874285877FB3123B86AC20FF5E1736C67124EE14BF7110AB3996957A88AA`.
All earlier attempts remain preserved. CLEAN-007 remains proposed with its
original acceptance and remaining output/runtime/projection/history/delivery gates.
