param(
    [string] $KeyVaultName = '__DEVICE_ARCHIVE_KEY_VAULT_NAME__',
    [string] $SecretNamePrefix = '__DEVICE_SECRET_PREFIX__',
    [string] $DisableAfterDays = '__DEVICE_DISABLE_AFTER_DAYS__',
    [string] $DeleteAfterDays = '__DEVICE_DELETE_AFTER_DAYS__',
    [string] $MaxDeleteCount = '__DEVICE_MAX_DELETE_COUNT__',
    [string] $DisableEnabled = '__DEVICE_DISABLE_ENABLED__',
    [string] $DeleteEnabled = '__DEVICE_DELETE_ENABLED__',
    [string] $ExcludedDeviceGroupId = '__EXCLUSION_DEVICE_GROUP_ID__',
    [string] $IntuneCheckInAttributeNumber = '__INTUNE_CHECKIN_ATTRIBUTE_NUMBER__',
    [string] $DefenderCheckInAttributeNumber = '__DEFENDER_CHECKIN_ATTRIBUTE_NUMBER__',
    [string] $AdvancedHuntingEnabled = '__ADVANCED_HUNTING_ENABLED__',
    [string] $AdvancedHuntingLookbackDays = '__ADVANCED_HUNTING_LOOKBACK_DAYS__',
    [string] $NotificationsEnabled = '__LOGIC_APP_NOTIFICATIONS_ENABLED__',
    [string] $NotificationCallbackUrl = '__LOGIC_APP_NOTIFICATION_CALLBACK_URL__',
    [string] $NotifyOnSuccess = '__LOGIC_APP_NOTIFY_ON_SUCCESS__',
    [string] $NotifyOnFailure = '__LOGIC_APP_NOTIFY_ON_FAILURE__',
    [string] $NotifyOnNoAction = '__LOGIC_APP_NOTIFY_ON_NO_ACTION__',
    [string] $EnvironmentName = '__AZURE_ENV_NAME__',
    [string] $SubscriptionId = '__AZURE_SUBSCRIPTION_ID__',
    [string] $ResourceGroupName = '__AZURE_RESOURCE_GROUP__',
    [string] $AutomationAccountName = '__AUTOMATION_ACCOUNT_NAME__',
    [string] $AutomationRunbookName = '__AUTOMATION_RUNBOOK_NAME__'
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$script:GraphResourceUrl = 'https://graph.microsoft.com/'
$script:DefenderResourceUrl = 'https://api.securitycenter.microsoft.com'
$script:DefenderApiUrl = 'https://api.security.microsoft.com'
$script:KeyVaultResourceUrl = 'https://vault.azure.net'
$script:TokenCache = @{}

function Get-RequiredInput {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name,
        [AllowNull()]
        [string] $Value
    )

    if ([string]::IsNullOrWhiteSpace($Value) -or ($Value.StartsWith('__') -and $Value.EndsWith('__'))) {
        throw "Required input '$Name' is missing."
    }

    return $Value
}

function Get-OptionalConfiguredInput {
    param(
        [AllowNull()]
        [string] $Value
    )

    if ([string]::IsNullOrWhiteSpace($Value) -or ($Value.StartsWith('__') -and $Value.EndsWith('__'))) {
        return $null
    }

    return $Value
}

function Get-IntegerInput {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name,
        [Parameter(Mandatory = $true)]
        [string] $Value
    )

    $parsed = 0
    if (-not [int]::TryParse($Value, [ref] $parsed)) {
        throw "Input '$Name' must be an integer. Current value: '$Value'."
    }

    return $parsed
}

function Get-ExtensionAttributeNumberInput {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name,
        [Parameter(Mandatory = $true)]
        [string] $Value
    )

    $parsed = Get-IntegerInput -Name $Name -Value $Value
    if (($parsed -lt 0) -or ($parsed -gt 15)) {
        throw "Input '$Name' must be between 0 and 15. Current value: '$Value'."
    }

    return $parsed
}

function Get-BooleanInput {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Name,
        [Parameter(Mandatory = $true)]
        [string] $Value
    )

    switch ($Value.Trim().ToLowerInvariant()) {
        '1' { return $true }
        '0' { return $false }
        'true' { return $true }
        'false' { return $false }
        'yes' { return $true }
        'no' { return $false }
        default { throw "Input '$Name' must be a boolean value. Current value: '$Value'." }
    }
}

function Get-ExtensionAttributeName {
    param(
        [Parameter(Mandatory = $true)]
        [int] $Number
    )

    if (($Number -lt 1) -or ($Number -gt 15)) {
        throw "Extension attribute number must be between 1 and 15. Current value: '$Number'."
    }

    return "extensionAttribute$Number"
}

function Get-NormalizedTimestamp {
    param(
        [AllowNull()]
        [string] $Value
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $null
    }

    return [datetime]::Parse($Value).ToUniversalTime().ToString('o')
}

function Get-HttpStatusCode {
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.ErrorRecord] $ErrorRecord
    )

    $response = $ErrorRecord.Exception.Response
    if ($null -eq $response) {
        return $null
    }

    if ($response.PSObject.Properties.Name -contains 'StatusCode') {
        $statusCode = $response.StatusCode
        if ($statusCode -is [int]) {
            return $statusCode
        }

        if ($statusCode.PSObject.Properties.Name -contains 'value__') {
            return [int] $statusCode.value__
        }
    }

    return $null
}

function Test-IsRestrictedManagementAdministrativeUnitError {
    param(
        [Parameter(Mandatory = $true)]
        [System.Management.Automation.ErrorRecord] $ErrorRecord
    )

    $statusCode = Get-HttpStatusCode -ErrorRecord $ErrorRecord
    if ($statusCode -ne 403) {
        return $false
    }

    $messages = @(
        $ErrorRecord.Exception.Message,
        $ErrorRecord.ErrorDetails.Message
    ) | Where-Object { -not [string]::IsNullOrWhiteSpace($_) }

    foreach ($message in $messages) {
        if ($message -like '*restricted management administrative unit*') {
            return $true
        }
    }

    return $false
}

function Invoke-JsonRestMethod {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Method,
        [Parameter(Mandatory = $true)]
        [string] $Uri,
        [Parameter(Mandatory = $true)]
        [string] $AccessToken,
        [object] $Body,
        [hashtable] $AdditionalHeaders = @{}
    )

    $headers = @{
        Authorization = "Bearer $AccessToken"
        'Content-Type' = 'application/json'
        'User-Agent' = 'azd-device-cleanup/0.1.0'
        'ocp-client-name' = 'azd-device-cleanup'
        'ocp-client-version' = '0.1.0'
    }

    foreach ($key in $AdditionalHeaders.Keys) {
        $headers[$key] = $AdditionalHeaders[$key]
    }

    $request = @{
        Method = $Method
        Uri = $Uri
        Headers = $headers
        ErrorAction = 'Stop'
    }

    if ($PSBoundParameters.ContainsKey('Body')) {
        $request.Body = if ($Body -is [string]) { $Body } else { $Body | ConvertTo-Json -Depth 20 -Compress }
    }

    Invoke-RestMethod @request
}

function Get-ManagedIdentityToken {
    param(
        [Parameter(Mandatory = $true)]
        [string] $ResourceUrl
    )

    if ($script:TokenCache.ContainsKey($ResourceUrl)) {
        $cached = $script:TokenCache[$ResourceUrl]
        if ($cached.ExpiresOn -gt (Get-Date).ToUniversalTime().AddMinutes(5)) {
            return $cached.Token
        }
    }

    $encodedResource = [Uri]::EscapeDataString($ResourceUrl)
    $tokenResponse = $null

    if (-not [string]::IsNullOrWhiteSpace($env:IDENTITY_ENDPOINT) -and -not [string]::IsNullOrWhiteSpace($env:IDENTITY_HEADER)) {
        $tokenUri = "$($env:IDENTITY_ENDPOINT)?resource=$encodedResource&api-version=2019-08-01"
        $tokenResponse = Invoke-RestMethod -Method 'GET' -Uri $tokenUri -Headers @{
            Metadata = 'True'
            'X-IDENTITY-HEADER' = $env:IDENTITY_HEADER
        } -ErrorAction Stop
    }
    elseif (-not [string]::IsNullOrWhiteSpace($env:MSI_ENDPOINT) -and -not [string]::IsNullOrWhiteSpace($env:MSI_SECRET)) {
        $tokenUri = "$($env:MSI_ENDPOINT)?resource=$encodedResource&api-version=2017-09-01"
        $tokenResponse = Invoke-RestMethod -Method 'GET' -Uri $tokenUri -Headers @{
            Secret = $env:MSI_SECRET
        } -ErrorAction Stop
    }
    else {
        $tokenUri = "http://169.254.169.254/metadata/identity/oauth2/token?resource=$encodedResource&api-version=2018-02-01"
        $tokenResponse = Invoke-RestMethod -Method 'GET' -Uri $tokenUri -Headers @{
            Metadata = 'true'
        } -ErrorAction Stop
    }

    $expiresOn = if ($tokenResponse.expires_on -match '^\d+$') {
        [DateTimeOffset]::FromUnixTimeSeconds([int64] $tokenResponse.expires_on).UtcDateTime
    }
    else {
        [datetime]::Parse($tokenResponse.expires_on).ToUniversalTime()
    }

    $script:TokenCache[$ResourceUrl] = @{
        Token = $tokenResponse.access_token
        ExpiresOn = $expiresOn
    }

    return $tokenResponse.access_token
}

function Get-GraphObject {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Uri
    )

    $token = Get-ManagedIdentityToken -ResourceUrl $script:GraphResourceUrl
    $response = Invoke-JsonRestMethod -Method 'GET' -Uri $Uri -AccessToken $token

    if ($response.PSObject.Properties.Name -contains 'value') {
        return $response.value
    }

    return $response
}

function Get-GraphCollection {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Uri
    )

    $token = Get-ManagedIdentityToken -ResourceUrl $script:GraphResourceUrl
    $items = @()
    $next = $Uri

    while (-not [string]::IsNullOrWhiteSpace($next)) {
        $response = Invoke-JsonRestMethod -Method 'GET' -Uri $next -AccessToken $token

        if ($response.PSObject.Properties.Name -contains 'value') {
            $items += @($response.value)
        }

        $next = if ($response.PSObject.Properties.Name -contains '@odata.nextLink') {
            $response.'@odata.nextLink'
        }
        else {
            $null
        }
    }

    return $items
}

