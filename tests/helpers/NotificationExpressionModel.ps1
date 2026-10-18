#Requires -Version 7.6
# Test-only evaluator for the exact documented primitives used by the compiled
# pattern actions. It is not a runtime validator or proof of native WDL behavior.
# Unknown syntax/functions fail the test instead of being approximated.
function Resolve-TestCompiledArmValue {
    param($Value,$Variables,[int]$Depth=0)
    if($Depth -gt 16){throw 'Compiled ARM variable recursion exceeded.'}
    if($Value -is [string] -and $Value -match "^\[variables\('([^']+)'\)\]$"){
        $property=$Variables.PSObject.Properties[$Matches[1]]
        if($null -eq $property){throw 'Missing compiled ARM variable.'}
        return ,(Resolve-TestCompiledArmValue $property.Value $Variables ($Depth+1))
    }
    if($Value -is [System.Management.Automation.PSCustomObject]){
        $result=[ordered]@{}
        foreach($property in $Value.PSObject.Properties){$result[$property.Name]=Resolve-TestCompiledArmValue $property.Value $Variables ($Depth+1)}
        return [pscustomobject]$result
    }
    if($Value -is [array]){return ,@(foreach($item in $Value){Resolve-TestCompiledArmValue $item $Variables ($Depth+1)})}
    return ,$Value
}

function ConvertFrom-TestWdlExpression {
    param([string]$Expression)
    $text=$Expression.Substring(1)
    $tokens=[Collections.Generic.List[object]]::new()
    $position=0
    while($position -lt $text.Length){
        $match=[regex]::Match($text.Substring($position),"^\s*(?:'((?:''|[^'])*)'|([0-9]+)|([A-Za-z_][A-Za-z_0-9]*)|([(),?\[\]]))")
        if(-not $match.Success){throw 'Unsupported test WDL syntax.'}
        $position+=$match.Length
        if($match.Groups[1].Success){$tokens.Add(@{kind='string';value=$match.Groups[1].Value.Replace("''","'")})}
        elseif($match.Groups[2].Success){$tokens.Add(@{kind='number';value=[int]$match.Groups[2].Value})}
        elseif($match.Groups[3].Success){$tokens.Add(@{kind='name';value=$match.Groups[3].Value})}
        else{$tokens.Add(@{kind='symbol';value=$match.Groups[4].Value})}
    }
    $state=@{index=0;tokens=$tokens}
    function Read-TestWdlNode {
        param($State)
        if($State.index -ge $State.tokens.Count){throw 'Truncated test WDL expression.'}
        $token=$State.tokens[$State.index++]
        if($token.kind -in @('string','number')){$node=@{kind='literal';value=$token.value}}
        elseif($token.kind -eq 'name' -and $token.value -in @('true','false')){$node=@{kind='literal';value=($token.value -eq 'true')}}
        elseif($token.kind -eq 'name'){
            if($State.tokens[$State.index++].value -ne '('){throw 'Missing test WDL call delimiter.'}
            $arguments=[Collections.Generic.List[object]]::new()
            if($State.tokens[$State.index].value -ne ')'){
                while($true){
                    $arguments.Add((Read-TestWdlNode $State))
                    if($State.tokens[$State.index].value -ne ','){break}
                    $State.index++
                }
            }
            if($State.tokens[$State.index++].value -ne ')'){throw 'Missing test WDL closing delimiter.'}
            $node=@{kind='call';name=$token.value;arguments=$arguments}
        }
        else{throw 'Unsupported test WDL node.'}
        while($State.index -lt $State.tokens.Count -and $State.tokens[$State.index].value -eq '?'){
            $State.index++
            if($State.tokens[$State.index++].value -ne '['){throw 'Missing test WDL access delimiter.'}
            $key=$State.tokens[$State.index++]
            if($key.kind -ne 'string' -or $State.tokens[$State.index++].value -ne ']'){throw 'Unsupported test WDL property access.'}
            $node=@{kind='access';target=$node;key=$key.value}
        }
        return $node
    }
    $result=Read-TestWdlNode $state
    if($state.index -ne $tokens.Count){throw 'Trailing test WDL syntax.'}
    return $result
}

