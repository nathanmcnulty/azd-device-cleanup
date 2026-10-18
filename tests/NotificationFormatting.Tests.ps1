Describe 'Bounded cleanup notification producer' {
    BeforeAll {
        $script:root = Split-Path $PSScriptRoot -Parent
        $tokens = $null; $errors = $null
        $ast = [System.Management.Automation.Language.Parser]::ParseFile((Join-Path $root 'runbooks/DeviceCleanup.ps1'), [ref]$tokens, [ref]$errors)
        if ($errors.Count) { throw ($errors | Out-String) }
        foreach ($definition in $ast.EndBlock.Statements | Where-Object { $_ -is [System.Management.Automation.Language.FunctionDefinitionAst] }) {
            . ([scriptblock]::Create($definition.Extent.Text))
        }
        $script:tenant = 'aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'
    }
    BeforeEach {
        $script:summary = [pscustomobject]@{
            environmentName='lab'; subscriptionId='bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb'; resourceGroupName='rg-lab'; automationAccountName='aa-lab'; runbookName='DeviceCleanup'
            cleanupRunId='cccccccc-cccc-cccc-cccc-cccccccccccc'; finishedAtUtc='2026-10-11T05:00:00+00:00'; status='PartiallySucceeded'; severity='Warning'
            summaryText='MUST_NOT_ESCAPE bearer secret'; failure=@{message='MUST_NOT_ESCAPE provider error'}; results=@{archivedDeletedDevices=@(@{displayName='MUST_NOT_ESCAPE';secretName='MUST_NOT_ESCAPE';lapsPassword='MUST_NOT_ESCAPE'})}
            counts=[pscustomobject]@{totalDevices=20;excludedDevices=3;intuneDefenderAttributeUpdates=2;restrictedManagementUnitSkipped=0;disableCandidates=4;deleteCandidates=1;disabledDevices=3;archivedDeletedDevices=1;dryRunDisableCandidates=0;dryRunDeleteCandidates=0;actionFailures=1;unexpected='MUST_NOT_ESCAPE'}
        }
        $script:settings = [pscustomobject]@{NotificationsEnabled=$true;NotifyOnFailure=$true;NotifyOnSuccess=$true;NotifyOnNoAction=$false;TenantId=$tenant;NotificationCallbackUrl='https://callback.example.invalid/run?sig=MUST_NOT_ESCAPE'}
        Mock Start-Sleep {}
    }
    It 'validates the actual produced envelope against its immutable canonical schema' {
        $envelope=ConvertTo-DeviceCleanupNotificationEnvelope -Summary $summary -TenantId $tenant
        $json=$envelope|ConvertTo-Json -Depth 20 -Compress
        $json|Test-Json -SchemaFile (Join-Path $root 'contracts/notifications/notification-envelope.schema.json') | Should -BeTrue
        $json | Should -Not -Match 'MUST_NOT_ESCAPE|lapsPassword|secretName|displayName|summaryText|failedActions'
        $envelope.eventId | Should -Be 'cleanup.cccccccc-cccc-cccc-cccc-cccccccccccc'
        $envelope.correlationId | Should -Be $summary.cleanupRunId
        $envelope.data.counts.actionFailures | Should -Be 1
        [Text.Encoding]::UTF8.GetByteCount($json) | Should -BeLessOrEqual 16384
    }
    It 'formats distinct Teams and email bodies from the same bounded event' {
        $e=ConvertTo-DeviceCleanupNotificationEnvelope -Summary $summary -TenantId $tenant
        $e.data.teams.type | Should -Be 'message'
        $e.data.teams.attachments.Count | Should -Be 1
        $e.data.teams.attachments[0].contentType | Should -Be 'application/vnd.microsoft.card.adaptive'
        $card=$e.data.teams.attachments[0].content
        $card.actions[0].url | Should -Be $e.data.reviewUrl
        ([Uri]$e.data.reviewUrl).Host | Should -Be 'portal.azure.com'
        ([Uri]$e.data.reviewUrl).Query | Should -Be ''
        $e.data.email.html | Should -Match '<a href="https://portal.azure.com/#resource/subscriptions/'
        $e.data.email.text | Should -Match 'cccccccc-cccc-cccc-cccc-cccccccccccc'
        $e.data.email.subject | Should -Be 'Device cleanup: PartiallySucceeded [lab]'
    }
    It 'retains degraded NoAction severity without raw failure text' {
        $summary.status='NoAction';$summary.severity='Warning'
        $e=ConvertTo-DeviceCleanupNotificationEnvelope -Summary $summary -TenantId $tenant
        $e.severity | Should -Be 'medium'
        $e.data.status | Should -Be 'NoAction'
    }
    It 'refuses injected source names and identifiers rather than formatting arbitrary links' {
        $summary.resourceGroupName='rg?sig=MUST_NOT_ESCAPE'
        {ConvertTo-DeviceCleanupNotificationEnvelope -Summary $summary -TenantId $tenant} | Should -Throw 'Invalid notification resource name.'
        $summary.resourceGroupName='rg-lab';$summary.subscriptionId='https://evil.example.invalid'
        {ConvertTo-DeviceCleanupNotificationEnvelope -Summary $summary -TenantId $tenant} | Should -Throw 'Invalid notification identity.'
    }
    It 'refuses unbounded counts and unknown terminal state' {
        $summary.counts.actionFailures=10000001
        {ConvertTo-DeviceCleanupNotificationEnvelope -Summary $summary -TenantId $tenant} | Should -Throw 'Invalid notification count.'
        $summary.counts.actionFailures=1;$summary.status='MUST_NOT_ESCAPE'
        {ConvertTo-DeviceCleanupNotificationEnvelope -Summary $summary -TenantId $tenant} | Should -Throw 'Invalid notification status.'
    }
    It 'passes only the actual bounded envelope through the existing notification dispatcher' {
        Mock Invoke-NotificationCallback {param($Uri,$Payload) $script:sent=$Payload}
        Invoke-DeviceCleanupNotification -Settings $settings -Summary $summary | Out-Null
        Should -Invoke Invoke-NotificationCallback -Times 1 -Exactly
        ($script:sent|ConvertTo-Json -Depth 20) | Should -Not -Match 'MUST_NOT_ESCAPE'
    }
    It 'does no formatting or callback for disabled and suppressed routes' {
        Mock ConvertTo-DeviceCleanupNotificationEnvelope {throw 'Must not format'}
        Mock Invoke-NotificationCallback {throw 'Must not post'}
        $settings.NotificationsEnabled=$false
        Invoke-DeviceCleanupNotification -Settings $settings -Summary $summary
        $settings.NotificationsEnabled=$true;$summary.status='NoAction'
        Invoke-DeviceCleanupNotification -Settings $settings -Summary $summary
        Should -Invoke ConvertTo-DeviceCleanupNotificationEnvelope -Times 0 -Exactly
        Should -Invoke Invoke-NotificationCallback -Times 0 -Exactly
    }
    It 'bounds retries and sanitizes real callback exceptions before notification logging' {
        Mock Invoke-RestMethod {throw 'MUST_NOT_ESCAPE https://callback.example.invalid/?sig=secret'}
        $warnings=@()
        Invoke-DeviceCleanupNotification -Settings $settings -Summary $summary -WarningVariable warnings -WarningAction SilentlyContinue | Out-Null
        Should -Invoke Invoke-RestMethod -Times 3 -Exactly -ParameterFilter {$MaximumRedirection -eq 0 -and $TimeoutSec -eq 30 -and $Method -eq 'POST'}
        ($warnings|Out-String) | Should -Not -Match 'MUST_NOT_ESCAPE|sig=|https://callback|bearer secret'
        Should -Invoke Start-Sleep -Times 2 -Exactly
    }
    It 'refuses non-HTTPS callbacks before any HTTP call' {
        Mock Invoke-RestMethod {throw 'Must not post'}
        {Invoke-NotificationCallback -Uri 'http://callback.example.invalid' -Payload @{}} | Should -Throw 'Invalid notification callback address.'
        Should -Invoke Invoke-RestMethod -Times 0 -Exactly
    }
}