function Get-DefenderMachines {
    $token = Get-ManagedIdentityToken -ResourceUrl $script:DefenderResourceUrl
    $items = @()
    $skip = 0
    $pageSize = 10000

    while ($true) {
        $uri = "$($script:DefenderApiUrl)/api/machines?`$top=$pageSize&`$skip=$skip"
        try {
            $response = Invoke-JsonRestMethod -Method 'GET' -Uri $uri -AccessToken $token
        }
        catch {
            $statusCode = Get-HttpStatusCode -ErrorRecord $_
            if (($statusCode -eq 404) -and ($skip -eq 0)) {
                return @()
            }

            throw
        }

        $batch = @($response.value)
        if ($batch.Count -eq 0) {
            break
        }

        $items += $batch
        if ($batch.Count -lt $pageSize) {
            break
        }

        $skip += $batch.Count
    }

    return $items
}

function New-DefenderMachineIndex {
    param(
        [Parameter(Mandatory = $true)]
        [object[]] $Machines
    )

    $index = @{}
    foreach ($machine in $Machines) {
        $key = Get-IndexedDeviceId -DeviceId $machine.aadDeviceId
        if ($null -eq $key) {
            continue
        }

        $index[$key] = Select-NewerCheckInRecord -Current $index[$key] -Candidate $machine -TimestampPropertyName 'lastSeen'
    }

    return $index
}

function Invoke-GraphHuntingQuery {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Query,
        [Parameter(Mandatory = $true)]
        [int] $LookbackDays
    )

    $token = Get-ManagedIdentityToken -ResourceUrl $script:GraphResourceUrl
    $uri = 'https://graph.microsoft.com/v1.0/security/runHuntingQuery'
    $response = Invoke-JsonRestMethod -Method 'POST' -Uri $uri -AccessToken $token -Body @{
        Query = $Query
        Timespan = "P${LookbackDays}D"
    }

    if ($null -eq $response -or -not ($response.PSObject.Properties.Name -contains 'results')) {
        return @()
    }

    return @($response.results)
}

function Get-AdvancedHuntingHeartbeatRows {
    param(
        [Parameter(Mandatory = $true)]
        [int] $LookbackDays
    )

    $query = @'
union isfuzzy=true
(
    DeviceInfo
    | where isnotempty(AadDeviceId)
    | extend DeviceHeartbeatTimestamp = Timestamp
    | summarize arg_max(DeviceHeartbeatTimestamp, *) by AadDeviceId
    | extend SourceTable = "DeviceInfo", HeartbeatTimestamp = DeviceHeartbeatTimestamp, DefenderMachineId = tostring(DeviceId), DefenderSensorHealthState = tostring(SensorHealthState), DefenderOnboardingStatus = tostring(OnboardingStatus)
    | project AadDeviceId, SourceTable, HeartbeatTimestamp, DeviceName, DefenderMachineId, DefenderSensorHealthState, DefenderOnboardingStatus, Record = pack_all()
),
(
    DeviceLogonEvents
    | where isnotempty(AadDeviceId)
    | summarize arg_max(Timestamp, *) by AadDeviceId
    | extend SourceTable = "DeviceLogonEvents", HeartbeatTimestamp = Timestamp
    | project AadDeviceId, SourceTable, HeartbeatTimestamp, DeviceName, DefenderMachineId = "", DefenderSensorHealthState = "", DefenderOnboardingStatus = "", Record = pack_all()
),
(
    IdentityLogonEvents
    | where isnotempty(AadDeviceId)
    | summarize arg_max(Timestamp, *) by AadDeviceId
    | extend SourceTable = "IdentityLogonEvents", HeartbeatTimestamp = Timestamp
    | project AadDeviceId, SourceTable, HeartbeatTimestamp, DeviceName, DefenderMachineId = "", DefenderSensorHealthState = "", DefenderOnboardingStatus = "", Record = pack_all()
)
| where isnotempty(AadDeviceId)
| order by HeartbeatTimestamp desc
'@

    return @(Invoke-GraphHuntingQuery -Query $query -LookbackDays $LookbackDays)
}

function Get-IntuneManagedDevices {
    $select = [Uri]::EscapeDataString('id,deviceName,azureADDeviceId,lastSyncDateTime,serialNumber')
    $uri = "https://graph.microsoft.com/v1.0/deviceManagement/managedDevices?`$select=$select"

    return @(Get-GraphCollection -Uri $uri)
}

function Get-EntraDevices {
    $select = [Uri]::EscapeDataString('id,deviceId,displayName,accountEnabled,approximateLastSignInDateTime,operatingSystem,operatingSystemVersion,trustType,extensionAttributes')
    $uri = "https://graph.microsoft.com/v1.0/devices?`$select=$select"

    return @(Get-GraphCollection -Uri $uri)
}

function Get-ExcludedDeviceIdSet {
    param(
        [AllowNull()]
        [string] $GroupId
    )

    if ([string]::IsNullOrWhiteSpace($GroupId)) {
        return $null
    }

    $select = [Uri]::EscapeDataString('id,deviceId,displayName')
    $uri = "https://graph.microsoft.com/v1.0/groups/$GroupId/members/microsoft.graph.device?`$select=$select"
    $excludedDevices = @(Get-GraphCollection -Uri $uri)
    $set = @{}
    foreach ($device in $excludedDevices) {
        if ([string]::IsNullOrWhiteSpace($device.id)) {
            continue
        }

        $set[$device.id.Trim().ToLowerInvariant()] = $true
    }

    return $set
}

function Get-DeviceInactiveDays {
    param(
        [Parameter(Mandatory = $true)]
        [object] $Device,
        [Parameter(Mandatory = $true)]
        [datetime] $ReferenceTime
    )

    if ([string]::IsNullOrWhiteSpace($Device.approximateLastSignInDateTime)) {
        return $null
    }

    $lastSignIn = [datetime]::Parse($Device.approximateLastSignInDateTime).ToUniversalTime()
    return [int] [Math]::Floor(($ReferenceTime - $lastSignIn).TotalDays)
}

function Get-IndexedDeviceId {
    param(
        [AllowNull()]
        [string] $DeviceId
    )

    if ([string]::IsNullOrWhiteSpace($DeviceId)) {
        return $null
    }

    return $DeviceId.Trim().ToLowerInvariant()
}

function Select-NewerCheckInRecord {
    param(
        [AllowNull()]
        [object] $Current,
        [AllowNull()]
        [object] $Candidate,
        [Parameter(Mandatory = $true)]
        [string] $TimestampPropertyName
    )

    if ($null -eq $Current) {
        return $Candidate
    }

    if ($null -eq $Candidate) {
        return $Current
    }

    $currentTimestamp = Get-NormalizedTimestamp -Value $Current.$TimestampPropertyName
    $candidateTimestamp = Get-NormalizedTimestamp -Value $Candidate.$TimestampPropertyName

    if ($null -eq $currentTimestamp) {
        return $Candidate
    }

    if ($null -eq $candidateTimestamp) {
        return $Current
    }

    if ([datetime]::Parse($candidateTimestamp) -gt [datetime]::Parse($currentTimestamp)) {
        return $Candidate
    }

    return $Current
}

function New-IntuneManagedDeviceIndex {
    param(
        [Parameter(Mandatory = $true)]
        [object[]] $ManagedDevices
    )

    $index = @{}
    foreach ($managedDevice in $ManagedDevices) {
        $key = Get-IndexedDeviceId -DeviceId $managedDevice.azureADDeviceId
        if ($null -eq $key) {
            continue
        }

        $index[$key] = Select-NewerCheckInRecord -Current $index[$key] -Candidate $managedDevice -TimestampPropertyName 'lastSyncDateTime'
    }

    return $index
}

function New-AdvancedHuntingHeartbeatIndex {
    param(
        [Parameter(Mandatory = $true)]
        [object[]] $Rows
    )

    $index = @{}
    foreach ($row in $Rows) {
        $key = Get-IndexedDeviceId -DeviceId $row.AadDeviceId
        if ($null -eq $key) {
            continue
        }

        $record = [pscustomobject]@{
            SourceTable = $row.SourceTable
            DeviceName = $row.DeviceName
            HeartbeatTimestamp = Get-NormalizedTimestamp -Value ([string] $row.HeartbeatTimestamp)
            DefenderMachineId = if ([string]::IsNullOrWhiteSpace([string] $row.DefenderMachineId)) { $null } else { [string] $row.DefenderMachineId }
            DefenderSensorHealthState = if ([string]::IsNullOrWhiteSpace([string] $row.DefenderSensorHealthState)) { $null } else { [string] $row.DefenderSensorHealthState }
            DefenderOnboardingStatus = if ([string]::IsNullOrWhiteSpace([string] $row.DefenderOnboardingStatus)) { $null } else { [string] $row.DefenderOnboardingStatus }
            Record = $row.Record
        }

        if (-not $index.ContainsKey($key)) {
            $index[$key] = New-Object System.Collections.Generic.List[object]
        }

        $index[$key].Add($record)
    }

    return $index
}

function Get-LatestAdvancedHuntingRecord {
    param(
        [AllowNull()]
        [object[]] $Records,
        [AllowEmptyString()]
        [string] $SourceTable = ''
    )

    $latestRecord = $null
    foreach ($record in @($Records)) {
        if ($null -eq $record -or $null -eq $record.HeartbeatTimestamp) {
            continue
        }

        if ((-not [string]::IsNullOrWhiteSpace($SourceTable)) -and ($record.SourceTable -ne $SourceTable)) {
            continue
        }

        $latestRecord = Select-NewerCheckInRecord -Current $latestRecord -Candidate $record -TimestampPropertyName 'HeartbeatTimestamp'
    }

    return $latestRecord
}

function Get-CheckInState {
    param(
        [AllowNull()]
        [string] $Timestamp,
        [Parameter(Mandatory = $true)]
        [int] $StaleAfterDays,
        [Parameter(Mandatory = $true)]
        [datetime] $ReferenceTime
    )

    $normalizedTimestamp = Get-NormalizedTimestamp -Value $Timestamp
    if ($null -eq $normalizedTimestamp) {
        return 'Unknown'
    }

    $lastCheckIn = [datetime]::Parse($normalizedTimestamp).ToUniversalTime()
    if (($ReferenceTime - $lastCheckIn).TotalDays -ge $StaleAfterDays) {
        return 'Stale'
    }

    return 'Fresh'
}

