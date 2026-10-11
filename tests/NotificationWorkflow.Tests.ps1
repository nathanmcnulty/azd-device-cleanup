Describe 'Compiled notification workflow contract' {
    BeforeAll {
        $root=Split-Path $PSScriptRoot -Parent
        # Compile the real production Bicep, not a hand-maintained workflow fixture.
        $json=& az bicep build --file (Join-Path $root 'infra/main.bicep') --stdout --only-show-errors
        if($LASTEXITCODE){throw 'Production notification template compilation failed.'}
        $template=($json -join "`n")|ConvertFrom-Json -Depth 100 -DateKind String
        $workflowTemplates=@($template.resources|Where-Object type -eq 'Microsoft.Resources/deployments'|ForEach-Object {$_.properties.template}|Where-Object { @($_.resources|Where-Object type -eq 'Microsoft.Logic/workflows').Count -gt 0 })
        if($workflowTemplates.Count -ne 1){throw 'Expected exactly one production notification child template.'}
        $script:workflowTemplate=$workflowTemplates[0]
        $script:workflow=@($workflowTemplate.resources|Where-Object type -eq 'Microsoft.Logic/workflows')
        if($workflow.Count -ne 1){throw 'Expected exactly one production notification workflow.'}
        $script:definition=$workflow[0].properties.definition
        $script:routes=@(
            @{outer='Forward_to_downstream_webhook';post='Post_notification';parameter='notificationWebhookUrl';body='@triggerBody()'},
            @{outer='Forward_to_teams';post='Post_teams';parameter='teamsWebhookUrl';body="@triggerBody()?['data']?['teams']"},
            @{outer='Forward_to_email';post='Post_email';parameter='emailWebhookUrl';body="@triggerBody()?['data']?['email']"}
        )
    }
    It 'has three sibling routes whose failures cannot block another route by runAfter dependency' {
        @($definition.actions.PSObject.Properties).Count | Should -Be 3
        foreach($route in $routes){
            $action=$definition.actions.($route.outer)
            $action.runAfter.PSObject.Properties.Name.Count | Should -Be 0
            $action.type | Should -Be 'If'
            $action.else.actions.PSObject.Properties.Name.Count | Should -Be 0
            $action.actions.($route.post).inputs.body | Should -Be $route.body
        }
    }
    It 'uses protected HTTPS parameters and hides each HTTP action input/output' {
        foreach($route in $routes){
            $definition.parameters.($route.parameter).type | Should -Be 'SecureString'
            $definition.parameters.($route.parameter).defaultValue | Should -Be ''
            $post=$definition.actions.($route.outer).actions.($route.post)
            $post.inputs.method | Should -Be 'POST'
            $post.inputs.uri | Should -Match 'uriScheme\(parameters'
            $post.inputs.uri | Should -Match "'https'"
            $post.runtimeConfiguration.secureData.properties | Should -Contain 'inputs'
            $post.runtimeConfiguration.secureData.properties | Should -Contain 'outputs'
            $post.operationOptions | Should -Be 'DisableAsyncPattern'
        }
    }
    It 'disables added routes by default and removes the whole workflow when notifications are disabled' {
        $template.parameters.logicAppTeamsWebhookUrl.type | Should -Be 'secureString'
        $template.parameters.logicAppEmailWebhookUrl.type | Should -Be 'secureString'
        $template.parameters.logicAppTeamsWebhookUrl.defaultValue | Should -Be ''
        $template.parameters.logicAppEmailWebhookUrl.defaultValue | Should -Be ''
        $workflow[0].condition | Should -Be "[parameters('logicAppNotificationsEnabled')]"
        $definition.actions.Forward_to_teams.expression | Should -Be "@not(empty(parameters('teamsWebhookUrl')))"
        $definition.actions.Forward_to_email.expression | Should -Be "@not(empty(parameters('emailWebhookUrl')))"
    }
    It 'embeds the exact vendored envelope schema and hashes both immutable component files' {
        $definition.triggers.manual.operationOptions | Should -Be 'EnableSchemaValidation'
        $definition.triggers.manual.inputs.method | Should -Be 'POST'
        $schema=Get-Content (Join-Path $root 'contracts/notifications/notification-envelope.schema.json') -Raw|ConvertFrom-Json -Depth 100
        $compiledSchema=$definition.triggers.manual.inputs.schema
        if($compiledSchema -is [string]){
            if($compiledSchema -notmatch "^\[variables\('([^']+)'\)\]$"){throw 'Unexpected compiled trigger schema expression.'}
            $schemaVariable=$workflowTemplate.variables.PSObject.Properties[$Matches[1]]
            if($null -eq $schemaVariable){throw 'Missing compiled trigger schema variable.'}
            $compiledSchema=$schemaVariable.Value
        }
        ($compiledSchema|ConvertTo-Json -Depth 100 -Compress)|Should -Be ($schema|ConvertTo-Json -Depth 100 -Compress)
        $lock=Get-Content (Join-Path $root 'azd-components.lock.json') -Raw|ConvertFrom-Json -Depth 100
        $lock.components.Count | Should -Be 1
        $lock.components[0].id | Should -Be 'notification-contracts'
        $lock.components[0].sourceRevision | Should -Be '6dc5841a3156b904b89f0f4ff8d97207a26ec15a'
        foreach($file in $lock.components[0].files){(Get-FileHash (Join-Path $root $file.target)).Hash.ToLowerInvariant()|Should -Be $file.sha256}
    }
    It 'exposes only child HTTP action status, including skipped, without raw response or destination values' {
        @($definition.outputs.PSObject.Properties).Count | Should -Be 3
        foreach($output in $definition.outputs.PSObject.Properties){
            $output.Value.type | Should -Be 'String'
            $output.Value.value | Should -Match "^@coalesce\(actions\('Post_"
            $output.Value.value | Should -Match "\?\['status'\], 'Skipped'\)$"
        }
    }
}