function Invoke-TestWdlNode {
    param($Node,$Context)
    if($Node.kind -eq 'literal'){return ,$Node.value}
    if($Node.kind -eq 'access'){return ,(Invoke-TestWdlNode $Node.target $Context)[$Node.key]}
    if($Node.kind -ne 'call'){throw 'Unsupported test WDL node kind.'}
    if($Node.name -eq 'if'){
        $branch=if(Invoke-TestWdlNode $Node.arguments[0] $Context){1}else{2}
        return ,(Invoke-TestWdlNode $Node.arguments[$branch] $Context)
    }
    $args=[Collections.Generic.List[object]]::new()
    foreach($argument in $Node.arguments){$args.Add((Invoke-TestWdlNode $argument $Context))}
    switch -CaseSensitive ($Node.name){
        'triggerBody' {return ,$Context.input}
        'outputs' {return ,$Context.outputs[$args[0]]}
        'body' {return ,$Context.outputs[$args[0]]}
        'item' {return ,$Context.item}
        'endsWith' {return ([string]$args[0]).EndsWith([string]$args[1],[StringComparison]::Ordinal)}
        'decodeUriComponent' {return [Uri]::UnescapeDataString($args[0])}
        'substring' {return ([string]$args[0]).Substring($args[1],$args[2])}
        'length' {if($args[0] -is [string]){return $args[0].Length};return $args[0].Count}
        'sub' {return $args[0]-$args[1]}
        'mul' {return $args[0]*$args[1]}
        'range' {return ,@($(for($i=0;$i -lt $args[1];$i++){$args[0]+$i}))}
        'concat' {return ($args -join '')}
        'createArray' {return ,$args.ToArray()}
        'split' {return ,([string]$args[0]).Split([string]$args[1],[StringSplitOptions]::None)}
        'skip' {return ,@($args[0]|Select-Object -Skip $args[1])}
        'union' {
            $values=[Collections.Generic.HashSet[string]]::new([StringComparer]::Ordinal)
            foreach($array in $args){foreach($value in $array){[void]$values.Add($value)}}
            return ,@($values)
        }
        'contains' {return ([string]$args[0]).Contains([string]$args[1],[StringComparison]::Ordinal)}
        'less' {return $args[0] -lt $args[1]}
        'empty' {return $null -eq $args[0] -or $args[0].Length -eq 0}
        'not' {return -not $args[0]}
        'and' {return -not ($args -contains $false)}
        'or' {return $args -contains $true}
        'equals' {return $args[0] -ceq $args[1]}
        default {throw "Unsupported test WDL function: $($Node.name)"}
    }
}

function Invoke-TestCompiledPatternActions {
    param($Actions,$InputBody)
    $context=@{input=$InputBody;outputs=@{}}
    $context.outputs.Pattern_inputs=@{}
    foreach($property in $Actions.Pattern_inputs.inputs.PSObject.Properties){
        $node=ConvertFrom-TestWdlExpression $property.Value
        $context.outputs.Pattern_inputs[$property.Name]=Invoke-TestWdlNode $node $context
    }
    foreach($name in @('Invalid_ID_controls','Invalid_namespace_initials','Invalid_namespace_segments','Invalid_namespace_characters')){
        $query=$Actions.$name
        $from=Invoke-TestWdlNode (ConvertFrom-TestWdlExpression $query.inputs.from) $context
        $predicate=ConvertFrom-TestWdlExpression $query.inputs.where
        $matches=@(foreach($value in $from){$context.item=$value;if(Invoke-TestWdlNode $predicate $context){$value}})
        $context.outputs[$name]=$matches
    }
    return Invoke-TestWdlNode (ConvertFrom-TestWdlExpression $Actions.Pattern_valid.inputs) $context
}