function Format-CheckInAttributeValue {
    param(
        [Parameter(Mandatory = $true)]
        [string] $State,
        [AllowNull()]
        [string] $Timestamp
    )

    $normalizedTimestamp = Get-NormalizedTimestamp -Value $Timestamp
    if ($null -eq $normalizedTimestamp) {
        return "$State|none"
    }

    return "$State|$normalizedTimestamp"
}

function Get-EffectiveHeartbeat {
    param(
        [Parameter(Mandatory = $true)]
        [datetime] $ReferenceTime,
        [Parameter(Mandatory = $true)]
        [int] $StaleAfterDays,
        [AllowNull()]
        [string] $EntraTimestamp,
        [AllowNull()]
        [object] $IntuneData,
        [AllowNull()]
        [object] $DefenderData,
        [AllowNull()]
        [object[]] $AdvancedHuntingRecords
    )

    $signals = New-Object System.Collections.Generic.List[object]

    $normalizedEntraTimestamp = Get-NormalizedTimestamp -Value $EntraTimestamp
    if ($null -ne $normalizedEntraTimestamp) {
        $signals.Add([pscustomobject]@{
                Source = 'EntraApproximateLastSignIn'
                Timestamp = $normalizedEntraTimestamp
            })
    }

    if (($null -ne $IntuneData) -and ($null -ne $IntuneData.LastCheckIn)) {
        $signals.Add([pscustomobject]@{
                Source = 'IntuneLastSync'
                Timestamp = $IntuneData.LastCheckIn
            })
    }

    if (($null -ne $DefenderData) -and ($null -ne $DefenderData.LastCheckIn)) {
        $signals.Add([pscustomobject]@{
                Source = 'DefenderForEndpointLastSeen'
                Timestamp = $DefenderData.LastCheckIn
            })
    }

    foreach ($record in @($AdvancedHuntingRecords)) {
        if ($null -eq $record -or $null -eq $record.HeartbeatTimestamp) {
            continue
        }

        $signals.Add([pscustomobject]@{
                Source = "AdvancedHunting:$($record.SourceTable)"
                Timestamp = $record.HeartbeatTimestamp
            })
    }

    if ($signals.Count -eq 0) {
        return [pscustomobject]@{
            Timestamp = $null
            Source = $null
            InactiveDays = $null
            State = 'Unknown'
            Signals = @()
        }
    }

    $latestSignal = $null
    foreach ($signal in $signals) {
        if ($null -eq $latestSignal) {
            $latestSignal = $signal
            continue
        }

        $candidateTimestamp = [datetime]::Parse($signal.Timestamp).ToUniversalTime()
        $currentTimestamp = [datetime]::Parse($latestSignal.Timestamp).ToUniversalTime()
        if (($candidateTimestamp -gt $currentTimestamp) -or (($candidateTimestamp -eq $currentTimestamp) -and ([string] $signal.Source -lt [string] $latestSignal.Source))) {
            $latestSignal = $signal
        }
    }

    $inactiveDays = [int] [Math]::Floor(($ReferenceTime - [datetime]::Parse($latestSignal.Timestamp).ToUniversalTime()).TotalDays)
    $effectiveState = if ($inactiveDays -ge $StaleAfterDays) { 'Stale' } else { 'Fresh' }
    $signalArray = @()
    foreach ($signal in $signals) {
        $signalArray += $signal
    }

    return [pscustomobject]@{
        Timestamp = $latestSignal.Timestamp
        Source = $latestSignal.Source
        InactiveDays = $inactiveDays
        State = $effectiveState
        Signals = $signalArray
    }
}

function Get-IntuneCheckInData {
    param(
        [Parameter(Mandatory = $true)]
        [object] $Device,
        [Parameter(Mandatory = $true)]
        [hashtable] $ManagedDeviceIndex,
        [Parameter(Mandatory = $true)]
        [int] $StaleAfterDays,
        [Parameter(Mandatory = $true)]
        [datetime] $ReferenceTime
    )

    $deviceKey = Get-IndexedDeviceId -DeviceId $Device.deviceId
    if ($null -eq $deviceKey) {
        return [pscustomobject]@{
            SourceFound = $false
            State = 'Unknown'
            LastCheckIn = $null
            ManagedDeviceId = $null
            DeviceName = $null
            AttributeValue = Format-CheckInAttributeValue -State 'Unknown' -Timestamp $null
        }
    }

    $managedDevice = $ManagedDeviceIndex[$deviceKey]
    if ($null -eq $managedDevice) {
        return [pscustomobject]@{
            SourceFound = $false
            State = 'Unmanaged'
            LastCheckIn = $null
            ManagedDeviceId = $null
            DeviceName = $null
            AttributeValue = Format-CheckInAttributeValue -State 'Unmanaged' -Timestamp $null
        }
    }

    $state = Get-CheckInState -Timestamp $managedDevice.lastSyncDateTime -StaleAfterDays $StaleAfterDays -ReferenceTime $ReferenceTime
    $timestamp = Get-NormalizedTimestamp -Value $managedDevice.lastSyncDateTime

    return [pscustomobject]@{
        SourceFound = $true
        State = $state
        LastCheckIn = $timestamp
        ManagedDeviceId = $managedDevice.id
        DeviceName = $managedDevice.deviceName
        SerialNumber = $managedDevice.serialNumber
        AttributeValue = Format-CheckInAttributeValue -State $state -Timestamp $timestamp
    }
}

function Get-DefenderCheckInData {
    param(
        [Parameter(Mandatory = $true)]
        [object] $Device,
        [AllowNull()]
        [object[]] $AdvancedHuntingRecords,
        [Parameter(Mandatory = $true)]
        [int] $StaleAfterDays,
        [Parameter(Mandatory = $true)]
        [datetime] $ReferenceTime
    )

    $deviceKey = Get-IndexedDeviceId -DeviceId $Device.deviceId
    if ($null -eq $deviceKey) {
        return [pscustomobject]@{
            SourceFound = $false
            State = 'Unknown'
            LastCheckIn = $null
            MachineId = $null
            DeviceName = $null
            SensorHealthState = $null
            OnboardingStatus = $null
            AttributeValue = Format-CheckInAttributeValue -State 'Unknown' -Timestamp $null
        }
    }

    $latestRecord = Get-LatestAdvancedHuntingRecord -Records $AdvancedHuntingRecords
    if ($null -eq $latestRecord) {
        return [pscustomobject]@{
            SourceFound = $false
            State = 'NotOnboarded'
            LastCheckIn = $null
            MachineId = $null
            DeviceName = $null
            SensorHealthState = $null
            OnboardingStatus = $null
            AttributeValue = Format-CheckInAttributeValue -State 'NotOnboarded' -Timestamp $null
        }
    }

    $deviceInfoRecord = Get-LatestAdvancedHuntingRecord -Records $AdvancedHuntingRecords -SourceTable 'DeviceInfo'
    $timestamp = $latestRecord.HeartbeatTimestamp
    $state = Get-CheckInState -Timestamp $timestamp -StaleAfterDays $StaleAfterDays -ReferenceTime $ReferenceTime

    return [pscustomobject]@{
        SourceFound = $true
        State = $state
        LastCheckIn = $timestamp
        MachineId = if ($null -eq $deviceInfoRecord) { $null } else { $deviceInfoRecord.DefenderMachineId }
        DeviceName = $latestRecord.DeviceName
        SensorHealthState = if ($null -eq $deviceInfoRecord) { $null } else { $deviceInfoRecord.DefenderSensorHealthState }
        OnboardingStatus = if ($null -eq $deviceInfoRecord) { $null } else { $deviceInfoRecord.DefenderOnboardingStatus }
        AttributeValue = Format-CheckInAttributeValue -State $state -Timestamp $timestamp
    }
}

function Get-DefenderMachineCheckInData {
    param(
        [Parameter(Mandatory = $true)]
        [object] $Device,
        [AllowNull()]
        [hashtable] $MachineIndex,
        [Parameter(Mandatory = $true)]
        [int] $StaleAfterDays,
        [Parameter(Mandatory = $true)]
        [datetime] $ReferenceTime
    )

    $deviceKey = Get-IndexedDeviceId -DeviceId $Device.deviceId
    if (($null -eq $deviceKey) -or ($null -eq $MachineIndex)) {
        return [pscustomobject]@{
            SourceFound = $false
            State = 'Unknown'
            LastCheckIn = $null
            MachineId = $null
            DeviceName = $null
            SensorHealthState = $null
            OnboardingStatus = $null
            AttributeValue = Format-CheckInAttributeValue -State 'Unknown' -Timestamp $null
        }
    }

    $machine = $MachineIndex[$deviceKey]
    if ($null -eq $machine) {
        return [pscustomobject]@{
            SourceFound = $false
            State = 'NotOnboarded'
            LastCheckIn = $null
            MachineId = $null
            DeviceName = $null
            SensorHealthState = $null
            OnboardingStatus = $null
            AttributeValue = Format-CheckInAttributeValue -State 'NotOnboarded' -Timestamp $null
        }
    }

    $state = Get-CheckInState -Timestamp $machine.lastSeen -StaleAfterDays $StaleAfterDays -ReferenceTime $ReferenceTime
    $timestamp = Get-NormalizedTimestamp -Value $machine.lastSeen

    return [pscustomobject]@{
        SourceFound = $true
        State = $state
        LastCheckIn = $timestamp
        MachineId = $machine.id
        DeviceName = $machine.computerDnsName
        SensorHealthState = $machine.healthStatus
        OnboardingStatus = $machine.onboardingStatus
        AttributeValue = Format-CheckInAttributeValue -State $state -Timestamp $timestamp
    }
}

