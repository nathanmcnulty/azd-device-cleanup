# Deployment-agent working agreements

## Authority

- Treat the administrator's request as the authority boundary. Read-only inspection and initialization do not authorize Azure deployment, tenant writes, device disabling, permission grants, archive reads, deletion, or cleanup.
- Before a mutation, report the selected account, tenant, subscription, cloud, resource group, thresholds, exclusion group, and whether disabling or deletion is enabled.
- The repository default enables device disabling. Do not run `azd up` until the administrator acknowledges that behavior or authorizes an inert pilot with `disableEnabled=false`.
- Never enable `deleteEnabled`, reveal recovery material, or delete a tenant group without explicit approval for that action.

## Authentication and secrets

- Never use, initiate, or recommend device-code authentication.
- Use normal cached Azure Developer CLI/Azure CLI sessions and operating-system broker or browser authentication.
- Stop on authentication, tenant, consent, or authorization mismatch. Do not switch accounts, use a token supplied by the user, or weaken a check.
- Never print or persist access tokens, webhook URLs, LAPS passwords, BitLocker recovery keys, or Key Vault secret values.

## Workflow

- Prefer `azd init -t nathanmcnulty/azd-device-cleanup && azd up` only after the administrator has reviewed the default write behavior.
- For a safe pilot, initialize first, set both action flags false in `infra/main.parameters.json`, and obtain approval before deployment.
- Run `scripts/preflight.ps1` and verify exact groups, permissions, lock, schedule, and safe Automation output.
- Preserve `deleteEnabled=false` until a human recovery drill succeeds.
- Explain exactly what `azd down` removes and preserves, and resolve exact owned IDs before cleanup.

See `docs/agent-assisted-deployment.md` for the human-facing workflow.
