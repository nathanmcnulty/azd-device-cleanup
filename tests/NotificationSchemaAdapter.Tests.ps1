#Requires -Version 7.6
BeforeDiscovery {
    $cases=@(
        @{Name='baseline';Field='source';Value='azd.device'},
        @{Name='namespace-terminal-LF';Field='source';Value="azd.device`n"},
        @{Name='namespace-terminal-CRLF';Field='source';Value="azd.device`r`n"},
        @{Name='namespace-two-LF';Field='eventType';Value="azd.device`n`n"},
        @{Name='namespace-uppercase-first';Field='eventType';Value='Azd.device'},
        @{Name='namespace-digit-segment';Field='source';Value='azd.1device'},
        @{Name='namespace-empty-segment';Field='source';Value='azd..device'},
        @{Name='namespace-one-segment';Field='source';Value='azd'},
        @{Name='namespace-empty';Field='source';Value=''},
        @{Name='namespace-del';Field='source';Value=('azd.device'+[char]127)},
        @{Name='namespace-unicode';Field='eventType';Value='azd.dévice'},
        @{Name='namespace-256';Field='source';Value=('a.'+('A'*254))},
        @{Name='namespace-257';Field='source';Value=('a.'+('A'*255))},
        @{Name='namespace-255-plusLF';Field='source';Value=('a.'+('A'*253)+"`n")},
        @{Name='namespace-256-plusLF';Field='source';Value=('a.'+('A'*254)+"`n")},
        @{Name='format-date-annotation';Field='occurredAt';Value='not-a-date'},
        @{Name='format-uuid-annotation';Field='tenantId';Value='not-a-uuid'},
        @{Name='name-128-codepoints';Field='name';Value=([char]::ConvertFromUtf32(0x1F600)*128)},
        @{Name='name-129-codepoints';Field='name';Value=([char]::ConvertFromUtf32(0x1F600)*129)},
        @{Name='schema-version';Field='schemaVersion';Value='1.1'},
        @{Name='severity';Field='severity';Value='unknown'},
        @{Name='isTest-string';Field='isTest';Value='true'},
        @{Name='data-array';Field='data';Value=@('a')},
        @{Name='data-open';Field='data';Value=@{arbitrary=@{nested=@('a',1,$null)}}},
        @{Name='extra-top';Field='extraTop';Value='canary'},
        @{Name='extra-environment';Field='extraEnvironment';Value='canary'},
        @{Name='missing-source';Field='missingSource';Value=$null},
        @{Name='null-source';Field='source';Value=$null}
    )
    foreach($field in @('eventId','correlationId')){
        foreach($pair in @(
            @{Label='empty';Text=''},@{Label='terminal-LF';Text="a`n"},
            @{Label='LF-only';Text="`n"},@{Label='embedded-LF';Text="a`nb"},
            @{Label='CRLF';Text="a`r`n"},@{Label='two-LF';Text="a`n`n"},
            @{Label='literal-percent';Text='%00'},@{Label='space-DEL';Text=(' '+[char]127)},
            @{Label='255-plusLF';Text=(('a'*255)+"`n")},@{Label='256-plusLF';Text=(('a'*256)+"`n")},
            @{Label='256-codepoints';Text=([char]::ConvertFromUtf32(0x1F600)*256)},
            @{Label='257-codepoints';Text=([char]::ConvertFromUtf32(0x1F600)*257)},
            @{Label='255-astral-plusLF';Text=(([char]::ConvertFromUtf32(0x1F600)*255)+"`n")},
            @{Label='256-astral-plusLF';Text=(([char]::ConvertFromUtf32(0x1F600)*256)+"`n")}
        )){$cases+=@{Name="$field-$($pair.Label)";Field=$field;Value=$pair.Text}}
        for($control=0;$control -lt 32;$control++){
            $cases+=@{Name="$field-embedded-C0-$control";Field=$field;Value=('a'+[char]$control+'b')}
            $cases+=@{Name="$field-final-C0-$control";Field=$field;Value=('a'+[char]$control)}
        }
    }
}