function Get-DeviceCheckInData {
    param(
        [Parameter(Mandatory = $true)]
        [object] $Device,
        [Parameter(Mandatory = $true)]
        [object] $Settings,
        [Parameter(Mandatory = $true)]
        [datetime] $ReferenceTime,
        [AllowNull()]
        [hashtable] $ManagedDeviceIndex,
        [AllowNull()]
        [hashtable] $MachineIndex,
        [AllowNull()]
        [hashtable] $AdvancedHuntingIndex
    )

    $intuneData = $null
    $defenderData = $null
    $advancedHuntingRecords = @()

    if ($Settings.IntuneCheckInAttributeNumber -gt 0) {
        $intuneData = Get-IntuneCheckInData -Device $Device -ManagedDeviceIndex $ManagedDeviceIndex -StaleAfterDays $Settings.DisableAfterDays -ReferenceTime $ReferenceTime
    }

    if ($Settings.AdvancedHuntingEnabled) {
        $deviceKey = Get-IndexedDeviceId -DeviceId $Device.deviceId
        if (($null -ne $deviceKey) -and ($null -ne $AdvancedHuntingIndex) -and $AdvancedHuntingIndex.ContainsKey($deviceKey)) {
            foreach ($record in $AdvancedHuntingIndex[$deviceKey]) {
                $advancedHuntingRecords += $record
            }
        }
    }

    $defenderApiData = $null
    $advancedHuntingDefenderData = $null
    if ($Settings.DefenderCheckInAttributeNumber -gt 0) {
        $defenderApiData = Get-DefenderMachineCheckInData -Device $Device -MachineIndex $MachineIndex -StaleAfterDays $Settings.DisableAfterDays -ReferenceTime $ReferenceTime
        $advancedHuntingDefenderData = Get-DefenderCheckInData -Device $Device -AdvancedHuntingRecords $advancedHuntingRecords -StaleAfterDays $Settings.DisableAfterDays -ReferenceTime $ReferenceTime
        $defenderData = if ($defenderApiData.SourceFound) { $defenderApiData } elseif ($advancedHuntingDefenderData.SourceFound) { $advancedHuntingDefenderData } else { $defenderApiData }
    }

    $effectiveHeartbeat = Get-EffectiveHeartbeat `
        -ReferenceTime $ReferenceTime `
        -StaleAfterDays $Settings.DisableAfterDays `
        -EntraTimestamp $Device.approximateLastSignInDateTime `
        -IntuneData $intuneData `
        -DefenderData $defenderData `
        -AdvancedHuntingRecords $advancedHuntingRecords

    return [pscustomobject]@{
        Intune = $intuneData
        DefenderForEndpoint = $defenderData
        AdvancedHuntingRecords = $advancedHuntingRecords
        EffectiveHeartbeat = $effectiveHeartbeat
    }
}

function Decode-LapsPassword {
    param(
        [Parameter(Mandatory = $true)]
        [string] $PasswordBase64
    )

    $bytes = [Convert]::FromBase64String($PasswordBase64)
    return [Text.Encoding]::Unicode.GetString($bytes)
}

function Get-LapsArchive {
    param(
        [Parameter(Mandatory = $true)]
        [string] $EntraObjectId
    )

    $uri = "https://graph.microsoft.com/v1.0/directory/deviceLocalCredentials/$EntraObjectId?`$select=credentials"

    try {
        $raw = Get-GraphObject -Uri $uri
    }
    catch {
        $statusCode = Get-HttpStatusCode -ErrorRecord $_
        if ($statusCode -eq 404) {
            return $null
        }

        throw
    }

    if ($null -eq $raw) {
        return $null
    }

    $credentials = @()
    foreach ($entry in @($raw.credentials)) {
        $credentials += [ordered]@{
            accountName = $entry.accountName
            accountSid = $entry.accountSid
            backupDateTime = $entry.backupDateTime
            password = Decode-LapsPassword -PasswordBase64 $entry.passwordBase64
        }
    }

    if ($credentials.Count -eq 0) {
        return $null
    }

    return [ordered]@{
        deviceName = $raw.deviceName
        lastBackupDateTime = $raw.lastBackupDateTime
        refreshDateTime = $raw.refreshDateTime
        credentials = $credentials
    }
}

function Get-BitLockerArchive {
    param(
        [AllowNull()]
        [string] $DeviceId
    )

    if ([string]::IsNullOrWhiteSpace($DeviceId)) {
        return @()
    }

    $filter = [Uri]::EscapeDataString("deviceId eq '$DeviceId'")
    $listUri = "https://graph.microsoft.com/v1.0/informationProtection/bitlocker/recoveryKeys?`$filter=$filter"
    $rawKeys = @(Get-GraphCollection -Uri $listUri)

    if ($rawKeys.Count -eq 0) {
        return @()
    }

    $bitlockerKeys = @()
    foreach ($rawKey in $rawKeys) {
        $keyUri = "https://graph.microsoft.com/v1.0/informationProtection/bitlocker/recoveryKeys/$($rawKey.id)?`$select=key"
        $resolved = Get-GraphObject -Uri $keyUri

        $bitlockerKeys += [ordered]@{
            id = $rawKey.id
            deviceId = $rawKey.deviceId
            createdDateTime = $rawKey.createdDateTime
            volumeType = $rawKey.volumeType
            key = $resolved.key
        }
    }

    return $bitlockerKeys
}

function Normalize-SecretNameSegment {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Value
    )

    $normalized = $Value.ToLowerInvariant() -replace '[^a-z0-9-]', '-'
    $normalized = $normalized -replace '-{2,}', '-'
    $normalized = $normalized.Trim('-')

    if ([string]::IsNullOrWhiteSpace($normalized)) {
        return 'device'
    }

    return $normalized
}

function New-ArchiveSecretName {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Prefix,
        [Parameter(Mandatory = $true)]
        [string] $DisplayName,
        [Parameter(Mandatory = $true)]
        [string] $EntraObjectId
    )

    $normalizedPrefix = Normalize-SecretNameSegment -Value $Prefix
    $normalizedDisplayName = Normalize-SecretNameSegment -Value $DisplayName
    $reservedLength = $normalizedPrefix.Length + $EntraObjectId.Length + 2
    $maxDisplayLength = 127 - $reservedLength

    if ($maxDisplayLength -lt 1) {
        throw "Secret prefix '$Prefix' is too long to build a valid Key Vault secret name."
    }

    if ($normalizedDisplayName.Length -gt $maxDisplayLength) {
        $normalizedDisplayName = $normalizedDisplayName.Substring(0, $maxDisplayLength).Trim('-')
        if ([string]::IsNullOrWhiteSpace($normalizedDisplayName)) {
            $normalizedDisplayName = 'device'
        }
    }

    return "$normalizedPrefix-$normalizedDisplayName-$EntraObjectId"
}

function Limit-TagValue {
    param(
        [AllowNull()]
        [object] $Value
    )

    if ($null -eq $Value) {
        return $null
    }

    $stringValue = [string] $Value
    if ([string]::IsNullOrWhiteSpace($stringValue)) {
        return $null
    }

    if ($stringValue.Length -le 256) {
        return $stringValue
    }

    return $stringValue.Substring(0, 256)
}

function Build-ArchivePayload {
    param(
        [Parameter(Mandatory = $true)]
        [object] $Device,
        [Parameter(Mandatory = $true)]
        [string] $ArchivedAt,
        [Parameter(Mandatory = $true)]
        [string] $CleanupRunId,
        [AllowNull()]
        [object] $Candidate,
        [AllowNull()]
        [object] $CheckInData,
        [AllowNull()]
        [object] $LapsArchive,
        [Parameter(Mandatory = $true)]
        [object[]] $BitLockerArchive
    )

    return [ordered]@{
        schemaVersion = '1.1'
        archivedAt = $ArchivedAt
        cleanupContext = if ($null -eq $Candidate) {
            [ordered]@{
                cleanupRunId = $CleanupRunId
                action = 'Delete'
            }
        }
        else {
            [ordered]@{
                cleanupRunId = $CleanupRunId
                action = $Candidate.Action
                inactiveDays = $Candidate.InactiveDays
                effectiveHeartbeatSource = $Candidate.HeartbeatSource
                effectiveHeartbeatTimestamp = $Candidate.HeartbeatTimestamp
            }
        }
        sources = [ordered]@{
            entra = $true
            intune = $null -ne $CheckInData -and $null -ne $CheckInData.Intune -and $CheckInData.Intune.SourceFound
            defenderForEndpoint = $null -ne $CheckInData -and $null -ne $CheckInData.DefenderForEndpoint -and $CheckInData.DefenderForEndpoint.SourceFound
        }
        device = [ordered]@{
            entraObjectId = $Device.id
            deviceId = $Device.deviceId
            displayName = $Device.displayName
            accountEnabled = $Device.accountEnabled
            operatingSystem = $Device.operatingSystem
            operatingSystemVersion = $Device.operatingSystemVersion
            trustType = $Device.trustType
            approximateLastSignInDateTime = $Device.approximateLastSignInDateTime
            serialNumber = if ($null -eq $CheckInData -or $null -eq $CheckInData.Intune) { $null } else { $CheckInData.Intune.SerialNumber }
        }
        intune = if ($null -eq $CheckInData -or $null -eq $CheckInData.Intune) {
            $null
        }
        else {
            [ordered]@{
                state = $CheckInData.Intune.State
                lastSyncDateTime = $CheckInData.Intune.LastCheckIn
                managedDeviceId = $CheckInData.Intune.ManagedDeviceId
                deviceName = $CheckInData.Intune.DeviceName
                serialNumber = $CheckInData.Intune.SerialNumber
                extensionAttributeValue = $CheckInData.Intune.AttributeValue
            }
        }
        defenderForEndpoint = if ($null -eq $CheckInData -or $null -eq $CheckInData.DefenderForEndpoint) {
            $null
        }
        else {
            [ordered]@{
                state = $CheckInData.DefenderForEndpoint.State
                lastSeen = $CheckInData.DefenderForEndpoint.LastCheckIn
                machineId = $CheckInData.DefenderForEndpoint.MachineId
                deviceName = $CheckInData.DefenderForEndpoint.DeviceName
                sensorHealthState = $CheckInData.DefenderForEndpoint.SensorHealthState
                onboardingStatus = $CheckInData.DefenderForEndpoint.OnboardingStatus
                extensionAttributeValue = $CheckInData.DefenderForEndpoint.AttributeValue
            }
        }
        heartbeats = if ($null -eq $CheckInData) {
            $null
        }
        else {
            [ordered]@{
                effective = [ordered]@{
                    state = $CheckInData.EffectiveHeartbeat.State
                    timestamp = $CheckInData.EffectiveHeartbeat.Timestamp
                    source = $CheckInData.EffectiveHeartbeat.Source
                    inactiveDays = $CheckInData.EffectiveHeartbeat.InactiveDays
                }
                entra = [ordered]@{
                    timestamp = Get-NormalizedTimestamp -Value $Device.approximateLastSignInDateTime
                }
                intune = if ($null -eq $CheckInData.Intune) {
                    $null
                }
                else {
                    [ordered]@{
                        timestamp = $CheckInData.Intune.LastCheckIn
                        state = $CheckInData.Intune.State
                        sourceFound = $CheckInData.Intune.SourceFound
                    }
                }
                defenderForEndpoint = if ($null -eq $CheckInData.DefenderForEndpoint) {
                    $null
                }
                else {
                    [ordered]@{
                        timestamp = $CheckInData.DefenderForEndpoint.LastCheckIn
                        state = $CheckInData.DefenderForEndpoint.State
                        sourceFound = $CheckInData.DefenderForEndpoint.SourceFound
                    }
                }
                advancedHunting = @($CheckInData.AdvancedHuntingRecords | ForEach-Object {
                        [ordered]@{
                            sourceTable = $_.SourceTable
                            timestamp = $_.HeartbeatTimestamp
                            deviceName = $_.DeviceName
                            record = $_.Record
                        }
                    })
            }
        }
        laps = $LapsArchive
        bitlocker = $BitLockerArchive
    }
}

