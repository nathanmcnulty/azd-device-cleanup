function Get-RequiredGraphPermissionNames {
  param(
    [Parameter(Mandatory = $true)][int] $IntuneCheckInAttributeNumber,
    [Parameter(Mandatory = $true)][bool] $PrimaryArchiveUserCollectionEnabled,
    [Parameter(Mandatory = $true)][bool] $AdvancedHuntingEnabled
  )

  $permissions = @(
    'Device.Read.All',
    'Device.ReadWrite.All',
    'Group.Read.All',
    'GroupMember.Read.All',
    'DeviceLocalCredential.Read.All',
    'BitlockerKey.Read.All'
  )
  if ($IntuneCheckInAttributeNumber -gt 0 -or $PrimaryArchiveUserCollectionEnabled) {
    $permissions += 'DeviceManagementManagedDevices.Read.All'
  }
  if ($AdvancedHuntingEnabled) {
    $permissions += 'ThreatHunting.Read.All'
  }
  return $permissions
}
