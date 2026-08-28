# Agent-assisted deployment

An agent can inspect prerequisites, initialize the template, explain configuration, and run tenant-independent validation. The administrator remains responsible for the selected account, tenant, subscription, exclusion scope, workload permission grants, device-state changes, and cleanup.

## Safe workflow

1. Ask the agent to inspect the repository and summarize the default behavior. Confirm it identifies that device disabling is enabled by default.
2. Confirm the selected Azure CLI account, tenant, subscription, and cloud.
3. For an inert pilot, have the agent initialize the template without deploying:

   ```powershell
   azd init -t nathanmcnulty/azd-device-cleanup
   ```

4. Set `disableEnabled=false` and `deleteEnabled=false` in `infra/main.parameters.json`.
5. Review the exact exclusion and recovery group choice, extension-attribute slots, thresholds, notification destination, and cleanup behavior.
6. Explicitly authorize `azd up` before the agent runs it. Complete normal browser or operating-system authentication yourself.
7. Run `scripts/preflight.ps1`, review the safe job and authoritative portal state, and add protected devices to the exclusion group.
8. Authorize enabling device disabling separately. Do not enable deletion until a human recovery drill succeeds.
9. Before cleanup, require the agent to resolve the exact lock, resource group, and created-versus-reused tenant objects.

## Authority boundaries

Permission to inspect or initialize does not authorize deployment. Permission to deploy does not authorize enabling deletion, revealing recovery material, deleting tenant groups, purging a vault, or changing another environment. An agent must never print a token, webhook, LAPS password, BitLocker recovery key, or archived secret.