function Set-KeyVaultArchiveSecret {
    param(
        [Parameter(Mandatory = $true)]
        [string] $VaultName,
        [Parameter(Mandatory = $true)]
        [string] $SecretName,
        [Parameter(Mandatory = $true)]
        [object] $Payload,
        [Parameter(Mandatory = $true)]
        [hashtable] $Tags
    )

    $json = $Payload | ConvertTo-Json -Depth 20 -Compress
    $payloadSize = [Text.Encoding]::UTF8.GetByteCount($json)
    if ($payloadSize -gt 24000) {
        throw "Archive payload for secret '$SecretName' is too large for Azure Key Vault secret storage."
    }

    $uri = "https://$VaultName.vault.azure.net/secrets/$SecretName?api-version=7.4"
    $token = Get-ManagedIdentityToken -ResourceUrl $script:KeyVaultResourceUrl
    $body = @{
        value = $json
        contentType = 'application/json'
        tags = $Tags
    }

    Invoke-JsonRestMethod -Method 'PUT' -Uri $uri -AccessToken $token -Body $body | Out-Null
}

function Remove-EntraDevice {
    param(
        [Parameter(Mandatory = $true)]
        [string] $EntraObjectId
    )

    $uri = "https://graph.microsoft.com/v1.0/devices/$EntraObjectId"
    $token = Get-ManagedIdentityToken -ResourceUrl $script:GraphResourceUrl
    Invoke-JsonRestMethod -Method 'DELETE' -Uri $uri -AccessToken $token | Out-Null
}

function Disable-EntraDevice {
    param(
        [Parameter(Mandatory = $true)]
        [string] $EntraObjectId
    )

    $uri = "https://graph.microsoft.com/v1.0/devices/$EntraObjectId"
    $token = Get-ManagedIdentityToken -ResourceUrl $script:GraphResourceUrl
    Invoke-JsonRestMethod -Method 'PATCH' -Uri $uri -AccessToken $token -Body @{ accountEnabled = $false } | Out-Null
}

function Set-DeviceExtensionAttributes {
    param(
        [Parameter(Mandatory = $true)]
        [string] $EntraObjectId,
        [Parameter(Mandatory = $true)]
        [hashtable] $ExtensionAttributes
    )

    if ($ExtensionAttributes.Count -eq 0) {
        return
    }

    $uri = "https://graph.microsoft.com/v1.0/devices/$EntraObjectId"
    $token = Get-ManagedIdentityToken -ResourceUrl $script:GraphResourceUrl
    Invoke-JsonRestMethod -Method 'PATCH' -Uri $uri -AccessToken $token -Body @{ extensionAttributes = $ExtensionAttributes } | Out-Null
}

function Get-DeviceCleanupSettings {
    $resolvedKeyVaultName = Get-RequiredInput -Name 'KeyVaultName' -Value $KeyVaultName
    $resolvedSecretNamePrefix = Get-RequiredInput -Name 'SecretNamePrefix' -Value $SecretNamePrefix
    $resolvedExcludedDeviceGroupId = Get-OptionalConfiguredInput -Value $ExcludedDeviceGroupId

    $resolvedDisableAfterDays = Get-IntegerInput -Name 'DisableAfterDays' -Value $DisableAfterDays
    $resolvedDeleteAfterDays = Get-IntegerInput -Name 'DeleteAfterDays' -Value $DeleteAfterDays
    if ($resolvedDeleteAfterDays -le $resolvedDisableAfterDays) {
        throw "DeleteAfterDays must be greater than DisableAfterDays. Current values: disable=$resolvedDisableAfterDays, delete=$resolvedDeleteAfterDays."
    }

    $resolvedIntuneAttributeNumber = Get-ExtensionAttributeNumberInput -Name 'IntuneCheckInAttributeNumber' -Value $IntuneCheckInAttributeNumber
    $resolvedDefenderAttributeNumber = Get-ExtensionAttributeNumberInput -Name 'DefenderCheckInAttributeNumber' -Value $DefenderCheckInAttributeNumber
    if (($resolvedIntuneAttributeNumber -gt 0) -and ($resolvedIntuneAttributeNumber -eq $resolvedDefenderAttributeNumber)) {
        throw "IntuneCheckInAttributeNumber and DefenderCheckInAttributeNumber must be different when both are enabled. Current value: $resolvedIntuneAttributeNumber."
    }

    $resolvedAdvancedHuntingEnabled = Get-BooleanInput -Name 'AdvancedHuntingEnabled' -Value $AdvancedHuntingEnabled
    $resolvedAdvancedHuntingLookbackDays = Get-IntegerInput -Name 'AdvancedHuntingLookbackDays' -Value $AdvancedHuntingLookbackDays
    if (($resolvedAdvancedHuntingLookbackDays -lt 1) -or ($resolvedAdvancedHuntingLookbackDays -gt 30)) {
        throw "AdvancedHuntingLookbackDays must be between 1 and 30 because Microsoft Defender advanced hunting data is limited to a 30-day window. Current value: $resolvedAdvancedHuntingLookbackDays."
    }

    $resolvedNotificationsEnabled = $false
    $notificationsEnabledInput = Get-OptionalConfiguredInput -Value $NotificationsEnabled
    if (-not [string]::IsNullOrWhiteSpace($notificationsEnabledInput)) {
        $resolvedNotificationsEnabled = Get-BooleanInput -Name 'NotificationsEnabled' -Value $notificationsEnabledInput
    }

    $resolvedNotifyOnSuccess = $true
    $notifyOnSuccessInput = Get-OptionalConfiguredInput -Value $NotifyOnSuccess
    if (-not [string]::IsNullOrWhiteSpace($notifyOnSuccessInput)) {
        $resolvedNotifyOnSuccess = Get-BooleanInput -Name 'NotifyOnSuccess' -Value $notifyOnSuccessInput
    }

    $resolvedNotifyOnFailure = $true
    $notifyOnFailureInput = Get-OptionalConfiguredInput -Value $NotifyOnFailure
    if (-not [string]::IsNullOrWhiteSpace($notifyOnFailureInput)) {
        $resolvedNotifyOnFailure = Get-BooleanInput -Name 'NotifyOnFailure' -Value $notifyOnFailureInput
    }

    $resolvedNotifyOnNoAction = $false
    $notifyOnNoActionInput = Get-OptionalConfiguredInput -Value $NotifyOnNoAction
    if (-not [string]::IsNullOrWhiteSpace($notifyOnNoActionInput)) {
        $resolvedNotifyOnNoAction = Get-BooleanInput -Name 'NotifyOnNoAction' -Value $notifyOnNoActionInput
    }

    $resolvedNotificationCallbackUrl = Get-OptionalConfiguredInput -Value $NotificationCallbackUrl
    $resolvedEnvironmentName = Get-OptionalConfiguredInput -Value $EnvironmentName
    $resolvedSubscriptionId = Get-OptionalConfiguredInput -Value $SubscriptionId
    $resolvedResourceGroupName = Get-OptionalConfiguredInput -Value $ResourceGroupName
    $resolvedAutomationAccountName = Get-OptionalConfiguredInput -Value $AutomationAccountName
    $resolvedAutomationRunbookName = Get-OptionalConfiguredInput -Value $AutomationRunbookName

    return [ordered]@{
        VaultName = $resolvedKeyVaultName
        SecretPrefix = $resolvedSecretNamePrefix
        ExclusionGroupId = $resolvedExcludedDeviceGroupId
        DisableAfterDays = $resolvedDisableAfterDays
        DeleteAfterDays = $resolvedDeleteAfterDays
        MaxDeleteCount = Get-IntegerInput -Name 'MaxDeleteCount' -Value $MaxDeleteCount
        DisableEnabled = Get-BooleanInput -Name 'DisableEnabled' -Value $DisableEnabled
        DeleteEnabled = Get-BooleanInput -Name 'DeleteEnabled' -Value $DeleteEnabled
        IntuneCheckInAttributeNumber = $resolvedIntuneAttributeNumber
        IntuneCheckInAttributeName = if ($resolvedIntuneAttributeNumber -gt 0) { Get-ExtensionAttributeName -Number $resolvedIntuneAttributeNumber } else { $null }
        DefenderCheckInAttributeNumber = $resolvedDefenderAttributeNumber
        DefenderCheckInAttributeName = if ($resolvedDefenderAttributeNumber -gt 0) { Get-ExtensionAttributeName -Number $resolvedDefenderAttributeNumber } else { $null }
        AdvancedHuntingEnabled = $resolvedAdvancedHuntingEnabled
        AdvancedHuntingLookbackDays = $resolvedAdvancedHuntingLookbackDays
        NotificationsEnabled = $resolvedNotificationsEnabled
        NotificationCallbackUrl = $resolvedNotificationCallbackUrl
        NotifyOnSuccess = $resolvedNotifyOnSuccess
        NotifyOnFailure = $resolvedNotifyOnFailure
        NotifyOnNoAction = $resolvedNotifyOnNoAction
        EnvironmentName = if ([string]::IsNullOrWhiteSpace($resolvedEnvironmentName)) { 'unknown' } else { $resolvedEnvironmentName }
        SubscriptionId = $resolvedSubscriptionId
        ResourceGroupName = $resolvedResourceGroupName
        AutomationAccountName = $resolvedAutomationAccountName
        AutomationRunbookName = if ([string]::IsNullOrWhiteSpace($resolvedAutomationRunbookName)) { 'DeviceCleanup' } else { $resolvedAutomationRunbookName }
    }
}