Describe 'Compiled provider adapter differential contract' {
    BeforeAll {
        function Invoke-RestMethod {throw 'Offline adapter tests forbid HTTP.'}
        function Invoke-WebRequest {throw 'Offline adapter tests forbid HTTP.'}
        $root=Split-Path $PSScriptRoot -Parent
        . (Join-Path $PSScriptRoot 'helpers/NotificationExpressionModel.ps1')
        $json=& az bicep build --file (Join-Path $root 'infra/main.bicep') --stdout --only-show-errors
        if($LASTEXITCODE){throw 'Adapter compilation failed.'}
        $template=($json -join "`n")|ConvertFrom-Json -Depth 100 -DateKind String
        $child=@($template.resources|Where-Object type -eq 'Microsoft.Resources/deployments'|ForEach-Object {$_.properties.template}|Where-Object {@($_.resources|Where-Object type -eq 'Microsoft.Logic/workflows').Count -gt 0})[0]
        $workflow=@($child.resources|Where-Object type -eq 'Microsoft.Logic/workflows')[0]
        $definition=Resolve-TestCompiledArmValue $workflow.properties.definition $child.variables
        $projection=$definition.triggers.manual.inputs.schema
        if($projection -is [string]){
            if($projection -notmatch "^\[variables\('([^']+)'\)\]$"){throw 'Unexpected schema expression.'}
            $projection=$child.variables.PSObject.Properties[$Matches[1]].Value
        }
        $projectionJson=$projection|ConvertTo-Json -Depth 100 -Compress
        $canonicalPath=Join-Path $root 'contracts/notifications/notification-envelope.schema.json'
        $canonical=Get-Content $canonicalPath -Raw|ConvertFrom-Json -Depth 100
        $base=@{schemaVersion='1.0';eventId='a';eventType='azd.device';source='azd.device';occurredAt='2026-01-01T00:00:00Z';severity='low';correlationId='a';isTest=$true;environment=@{name='lab';tenantId='00000000-0000-0000-0000-000000000001'};data=@{}}
    }
    It 'matches canonical validation for <Name> using actual compiled pattern expressions' -ForEach $cases {
        $body=($base|ConvertTo-Json -Depth 20)|ConvertFrom-Json -AsHashtable -DateKind String
        switch($Field){
            'name' {$body.environment.name=$Value}
            'tenantId' {$body.environment.tenantId=$Value}
            'extraTop' {$body.other=$Value}
            'extraEnvironment' {$body.environment.other=$Value}
            'missingSource' {[void]$body.Remove('source')}
            default {$body[$Field]=$Value}
        }
        $wire=$body|ConvertTo-Json -Depth 20 -Compress
        $expected=$wire|Test-Json -SchemaFile $canonicalPath -ErrorAction SilentlyContinue
        $actual=$wire|Test-Json -Schema $projectionJson -ErrorAction SilentlyContinue
        if($actual){$actual=Invoke-TestCompiledPatternActions $definition.actions.Check_patterns.actions $body}
        $actual | Should -Be $expected
    }
    It 'accounts for every canonical structural assertion without adding format assertions' {
        # Pattern predicates are deliberately specific to this immutable schema.
        # A changed contract requires reviewing the adapter, not only its lock.
        (Get-FileHash -LiteralPath $canonicalPath).Hash | Should -Be '627F13BE9F5D5813CC350423D164C9BCE97D56C3B050CFA753F8F702EE193B4E'
        $expected=($canonical|ConvertTo-Json -Depth 100)|ConvertFrom-Json -AsHashtable -Depth 100
        $definitions=$expected['$defs']
        foreach($key in @('$schema','title','$defs')){[void]$expected.Remove($key)}
        foreach($field in @('eventId','correlationId','source','eventType','environment')){
            $reference=$expected.properties[$field]['$ref'].Substring('#/$defs/'.Length)
            $expanded=($definitions[$reference]|ConvertTo-Json -Depth 100)|ConvertFrom-Json -AsHashtable -Depth 100
            [void]$expanded.Remove('pattern')
            $expected.properties[$field]=$expanded
        }
        $expected.properties.schemaVersion=@{enum=@($expected.properties.schemaVersion.const)}
        [void]$expected.properties.occurredAt.Remove('format')
        foreach($field in @('tenantId','subscriptionId')){[void]$expected.properties.environment.properties[$field].Remove('format')}
        # Hashtable/PSObject ordering is irrelevant: compare every structural
        # leaf through a stable serialized representation, not a partial map.
        function Get-SortedTestStructure {
            param($Value)
            if($Value -is [Collections.IDictionary]){
                $result=[ordered]@{};foreach($key in $Value.Keys|Sort-Object){$result[$key]=Get-SortedTestStructure $Value[$key]};return $result
            }
            if($Value -is [array]){return ,@(foreach($item in $Value){Get-SortedTestStructure $item})}
            return ,$Value
        }
        $actualMap=$projectionJson|ConvertFrom-Json -AsHashtable -Depth 100
        (Get-SortedTestStructure $actualMap|ConvertTo-Json -Depth 100 -Compress)|Should -Be (Get-SortedTestStructure $expected|ConvertTo-Json -Depth 100 -Compress)
        @($projection.properties.PSObject.Properties.Name)|Should -Be @($canonical.properties.PSObject.Properties.Name)
        $projection.additionalProperties | Should -BeFalse
        $projection.properties.environment.additionalProperties | Should -BeFalse
        @($projection.properties.environment.required)|Should -Be @($canonical.'$defs'.environment.required)
        foreach($field in @('eventId','correlationId')){
            $projection.properties.$field.type|Should -Be 'string'
            $projection.properties.$field.minLength|Should -Be $canonical.'$defs'.eventId.minLength
            $projection.properties.$field.maxLength|Should -Be $canonical.'$defs'.eventId.maxLength
        }
        foreach($field in @('source','eventType')){
            $projection.properties.$field.type|Should -Be 'string'
            $projection.properties.$field.maxLength|Should -Be $canonical.'$defs'.namespacedName.maxLength
        }
        foreach($field in @('name','resourceGroup')){
            ($projection.properties.environment.properties.$field|ConvertTo-Json -Compress)|Should -Be ($canonical.'$defs'.environment.properties.$field|ConvertTo-Json -Compress)
        }
        $projectionJson|Should -Not -Match '"format"|"pattern"|"\$ref"|"\$defs"|"const"'
    }
    It 'fails closed before all routes when any validation action fails or is skipped' {
        $decision=$definition.actions.Validate_envelope
        $decision.expression|Should -Be "@equals(outputs('Pattern_valid'), true)"
        @($decision.runAfter.PSObject.Properties.Name)|Should -Be @('Check_patterns')
        $decision.runAfter.Check_patterns|Should -Be @('Succeeded')
        $decision.else.actions.Reject_notification.inputs.statusCode|Should -Be 400
        $definition.actions.Validation_error_response.inputs.statusCode|Should -Be 503
        @($definition.actions.Validation_error_response.runAfter.Check_patterns)|Should -Be @('Failed','TimedOut')
        @($definition.actions.PSObject.Properties|Where-Object {$_.Value.type -eq 'Http'}).Count|Should -Be 0
        @($decision.else.actions.PSObject.Properties|Where-Object {$_.Value.type -eq 'Http'}).Count|Should -Be 0
        $decision.actions.Accept_notification.inputs.statusCode|Should -Be 202
        @($decision.actions.PSObject.Properties|Where-Object Name -like 'Forward_to_*').Count|Should -Be 3
        foreach($check in $definition.actions.Check_patterns.actions.PSObject.Properties){
            if($check.Name -ne 'Pattern_inputs'){@($check.Value.runAfter.PSObject.Properties.Name).Count|Should -BeGreaterThan 0}
            foreach($after in $check.Value.runAfter.PSObject.Properties){$after.Value|Should -Be @('Succeeded')}
        }
    }
    It 'configures documented supported protections for inbound and temporary pattern bodies' {
        $definition.triggers.manual.runtimeConfiguration.secureData.properties|Should -Contain 'inputs'
        $definition.triggers.manual.runtimeConfiguration.secureData.properties|Should -Contain 'outputs'
        @($definition.actions.Check_patterns.PSObject.Properties.Name)|Should -Not -Contain 'runtimeConfiguration'
        $definition.actions.Check_patterns.actions.Pattern_inputs.type|Should -Be 'Compose'
        $definition.actions.Check_patterns.actions.Pattern_inputs.runtimeConfiguration.secureData.properties|Should -Be @('inputs')
        foreach($check in $definition.actions.Check_patterns.actions.PSObject.Properties|Where-Object {$_.Value.type -eq 'Query'}){
            $check.Value.runtimeConfiguration.secureData.properties|Should -Contain 'inputs'
            $check.Value.runtimeConfiguration.secureData.properties|Should -Contain 'outputs'
        }
        $definition.actions.Check_patterns.actions.Pattern_valid.inputs|Should -Not -Match 'triggerBody'
    }
    It 'rejects unsupported secure-data configurations in actual action-type fixtures' -ForEach @('Scope','Compose','If','Response') {
        # Microsoft lists Scope/If unsupported for both, Compose/Response for outputs.
        function Assert-SupportedHistorySettings($Action) {
            $configuration=$Action.PSObject.Properties['runtimeConfiguration']
            if($null -eq $configuration){return}
            if($Action.type -in @('Scope','If') -and $null -ne $configuration.Value.secureData){throw 'UnsupportedSecureData'}
            if($Action.type -in @('Compose','Response') -and 'outputs' -in @($configuration.Value.secureData.properties)){throw 'UnsupportedSecureOutputs'}
        }
        $actual=switch($PSItem){
            Scope {$definition.actions.Check_patterns}
            Compose {$definition.actions.Check_patterns.actions.Pattern_inputs}
            If {$definition.actions.Validate_envelope}
            Response {$definition.actions.Validate_envelope.actions.Accept_notification}
        }
        {Assert-SupportedHistorySettings $actual}|Should -Not -Throw
        $fixture=($actual|ConvertTo-Json -Depth 100)|ConvertFrom-Json -Depth 100
        $fixture|Add-Member -MemberType NoteProperty -Name runtimeConfiguration -Value @{secureData=@{properties=@('inputs','outputs')}} -Force
        {Assert-SupportedHistorySettings $fixture}|Should -Throw '*UnsupportedSecure*'
    }
    It 'refuses unsupported expression syntax rather than inventing an evaluation result' {
        {Invoke-TestWdlNode (ConvertFrom-TestWdlExpression "@unreviewedFunction('a')") @{}}|Should -Throw
        {ConvertFrom-TestWdlExpression "@true || false"}|Should -Throw
    }
    It 'detects a missing C0 check in the actual compiled expression model' {
        $mutated=($definition.actions.Check_patterns.actions|ConvertTo-Json -Depth 100)|ConvertFrom-Json -Depth 100
        $mutated.Invalid_ID_controls.inputs.where='@false'
        $body=($base|ConvertTo-Json -Depth 20)|ConvertFrom-Json -AsHashtable -DateKind String
        $body.eventId='a'+[char]0+'b'
        (($body|ConvertTo-Json -Depth 20)|Test-Json -SchemaFile $canonicalPath -ErrorAction SilentlyContinue)|Should -BeFalse
        (Invoke-TestCompiledPatternActions $mutated $body)|Should -BeTrue
    }
    It 'detects a missing namespace initial check in the actual compiled expression model' {
        $mutated=($definition.actions.Check_patterns.actions|ConvertTo-Json -Depth 100)|ConvertFrom-Json -Depth 100
        $mutated.Invalid_namespace_initials.inputs.where='@false'
        $body=($base|ConvertTo-Json -Depth 20)|ConvertFrom-Json -AsHashtable -DateKind String
        $body.source='Azd.device'
        (($body|ConvertTo-Json -Depth 20)|Test-Json -SchemaFile $canonicalPath -ErrorAction SilentlyContinue)|Should -BeFalse
        (Invoke-TestCompiledPatternActions $mutated $body)|Should -BeTrue
    }
    It 'detects accidental tightening when single terminal LF normalization is removed' {
        $mutated=($definition.actions.Check_patterns.actions|ConvertTo-Json -Depth 100)|ConvertFrom-Json -Depth 100
        $mutated.Pattern_inputs.inputs.eventId="@triggerBody()?['eventId']"
        $body=($base|ConvertTo-Json -Depth 20)|ConvertFrom-Json -AsHashtable -DateKind String
        $body.eventId="a`n"
        (($body|ConvertTo-Json -Depth 20)|Test-Json -SchemaFile $canonicalPath -ErrorAction SilentlyContinue)|Should -BeTrue
        (Invoke-TestCompiledPatternActions $mutated $body)|Should -BeFalse
    }
}
