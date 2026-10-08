Describe 'Conditional permission and configuration parity' {
  BeforeAll {
    Set-StrictMode -Version Latest
    $repoRoot=Split-Path $PSScriptRoot -Parent
    . (Join-Path $repoRoot 'scripts/PermissionRequirements.ps1')
    $script:preflight=Get-Content -Raw (Join-Path $repoRoot 'scripts/preflight.ps1')
    $script:post=Get-Content -Raw (Join-Path $repoRoot 'scripts/postprovision.ps1')
    $script:runbook=Get-Content -Raw (Join-Path $repoRoot 'runbooks/DeviceCleanup.ps1')
    $script:bicep=Get-Content -Raw (Join-Path $repoRoot 'infra/main.bicep')
    $script:parameters=Get-Content -Raw (Join-Path $repoRoot 'infra/main.parameters.json')|ConvertFrom-Json
    $tokens=$null;$errors=$null
    $postAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot 'scripts/postprovision.ps1'),[ref]$tokens,[ref]$errors)
    foreach($definition in @($postAst.EndBlock.Statements|Where-Object{$_ -is [Management.Automation.Language.FunctionDefinitionAst] -and $_.Name -in @('Sync-GraphAppRoleAssignments','Get-OptionalEnvironmentValue','ConvertTo-BooleanValue')})){. ([scriptblock]::Create($definition.Extent.Text))}
    $preflightAst=[Management.Automation.Language.Parser]::ParseFile((Join-Path $repoRoot 'scripts/preflight.ps1'),[ref]$tokens,[ref]$errors)
    $preflightOptional=@($preflightAst.EndBlock.Statements|Where-Object{$_ -is [Management.Automation.Language.FunctionDefinitionAst] -and $_.Name -eq 'Get-OptionalEnvironmentValue'})[0]
    . ([scriptblock]::Create($preflightOptional.Extent.Text.Replace('function Get-OptionalEnvironmentValue','function Get-PreflightOptionalEnvironmentValue')))
    function Ensure-AppRoleAssignments { param($PrincipalId,$ResourceServicePrincipal,$PermissionNames,$ExistingAssignments) }
    function Remove-AppRoleAssignments { param($PrincipalId,$ResourceServicePrincipal,$PermissionNames,$ExistingAssignments) }
  }

  It 'includes the Intune read role exactly when heartbeat or primary collection needs it' -ForEach @(
    @{Slot=0;Primary=$false;Expected=$false}, @{Slot=14;Primary=$false;Expected=$true},
    @{Slot=0;Primary=$true;Expected=$true}, @{Slot=14;Primary=$true;Expected=$true}
  ) {
    $roles=@(Get-RequiredGraphPermissionNames -IntuneCheckInAttributeNumber $Slot -PrimaryArchiveUserCollectionEnabled $Primary -AdvancedHuntingEnabled $false)
    ($roles -contains 'DeviceManagementManagedDevices.Read.All') | Should -Be $Expected
    $roles | Should -Not -Contain 'User.Read.All'
  }

  It 'keeps advanced hunting conditional without changing core roles' {
    $off=@(Get-RequiredGraphPermissionNames -IntuneCheckInAttributeNumber 0 -PrimaryArchiveUserCollectionEnabled $false -AdvancedHuntingEnabled $false)
    $on=@(Get-RequiredGraphPermissionNames -IntuneCheckInAttributeNumber 0 -PrimaryArchiveUserCollectionEnabled $false -AdvancedHuntingEnabled $true)
    $on | Should -Contain 'ThreatHunting.Read.All'
    $off | Should -Not -Contain 'ThreatHunting.Read.All'
    foreach($role in @('Device.Read.All','Device.ReadWrite.All','Group.Read.All','GroupMember.Read.All','DeviceLocalCredential.Read.All','BitlockerKey.Read.All')) {
      $off | Should -Contain $role
    }
  }

  It 'executes the production ensure/remove path for every Intune consumer combination' -ForEach @(
    @{Slot=0;Primary=$false;ExpectedEnsure=$false;ExpectedRemove=$true}, @{Slot=14;Primary=$false;ExpectedEnsure=$true;ExpectedRemove=$false},
    @{Slot=0;Primary=$true;ExpectedEnsure=$true;ExpectedRemove=$false}, @{Slot=14;Primary=$true;ExpectedEnsure=$true;ExpectedRemove=$false}
  ) {
    $script:ensured=@();$script:removed=@()
    Mock Ensure-AppRoleAssignments { $script:ensured=@($PermissionNames) }
    Mock Remove-AppRoleAssignments { $script:removed+=@($PermissionNames) }
    $roles=@(Sync-GraphAppRoleAssignments -PrincipalId 'principal' -GraphServicePrincipal ([pscustomobject]@{id='graph'}) -ExistingAssignments ([Collections.ArrayList]::new()) -IntuneCheckInAttributeNumber $Slot -PrimaryArchiveUserCollectionEnabled $Primary -AdvancedHuntingEnabled $false)
    ($script:ensured -contains 'DeviceManagementManagedDevices.Read.All') | Should -Be $ExpectedEnsure
    ($script:removed -contains 'DeviceManagementManagedDevices.Read.All') | Should -Be $ExpectedRemove
    $roles | Should -Not -Contain 'User.Read.All'
    $script:ensured | Should -Not -Contain 'User.Read.All'
    $script:removed | Should -Not -Contain 'User.Read.All'
  }

  It 'defaults a retained postprovision environment without the new flag to false' {
    $previous=[Environment]::GetEnvironmentVariable('PRIMARY_ARCHIVE_USER_COLLECTION_ENABLED')
    try {
      [Environment]::SetEnvironmentVariable('PRIMARY_ARCHIVE_USER_COLLECTION_ENABLED',$null)
      $script:AzdEnvironmentValues=@{}
      $value=Get-OptionalEnvironmentValue -Name 'PRIMARY_ARCHIVE_USER_COLLECTION_ENABLED' -Default 'false'
      (ConvertTo-BooleanValue -Name 'PRIMARY_ARCHIVE_USER_COLLECTION_ENABLED' -Value $value) | Should -BeFalse
    }
    finally { [Environment]::SetEnvironmentVariable('PRIMARY_ARCHIVE_USER_COLLECTION_ENABLED',$previous) }
  }

  It 'defaults a retained preflight environment without the new flag to false' {
    $value=Get-PreflightOptionalEnvironmentValue -EnvironmentValues @{} -Name 'PRIMARY_ARCHIVE_USER_COLLECTION_ENABLED' -Default 'false'
    (ConvertTo-BooleanValue -Name 'PRIMARY_ARCHIVE_USER_COLLECTION_ENABLED' -Value $value) | Should -BeFalse
  }

  It 'keeps the permission helper side-effect-free in its caller scope' {
    $result=& {
      Set-StrictMode -Off
      . (Join-Path $repoRoot 'scripts/PermissionRequirements.ps1')
      try { $null=$undefinedCallerVariable; 'strict-off' } catch { 'strict-on' }
    }
    $result | Should -Be 'strict-off'
  }

  It 'wires the default-false flag through Bicep, hook, runbook and inert preflight' {
    $script:parameters.parameters.primaryArchiveUserCollectionEnabled.value | Should -BeFalse
    $script:bicep | Should -Match 'param primaryArchiveUserCollectionEnabled bool = false'
    $script:bicep | Should -Match 'output PRIMARY_ARCHIVE_USER_COLLECTION_ENABLED'
    $script:post | Should -Match '__PRIMARY_ARCHIVE_USER_COLLECTION_ENABLED__'
    $script:runbook | Should -Match '__PRIMARY_ARCHIVE_USER_COLLECTION_ENABLED__'
    $script:preflight | Should -Match "PrimaryArchiveUserCollectionEnabled = 'false'"
    $script:post | Should -Match "Get-OptionalEnvironmentValue -Name 'PRIMARY_ARCHIVE_USER_COLLECTION_ENABLED' -Default 'false'"
    $script:preflight | Should -Match "Get-OptionalEnvironmentValue -EnvironmentValues [`$]envValues -Name 'PRIMARY_ARCHIVE_USER_COLLECTION_ENABLED' -Default 'false'"
  }

  It 'binds permission evidence to canonical Git LF UTF-8 content hashes' {
    $manifest=Get-Content -Raw (Join-Path $repoRoot 'azd-permissions.json')|ConvertFrom-Json
    foreach($evidence in @($manifest.requirements.evidence)){
      $content=(Get-Content -Raw (Join-Path $repoRoot $evidence.path)).Replace("`r`n","`n")
      $bytes=[Text.Encoding]::UTF8.GetBytes($content)
      $actual=[Convert]::ToHexString([Security.Cryptography.SHA256]::HashData($bytes)).ToLowerInvariant()
      $actual | Should -Be $evidence.sha256
    }
  }
}