function New-DeviceCleanupActionRecord {
    param(
        [Parameter(Mandatory = $true)]
        [object] $Device,
        [Parameter(Mandatory = $true)]
        [object] $Candidate,
        [Parameter(Mandatory = $true)]
        [string] $Mode,
        [AllowNull()]
        [object] $ArchiveResult
    )

    $displayName = if ([string]::IsNullOrWhiteSpace($Device.displayName)) { '<unnamed-device>' } else { $Device.displayName }
    $record = [ordered]@{
        displayName = $displayName
        entraObjectId = $Device.id
        deviceId = $Device.deviceId
        cleanupRunId = $null
        action = $Candidate.Action
        mode = $Mode
        inactiveDays = $Candidate.InactiveDays
        effectiveHeartbeatSource = $Candidate.HeartbeatSource
        effectiveHeartbeatTimestamp = $Candidate.HeartbeatTimestamp
    }

    if ($null -ne $ArchiveResult) {
        $record.cleanupRunId = $ArchiveResult.CleanupRunId
        $record.secretName = $ArchiveResult.SecretName
        $record.lapsCredentialCount = $ArchiveResult.LapsCredentialCount
        $record.bitLockerKeyCount = $ArchiveResult.BitLockerKeyCount
    }

    return [pscustomobject] $record
}

function Invoke-NotificationCallback {
    param(
        [Parameter(Mandatory = $true)]
        [string] $Uri,
        [Parameter(Mandatory = $true)]
        [object] $Payload
    )

    $body = $Payload | ConvertTo-Json -Depth 20 -Compress
    for ($attempt = 1; $attempt -le 3; $attempt++) {
        try {
            Invoke-RestMethod -Method 'POST' -Uri $Uri -Headers @{
                'Content-Type' = 'application/json'
                'User-Agent' = 'azd-device-cleanup/0.1.0'
            } -Body $body -ErrorAction Stop | Out-Null

            return
        }
        catch {
            if ($attempt -ge 3) {
                throw
            }

            Start-Sleep -Seconds ([int] [math]::Pow(2, $attempt - 1))
        }
    }
}

function Invoke-DeviceCleanupNotification {
    param(
        [Parameter(Mandatory = $true)]
        [object] $Settings,
        [Parameter(Mandatory = $true)]
        [object] $Summary
    )

    if (-not $Settings.NotificationsEnabled) {
        return
    }

    $sendNotification = switch ($Summary.status) {
        'Failed' { $Settings.NotifyOnFailure }
        'PartiallySucceeded' { $Settings.NotifyOnFailure }
        'NoAction' { $Settings.NotifyOnNoAction }
        default { $Settings.NotifyOnSuccess }
    }

    if (-not $sendNotification) {
        Write-Host "Skipping cleanup notification for status '$($Summary.status)' because that notification class is disabled."
        return
    }

    if ([string]::IsNullOrWhiteSpace($Settings.NotificationCallbackUrl)) {
        Write-Warning "Cleanup notifications are enabled, but NotificationCallbackUrl is empty. Skipping notification delivery."
        return
    }

    try {
        Invoke-NotificationCallback -Uri $Settings.NotificationCallbackUrl -Payload $Summary
        Write-Output "Sent Logic App notification for cleanup status '$($Summary.status)'."
    }
    catch {
        Write-Warning "Failed to send Logic App notification for cleanup status '$($Summary.status)'. Error: $($_.Exception.Message)"
    }
}

function Get-DeviceLifecycleAction {
    param(
        [Parameter(Mandatory = $true)]
        [object] $Device,
        [Parameter(Mandatory = $true)]
        [object] $CheckInData,
        [Parameter(Mandatory = $true)]
        [object] $Settings,
        [Parameter(Mandatory = $true)]
        [datetime] $ReferenceTime
    )

    $inactiveDays = $CheckInData.EffectiveHeartbeat.InactiveDays
    if ($null -eq $inactiveDays) {
        return $null
    }

    if (($inactiveDays -ge $Settings.DeleteAfterDays) -and (-not $Device.accountEnabled)) {
        return [pscustomobject]@{
            Action = 'Delete'
            InactiveDays = $inactiveDays
            HeartbeatSource = $CheckInData.EffectiveHeartbeat.Source
            HeartbeatTimestamp = $CheckInData.EffectiveHeartbeat.Timestamp
        }
    }

    if (($inactiveDays -ge $Settings.DisableAfterDays) -and $Device.accountEnabled) {
        return [pscustomobject]@{
            Action = 'Disable'
            InactiveDays = $inactiveDays
            HeartbeatSource = $CheckInData.EffectiveHeartbeat.Source
            HeartbeatTimestamp = $CheckInData.EffectiveHeartbeat.Timestamp
        }
    }

    return $null
}

function Sync-DeviceCheckInAttributes {
    param(
        [Parameter(Mandatory = $true)]
        [object[]] $Devices,
        [Parameter(Mandatory = $true)]
        [object] $Settings,
        [Parameter(Mandatory = $true)]
        [datetime] $ReferenceTime,
        [AllowNull()]
        [hashtable] $ManagedDeviceIndex,
        [AllowNull()]
        [hashtable] $MachineIndex,
        [bool] $DefenderApiAvailable = $true,
        [bool] $AdvancedHuntingAvailable = $true,
        [AllowNull()]
        [hashtable] $AdvancedHuntingIndex
    )

    if (($Settings.IntuneCheckInAttributeNumber -le 0) -and ($Settings.DefenderCheckInAttributeNumber -le 0)) {
        return [pscustomobject]@{
            UpdatedCount = 0
            DeviceCount = $Devices.Count
        }
    }

    $updatedCount = 0
    $restrictedManagementUnitSkippedCount = 0
    foreach ($device in $Devices) {
        $displayName = if ([string]::IsNullOrWhiteSpace($device.displayName)) { '<unnamed-device>' } else { $device.displayName }
        $checkInData = $null
        try {
            $checkInData = Get-DeviceCheckInData -Device $device -Settings $Settings -ReferenceTime $ReferenceTime -ManagedDeviceIndex $ManagedDeviceIndex -MachineIndex $MachineIndex -AdvancedHuntingIndex $AdvancedHuntingIndex
        }
        catch {
            $message = "Failed to evaluate device '$displayName' ($($device.id)) during extension-attribute sync. $($_.Exception.Message)"
            if (-not [string]::IsNullOrWhiteSpace($_.ScriptStackTrace)) {
                $message = "$message Stack: $($_.ScriptStackTrace)"
            }

            throw $message
        }

        $updates = @{}

        if ($Settings.IntuneCheckInAttributeNumber -gt 0) {
            $existingIntuneValue = $null
            if ($null -ne $device.extensionAttributes) {
                $existingIntuneValue = $device.extensionAttributes.($Settings.IntuneCheckInAttributeName)
            }

            if ($existingIntuneValue -ne $checkInData.Intune.AttributeValue) {
                $updates[$Settings.IntuneCheckInAttributeName] = $checkInData.Intune.AttributeValue
            }
        }

        $defenderHeartbeatAvailable = ($Settings.DefenderCheckInAttributeNumber -le 0) -or $DefenderApiAvailable -or (($Settings.AdvancedHuntingEnabled) -and $AdvancedHuntingAvailable)
        if (($Settings.DefenderCheckInAttributeNumber -gt 0) -and $defenderHeartbeatAvailable) {
            $existingDefenderValue = $null
            if ($null -ne $device.extensionAttributes) {
                $existingDefenderValue = $device.extensionAttributes.($Settings.DefenderCheckInAttributeName)
            }

            if ($existingDefenderValue -ne $checkInData.DefenderForEndpoint.AttributeValue) {
                $updates[$Settings.DefenderCheckInAttributeName] = $checkInData.DefenderForEndpoint.AttributeValue
            }
        }

        if ($updates.Count -eq 0) {
            continue
        }

        Write-Host "Updating extension attributes for '$displayName' ($($device.id))."
        try {
            Set-DeviceExtensionAttributes -EntraObjectId $device.id -ExtensionAttributes $updates
        }
        catch {
            if (Test-IsRestrictedManagementAdministrativeUnitError -ErrorRecord $_) {
                Write-Host "Skipping extension attribute update for '$displayName' ($($device.id)) because it is in a restricted management administrative unit."
                $restrictedManagementUnitSkippedCount++
                continue
            }

            throw
        }

        if ($null -eq $device.extensionAttributes) {
            $device | Add-Member -NotePropertyName extensionAttributes -NotePropertyValue ([pscustomobject]@{}) -Force
        }

        foreach ($attributeName in $updates.Keys) {
            $device.extensionAttributes | Add-Member -NotePropertyName $attributeName -NotePropertyValue $updates[$attributeName] -Force
        }

        $updatedCount++
    }

    return [pscustomobject]@{
        UpdatedCount = $updatedCount
        DeviceCount = $Devices.Count
        RestrictedManagementUnitSkippedCount = $restrictedManagementUnitSkippedCount
    }
}

