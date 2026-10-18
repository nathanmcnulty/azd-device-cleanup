# Development

Contributor tooling is not part of the administrator quickstart.

## Validate

Use PowerShell 7.6+ and Pester 6.2.0. CI selects a SHA-256-verified PowerShell 7.6.6 runtime. From the repository root:

```powershell
$errors = @()
Get-ChildItem . -Recurse -File | Where-Object Extension -In '.ps1', '.psm1', '.psd1' | ForEach-Object {
  $tokens = $null
  $parseErrors = $null
  [System.Management.Automation.Language.Parser]::ParseFile($_.FullName, [ref]$tokens, [ref]$parseErrors) | Out-Null
  $errors += @($parseErrors)
}
if ($errors.Count) { throw ($errors | Format-List | Out-String) }

Install-Module Pester -RequiredVersion 6.2.0 -Scope CurrentUser -Force
Import-Module Pester -RequiredVersion 6.2.0 -Force
$result = Invoke-Pester -Path ./tests -PassThru
if ($null -eq $result -or $result.Result -ne 'Passed' -or $result.TotalCount -eq 0 -or $result.SkippedCount -or $result.InconclusiveCount -or $result.NotRunCount) {
  throw 'Every registered device safety test must pass without omissions.'
}

az bicep build --file .\infra\main.bicep
git diff --exit-code -- .\infra\main.json
```

Also parse `infra/main.parameters.json`, validate every relative Markdown link, scan for credentials and device-code authentication, and confirm the checkout remains clean. The generated `infra/main.json` is tracked and must be committed only when it exactly matches `infra/main.bicep`.

## Publication

Before publication, initialize into a fresh directory with the public quickstart, review the prompted values, confirm the post-provision hook uses only administrator tooling, run the safe preflight job, and verify default cleanup behavior. Do not enable deletion for a smoke test.