function Save-DeviceArchive {
    param(
        [Parameter(Mandatory = $true)]
        [object] $Device,
        [Parameter(Mandatory = $true)]
        [object] $Settings,
        [Parameter(Mandatory = $true)]
        [string] $CleanupRunId,
        [AllowNull()]
        [object] $Candidate,
        [AllowNull()]
        [object] $CheckInData
    )

    $secretDisplayName = if ([string]::IsNullOrWhiteSpace($Device.displayName)) { 'unnamed-device' } else { $Device.displayName }
    $lapsArchive = Get-LapsArchive -EntraObjectId $Device.id
    $bitLockerArchive = @(Get-BitLockerArchive -DeviceId $Device.deviceId)
    $archivedAt = (Get-Date).ToUniversalTime().ToString('o')
    $payload = Build-ArchivePayload -Device $Device -ArchivedAt $archivedAt -CleanupRunId $CleanupRunId -Candidate $Candidate -CheckInData $CheckInData -LapsArchive $lapsArchive -BitLockerArchive $bitLockerArchive
    $secretName = New-ArchiveSecretName -Prefix $Settings.SecretPrefix -DisplayName $secretDisplayName -EntraObjectId $Device.id
    $tags = @{}

    foreach ($entry in @(
            @{ Key = 'displayName'; Value = $Device.displayName },
            @{ Key = 'deviceId'; Value = $Device.deviceId },
            @{ Key = 'entraObjectId'; Value = $Device.id },
            @{ Key = 'archivedAt'; Value = $archivedAt },
            @{ Key = 'cleanupSource'; Value = 'entra' },
            @{ Key = 'cleanupAction'; Value = if ($null -eq $Candidate) { 'Delete' } else { $Candidate.Action } },
            @{ Key = 'cleanupRunId'; Value = $CleanupRunId },
            @{ Key = 'effectiveHeartbeatSource'; Value = if ($null -eq $Candidate) { $null } else { $Candidate.HeartbeatSource } },
            @{ Key = 'effectiveHeartbeatTimestamp'; Value = if ($null -eq $Candidate) { $null } else { $Candidate.HeartbeatTimestamp } },
            @{ Key = 'serialNumber'; Value = $payload.device.serialNumber },
            @{ Key = 'intuneManagedDeviceId'; Value = if ($null -eq $payload.intune) { $null } else { $payload.intune.managedDeviceId } },
            @{ Key = 'defenderMachineId'; Value = if ($null -eq $payload.defenderForEndpoint) { $null } else { $payload.defenderForEndpoint.machineId } },
            @{ Key = 'lastSeenEntra'; Value = if ($null -eq $payload.heartbeats) { $null } else { $payload.heartbeats.entra.timestamp } },
            @{ Key = 'lastSeenIntune'; Value = if ($null -eq $payload.heartbeats -or $null -eq $payload.heartbeats.intune) { $null } else { $payload.heartbeats.intune.timestamp } },
            @{ Key = 'lastSeenDefender'; Value = if ($null -eq $payload.heartbeats -or $null -eq $payload.heartbeats.defenderForEndpoint) { $null } else { $payload.heartbeats.defenderForEndpoint.timestamp } }
        )) {
        $tagValue = Limit-TagValue -Value $entry.Value
        if ($null -ne $tagValue) {
            $tags[$entry.Key] = $tagValue
        }
    }

    Set-KeyVaultArchiveSecret -VaultName $Settings.VaultName -SecretName $secretName -Payload $payload -Tags $tags

    return [pscustomobject]@{
        CleanupRunId = $CleanupRunId
        SecretName = $secretName
        LapsCredentialCount = if ($null -eq $lapsArchive) { 0 } else { @($lapsArchive.credentials).Count }
        BitLockerKeyCount = $bitLockerArchive.Count
    }
}

function Invoke-DeviceCleanupJob {
    $settings = Get-DeviceCleanupSettings
    $nowUtc = (Get-Date).ToUniversalTime()
    $cleanupRunId = [guid]::NewGuid().ToString()
    $disableCutoffDate = $nowUtc.AddDays(-$settings.DisableAfterDays)
    $deleteCutoffDate = $nowUtc.AddDays(-$settings.DeleteAfterDays)
    $managedDeviceIndex = $null
    $machineIndex = $null
    $defenderApiAvailable = -not ($settings.DefenderCheckInAttributeNumber -gt 0)
    $advancedHuntingIndex = $null
    $advancedHuntingAvailable = -not $settings.AdvancedHuntingEnabled
    $excludedDeviceIdSet = $null
    $excludedLifecycleDeviceCount = 0
    $summary = [ordered]@{
        environmentName = $settings.EnvironmentName
        subscriptionId = $settings.SubscriptionId
        resourceGroupName = $settings.ResourceGroupName
        automationAccountName = $settings.AutomationAccountName
        runbookName = $settings.AutomationRunbookName
        cleanupRunId = $cleanupRunId
        startedAtUtc = $nowUtc.ToString('o')
        finishedAtUtc = $null
        status = 'Running'
        severity = 'Informational'
        summaryText = ''
        settings = [ordered]@{
            disableEnabled = $settings.DisableEnabled
            deleteEnabled = $settings.DeleteEnabled
            disableAfterDays = $settings.DisableAfterDays
            deleteAfterDays = $settings.DeleteAfterDays
            maxDeleteCount = $settings.MaxDeleteCount
            exclusionGroupId = $settings.ExclusionGroupId
            intuneCheckInAttributeNumber = $settings.IntuneCheckInAttributeNumber
            defenderCheckInAttributeNumber = $settings.DefenderCheckInAttributeNumber
            advancedHuntingEnabled = $settings.AdvancedHuntingEnabled
            advancedHuntingLookbackDays = $settings.AdvancedHuntingLookbackDays
        }
        advancedHunting = [ordered]@{
            enabled = $settings.AdvancedHuntingEnabled
            available = if ($settings.AdvancedHuntingEnabled) { $false } else { $true }
            failure = $null
        }
        defenderApi = [ordered]@{
            enabled = $settings.DefenderCheckInAttributeNumber -gt 0
            available = if ($settings.DefenderCheckInAttributeNumber -gt 0) { $false } else { $true }
            failure = $null
        }
        counts = [ordered]@{
            totalDevices = 0
            excludedDevices = 0
            intuneDefenderAttributeUpdates = 0
            restrictedManagementUnitSkipped = 0
            disableCandidates = 0
            deleteCandidates = 0
            disabledDevices = 0
            archivedDeletedDevices = 0
            dryRunDisableCandidates = 0
            dryRunDeleteCandidates = 0
            actionFailures = 0
        }
        results = [ordered]@{
            disabledDevices = @()
            archivedDeletedDevices = @()
            dryRunDisableDevices = @()
            dryRunDeleteDevices = @()
            failedActions = @()
        }
        failure = $null
    }

    try {
        Write-Output "Starting device cleanup run. CleanupRunId=$cleanupRunId; DisableEnabled=$($settings.DisableEnabled); DeleteEnabled=$($settings.DeleteEnabled); ExclusionGroupId=$($settings.ExclusionGroupId); DisableAfterDays=$($settings.DisableAfterDays); DeleteAfterDays=$($settings.DeleteAfterDays); MaxDeleteCount=$($settings.MaxDeleteCount); IntuneAttribute=$($settings.IntuneCheckInAttributeNumber); DefenderAttribute=$($settings.DefenderCheckInAttributeNumber); AdvancedHuntingEnabled=$($settings.AdvancedHuntingEnabled); AdvancedHuntingLookbackDays=$($settings.AdvancedHuntingLookbackDays); DisableCutoff=$($disableCutoffDate.ToString('o')); DeleteCutoff=$($deleteCutoffDate.ToString('o'))"

        $devices = @(Get-EntraDevices | Sort-Object -Property displayName, id)
        $summary.counts.totalDevices = $devices.Count
        if ($devices.Count -eq 0) {
            Write-Output 'No Entra devices were returned.'
            $summary.status = 'NoAction'
            $summary.summaryText = 'No Entra devices were returned.'
            $summary.finishedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
            Invoke-DeviceCleanupNotification -Settings $settings -Summary ([pscustomobject] $summary)
            return [pscustomobject] $summary
        }

        if ($null -ne $settings.ExclusionGroupId) {
            Write-Output "Loading excluded devices from group '$($settings.ExclusionGroupId)'."
            $excludedDeviceIdSet = Get-ExcludedDeviceIdSet -GroupId $settings.ExclusionGroupId
            Write-Output "Loaded $($excludedDeviceIdSet.Count) excluded device(s) from the configured exclusion group."
        }

        if ($settings.IntuneCheckInAttributeNumber -gt 0) {
            Write-Output 'Loading Intune managed device check-in data.'
            $managedDeviceIndex = New-IntuneManagedDeviceIndex -ManagedDevices @(Get-IntuneManagedDevices)
        }

        if ($settings.DefenderCheckInAttributeNumber -gt 0) {
            Write-Output 'Loading Defender for Endpoint machine check-in data.'
            try {
                $machineIndex = New-DefenderMachineIndex -Machines @(Get-DefenderMachines)
                $defenderApiAvailable = $true
                $summary.defenderApi.available = $true
                Write-Output "Loaded $($machineIndex.Count) Defender machine record(s)."
            }
            catch {
                $defenderApiAvailable = $false
                $summary.defenderApi.available = $false
                $summary.defenderApi.failure = $_.Exception.Message
                Write-Warning "Defender machine data could not be loaded for this run. Advanced hunting may provide a fallback heartbeat if enabled. Error: $($_.Exception.Message)"
            }
        }

        if ($settings.AdvancedHuntingEnabled) {
            Write-Output 'Loading Microsoft Graph advanced hunting data for Defender state and heartbeat signals.'
            try {
                $advancedHuntingRows = @(Get-AdvancedHuntingHeartbeatRows -LookbackDays $settings.AdvancedHuntingLookbackDays)
                $advancedHuntingIndex = New-AdvancedHuntingHeartbeatIndex -Rows $advancedHuntingRows
                $advancedHuntingAvailable = $true
                $summary.advancedHunting.available = $true
                Write-Output "Loaded $($advancedHuntingRows.Count) advanced hunting heartbeat row(s)."
            }
            catch {
                $advancedHuntingAvailable = $false
                $summary.advancedHunting.available = $false
                $summary.advancedHunting.failure = $_.Exception.Message
                Write-Warning "Advanced hunting heartbeat data could not be loaded for this run. The Defender machines API remains the primary source when available. Error: $($_.Exception.Message)"
            }
        }

        $syncResult = Sync-DeviceCheckInAttributes -Devices $devices -Settings $settings -ReferenceTime $nowUtc -ManagedDeviceIndex $managedDeviceIndex -MachineIndex $machineIndex -DefenderApiAvailable $defenderApiAvailable -AdvancedHuntingAvailable $advancedHuntingAvailable -AdvancedHuntingIndex $advancedHuntingIndex
        $summary.counts.intuneDefenderAttributeUpdates = $syncResult.UpdatedCount
        $summary.counts.restrictedManagementUnitSkipped = $syncResult.RestrictedManagementUnitSkippedCount
        if (($settings.IntuneCheckInAttributeNumber -gt 0) -or ($settings.DefenderCheckInAttributeNumber -gt 0)) {
            Write-Output "Updated extension attributes on $($syncResult.UpdatedCount) of $($syncResult.DeviceCount) device(s). RestrictedManagementUnitSkipped=$($syncResult.RestrictedManagementUnitSkippedCount)."
        }

        if (($settings.DefenderCheckInAttributeNumber -gt 0) -and (-not $defenderApiAvailable) -and ((-not $settings.AdvancedHuntingEnabled) -or (-not $advancedHuntingAvailable))) {
            Write-Warning 'Neither the Defender machines API nor the configured advanced hunting fallback was available. Skipping disable/delete actions for this run.'
            $summary.status = 'NoAction'
            $summary.severity = 'Warning'
            $summary.summaryText = 'Defender heartbeat data was unavailable from both the machines API and advanced hunting fallback, so the safety failsafe skipped disable/delete actions for this run.'
            $summary.finishedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
            Invoke-DeviceCleanupNotification -Settings $settings -Summary ([pscustomobject] $summary)
            return [pscustomobject] $summary
        }

        $candidates = @()
        foreach ($device in $devices) {
            $displayName = if ([string]::IsNullOrWhiteSpace($device.displayName)) { '<unnamed-device>' } else { $device.displayName }
            if (($null -ne $excludedDeviceIdSet) -and $excludedDeviceIdSet.ContainsKey($device.id.Trim().ToLowerInvariant())) {
                $excludedLifecycleDeviceCount++
                continue
            }

            try {
                $checkInData = Get-DeviceCheckInData -Device $device -Settings $settings -ReferenceTime $nowUtc -ManagedDeviceIndex $managedDeviceIndex -MachineIndex $machineIndex -AdvancedHuntingIndex $advancedHuntingIndex
            }
            catch {
                $message = "Failed to evaluate device '$displayName' ($($device.id)) during lifecycle selection. $($_.Exception.Message)"
                if (-not [string]::IsNullOrWhiteSpace($_.ScriptStackTrace)) {
                    $message = "$message Stack: $($_.ScriptStackTrace)"
                }

                throw $message
            }

            $lifecycle = Get-DeviceLifecycleAction -Device $device -CheckInData $checkInData -Settings $settings -ReferenceTime $nowUtc
            if ($null -eq $lifecycle) {
                continue
            }

            $candidates += [pscustomobject]@{
                Device = $device
                CheckInData = $checkInData
                Action = $lifecycle.Action
                InactiveDays = $lifecycle.InactiveDays
                HeartbeatSource = $lifecycle.HeartbeatSource
                HeartbeatTimestamp = $lifecycle.HeartbeatTimestamp
            }
        }

        $summary.counts.excludedDevices = $excludedLifecycleDeviceCount
        if ($excludedLifecycleDeviceCount -gt 0) {
            Write-Output "Excluded $excludedLifecycleDeviceCount device(s) from disable/delete evaluation via group '$($settings.ExclusionGroupId)'."
        }

        if ($candidates.Count -eq 0) {
            Write-Output 'No Entra devices require disable or delete actions.'
            $summary.status = 'NoAction'
            $summary.summaryText = 'No Entra devices require disable or delete actions.'
            $summary.finishedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
            Invoke-DeviceCleanupNotification -Settings $settings -Summary ([pscustomobject] $summary)
            return [pscustomobject] $summary
        }

        $disableCandidates = @($candidates | Where-Object Action -eq 'Disable' | Sort-Object -Property InactiveDays, @{ Expression = { $_.Device.displayName } }, @{ Expression = { $_.Device.id } })
        $deleteCandidates = @($candidates | Where-Object Action -eq 'Delete' | Sort-Object -Property InactiveDays, @{ Expression = { $_.Device.displayName } }, @{ Expression = { $_.Device.id } })
        $summary.counts.disableCandidates = $disableCandidates.Count
        $summary.counts.deleteCandidates = $deleteCandidates.Count

        if ($deleteCandidates.Count -gt $settings.MaxDeleteCount) {
            throw "Safety threshold reached. Found $($deleteCandidates.Count) delete candidates which exceeds the configured maximum of $($settings.MaxDeleteCount)."
        }

        Write-Output "Found $($disableCandidates.Count) disable candidate(s) and $($deleteCandidates.Count) delete candidate(s)."

        foreach ($candidate in $disableCandidates) {
            $device = $candidate.Device
            $displayName = if ([string]::IsNullOrWhiteSpace($device.displayName)) { '<unnamed-device>' } else { $device.displayName }

            if (-not $settings.DisableEnabled) {
                Write-Output "Dry run: would disable '$displayName' ($($device.id)) after $($candidate.InactiveDays) inactive day(s). EffectiveHeartbeat=$($candidate.HeartbeatSource)@$($candidate.HeartbeatTimestamp)"
                $summary.results.dryRunDisableDevices += @(New-DeviceCleanupActionRecord -Device $device -Candidate $candidate -Mode 'DryRun' -ArchiveResult $null)
                $summary.counts.dryRunDisableCandidates++
                continue
            }

            try {
                Write-Output "Disabling '$displayName' ($($device.id)) after $($candidate.InactiveDays) inactive day(s). EffectiveHeartbeat=$($candidate.HeartbeatSource)@$($candidate.HeartbeatTimestamp)"
                Disable-EntraDevice -EntraObjectId $device.id
                Write-Output "Disabled '$displayName' ($($device.id))."
                $summary.results.disabledDevices += @(New-DeviceCleanupActionRecord -Device $device -Candidate $candidate -Mode 'Executed' -ArchiveResult $null)
                $summary.counts.disabledDevices++
            }
            catch {
                $isRestricted = Test-IsRestrictedManagementAdministrativeUnitError -ErrorRecord $_
                $reason = if ($isRestricted) { 'RestrictedManagementAdministrativeUnit' } else { 'ActionFailed' }
                Write-Warning "Failed to disable '$displayName' ($($device.id)); continuing with remaining candidates. Reason=$reason; Error=$($_.Exception.Message)"
                $summary.results.failedActions += @([pscustomobject]@{
                        displayName = $displayName
                        entraObjectId = $device.id
                        deviceId = $device.deviceId
                        action = 'Disable'
                        reason = $reason
                        message = $_.Exception.Message
                    })
                $summary.counts.actionFailures++
            }
        }

        foreach ($candidate in $deleteCandidates) {
            $device = $candidate.Device
            $displayName = if ([string]::IsNullOrWhiteSpace($device.displayName)) { '<unnamed-device>' } else { $device.displayName }
            $checkInData = $candidate.CheckInData

            if (-not $settings.DeleteEnabled) {
                $plannedSecretName = New-ArchiveSecretName -Prefix $settings.SecretPrefix -DisplayName $displayName -EntraObjectId $device.id
                Write-Output "Dry run: would archive and delete '$displayName' ($($device.id)) after $($candidate.InactiveDays) inactive day(s) using secret '$plannedSecretName'. EffectiveHeartbeat=$($candidate.HeartbeatSource)@$($candidate.HeartbeatTimestamp)"
                $dryRunRecord = New-DeviceCleanupActionRecord -Device $device -Candidate $candidate -Mode 'DryRun' -ArchiveResult ([pscustomobject]@{
                        SecretName = $plannedSecretName
                        LapsCredentialCount = 0
                        BitLockerKeyCount = 0
                    })
                $summary.results.dryRunDeleteDevices += @($dryRunRecord)
                $summary.counts.dryRunDeleteCandidates++
                continue
            }

            $archiveResult = $null
            $failedPhase = 'Archive'
            try {
                Write-Output "Archiving '$displayName' ($($device.id)) before deletion after $($candidate.InactiveDays) inactive day(s). EffectiveHeartbeat=$($candidate.HeartbeatSource)@$($candidate.HeartbeatTimestamp)"
                $archiveResult = Save-DeviceArchive -Device $device -Settings $settings -CleanupRunId $cleanupRunId -Candidate $candidate -CheckInData $checkInData
                $failedPhase = 'Delete'
                Remove-EntraDevice -EntraObjectId $device.id
                Write-Output "Archived and deleted '$displayName'. Secret=$($archiveResult.SecretName); LAPS=$($archiveResult.LapsCredentialCount); BitLockerKeys=$($archiveResult.BitLockerKeyCount)"
                $summary.results.archivedDeletedDevices += @(New-DeviceCleanupActionRecord -Device $device -Candidate $candidate -Mode 'Executed' -ArchiveResult $archiveResult)
                $summary.counts.archivedDeletedDevices++
            }
            catch {
                $isRestricted = Test-IsRestrictedManagementAdministrativeUnitError -ErrorRecord $_
                $reason = if ($isRestricted) { 'RestrictedManagementAdministrativeUnit' } else { "${failedPhase}Failed" }
                Write-Warning "Failed during $failedPhase for '$displayName' ($($device.id)); continuing with remaining candidates. Reason=$reason; Error=$($_.Exception.Message)"
                $summary.results.failedActions += @([pscustomobject]@{
                        displayName = $displayName
                        entraObjectId = $device.id
                        deviceId = $device.deviceId
                        action = $failedPhase
                        reason = $reason
                        message = $_.Exception.Message
                        secretName = if ($null -ne $archiveResult) { $archiveResult.SecretName } else { $null }
                    })
                $summary.counts.actionFailures++
            }
        }

        $summary.finishedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        $summary.status = if ($summary.counts.actionFailures -gt 0) { 'PartiallySucceeded' } else { 'Succeeded' }
        $summary.severity = if (($summary.counts.actionFailures + $summary.counts.dryRunDisableCandidates + $summary.counts.dryRunDeleteCandidates) -gt 0) { 'Warning' } else { 'Informational' }
        $summary.summaryText = "Completed device cleanup run. DisableCandidates=$($summary.counts.disableCandidates); DeleteCandidates=$($summary.counts.deleteCandidates); Disabled=$($summary.counts.disabledDevices); ArchivedDeleted=$($summary.counts.archivedDeletedDevices); DryRunDisable=$($summary.counts.dryRunDisableCandidates); DryRunDelete=$($summary.counts.dryRunDeleteCandidates); ActionFailures=$($summary.counts.actionFailures); Excluded=$($summary.counts.excludedDevices)."
        Invoke-DeviceCleanupNotification -Settings $settings -Summary ([pscustomobject] $summary)
        return [pscustomobject] $summary
    }
    catch {
        $summary.finishedAtUtc = (Get-Date).ToUniversalTime().ToString('o')
        $summary.status = 'Failed'
        $summary.severity = 'Error'
        $summary.summaryText = "Device cleanup run failed. $($_.Exception.Message)"
        $summary.failure = [ordered]@{
            message = $_.Exception.Message
            fullyQualifiedErrorId = $_.FullyQualifiedErrorId
            scriptStackTrace = $_.ScriptStackTrace
        }
        Invoke-DeviceCleanupNotification -Settings $settings -Summary ([pscustomobject] $summary)
        throw
    }
}

Invoke-DeviceCleanupJob
