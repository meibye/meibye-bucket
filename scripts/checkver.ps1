<#
.SYNOPSIS
    Wrapper for Scoop's checkver.ps1 with argument normalization, static help, and detail output support.

.DESCRIPTION
    This script wraps Scoop's checkver.ps1 for the apps-bucket-scan manifest. It accepts arguments via -Args, normalizes them, handles -help and -detail locally, inserts -Dir D:\Dev\meibye-bucket\bucket if missing, and passes the final arguments to checkver.ps1. Help output is static and documents supported parameters.

.PARAMETER Args
    String of arguments to pass. Handles 'help' and 'detail' locally, normalizes argument order, and passes the rest to checkver.ps1.
#>

param(
    # Accept all arguments as a single string via -Args, or as a splatted array
    [Parameter(Position=0, ValueFromRemainingArguments=$true)]
    [string[]]$Args
)

# Normalize $ArgLine to be a single string of all arguments, preserving spaces/quotes
if ($Args.Count -eq 1 -and $Args[0] -is [string]) {
    $ArgLine = $Args[0]
} else {
    $ArgLine = ($Args | ForEach-Object { $_ }) -join ' '
}

# Local-only flags that parent consumes (do NOT forward)
# initialize to #null for string
# Example: -verbose (switch), -help (switch)
$LocalOnlyParams = @{
    Help = $false  
    Detail = $false
    DryRun = $false
}

# --- Tokenize ArgLine safely (handles quotes, spaces) ---
$toks = [System.Management.Automation.PSParser]::Tokenize($ArgLine, [ref]$null)

# Build a token list that represents argv (strings of tokens)
$argv = @()
foreach ($t in $toks) {
    switch ($t.Type.ToString()) {
        'Command'          { $argv += $t.Content }
        'CommandParameter' { $argv += $t.Content }
        'CommandArgument'  { $argv += $t.Content }
        'String'           { $argv += $t.Content }
        'Number'           { $argv += $t.Content }
        default { } # ignore punctuation like commas, parens, etc.
    }
    # Check for -help or --help (case-insensitive)
    if ($t.Content -match '^(--?help)$') {
        $LocalOnlyParams.Help = $true
    }
    # Check for -detail or --detail (case-insensitive)
    if ($t.Content -match '^(--?detail)$') {
        $LocalOnlyParams.Detail = $true
    }
    # Check for -dryrun or --dryrun (case-insensitive)
    if ($t.Content -match '^(--?dryrun)$') {
        $LocalOnlyParams.DryRun = $true
    }
}

# --- Define expected parameters and their default values ---
if ($LocalOnlyParams.Help)    { Write-Host "Help:      ON" }
if ($LocalOnlyParams.Detail)  { Write-Host "Detail:    ON" }
if ($LocalOnlyParams.DryRun)  { Write-Host "DryRun:    ON" }

# Print help if requested ---
if ($LocalOnlyParams.Help) {
    Write-Host "USAGE: checkver.ps1 -Args '<params>'"
    Write-Host ""
    Write-Host "Parameters:"
    Write-Host "  -App           The app manifest name or pattern (default: *)"
    Write-Host "  -Dir           Path to bucket directory (default: D:\Dev\meibye-bucket\bucket)"
    Write-Host "  -Update        Update manifest(s)"
    Write-Host "  -ForceUpdate   Force update even if unchanged"
    Write-Host "  -SkipUpdated   Skip already updated manifests"
    Write-Host "  -Version       Specify version"
    Write-Host "  -ThrowError    Throw on error"
    Write-Host ""
    Write-Host "Special wrapper arguments handled locally: -help, -detail, -dryrun"
    Write-Host ""
    Write-Host "Example:"
    Write-Host "  .\checkver.ps1 -Args 'apps-bucket-scan -Dir D:\Dev\meibye-bucket\bucket'"
    Write-Host "  .\checkver.ps1 -Args '-help'"
    exit 0
}

# Define the mapping of positional arguments to named parameters. Local only params should be included.
$paramMapping = @(
    @{ Name = '-App'; Type = 'String'; Default = '*'; Mandatory = $true },
    @{ Name = '-Dir'; Type = 'String'; Default = 'D:\Dev\meibye-bucket\bucket'; Mandatory = $true },
    @{ Name = '-Update'; Type = 'Switch'; Default = $false; Mandatory = $false },
    @{ Name = '-ForceUpdate'; Type = 'Switch'; Default = $false; Mandatory = $false },
    @{ Name = '-SkipUpdated'; Type = 'Switch'; Default = $false; Mandatory = $false },
    @{ Name = '-Version'; Type = 'String'; Default = $false; Mandatory = $false },
    @{ Name = '-ThrowError'; Type = 'Switch'; Default = $false; Mandatory = $false },
    @{ Name = '-Help'; Type = 'Switch'; Default = $false; Mandatory = $false },
    @{ Name = '-Detail'; Type = 'Switch'; Default = $false; Mandatory = $false },
    @{ Name = '-DryRun'; Type = 'Switch'; Default = $false; Mandatory = $false }
)

# Convert positional arguments to named arguments
$namedArgs = @{}
$positionalIndex = 0
for ($i = 0; $i -lt $argv.Count; $i++) {
    if ($argv[$i] -like '-*') {
        # Named argument, add it directly.
        $param = $paramMapping | Where-Object { $_.Name -eq $argv[$i] }
        if ($param -and $param.Type -eq 'Switch') {
            $namedArgs[$argv[$i]] = $true
        } elseif (($i + 1) -lt $argv.Count -and $argv[$i + 1] -notlike '-*') {
            $namedArgs[$argv[$i]] = $argv[$i + 1]
        } else {
            $namedArgs[$argv[$i]] = $true
        }
    } else {
        # Positional argument, map it to the corresponding named parameter
        if ($positionalIndex -lt $paramMapping.Count) {
            $param = $paramMapping[$positionalIndex]
            $namedArgs[$param.Name] = $argv[$i]
            $positionalIndex++
        }
    }
}

# Ensure all required named parameters are present (only those with a Default not equal to $false)
foreach ($param in $paramMapping) {
    if ($param.Mandatory -and -not $namedArgs.ContainsKey($param.Name)) {
        $namedArgs[$param.Name] = $param.Default
    }
}

# Remove local-only parameters from the final argument list
$localParams = @('-Help', '-Detail', '-DryRun')
$finalArgs = @()
foreach ($key in $namedArgs.Keys) {
    if ($localParams -notcontains $key) {
        $finalArgs += $key
        if ($namedArgs[$key] -ne $true) {
            $finalArgs += $namedArgs[$key]
        }
    }
}

# --- Determine path to scoop checkver script --- 
$SCOOPROOT = scoop prefix scoop
$checkverPath = Join-Path $SCOOPROOT 'bin\checkver.ps1'
if (-not (Test-Path $checkverPath)) {
    Write-Error "Could not find checkver.ps1 at expected path: $checkverPath"
    exit 1
}
# Detail output if requested ---
if ($LocalOnlyParams.Detail) {
    Write-Host "DETAIL MODE:"
    Write-Host "  ArgLine: $ArgLine"
    Write-Host "  Parsed argv:"
    # Find max length for argument values for alignment
    $maxArgLen = 0
    for ($i = 0; $i -lt $argv.Count; $i++) {
        if ($argv[$i].Length -gt $maxArgLen) { $maxArgLen = $argv[$i].Length }
    }
    for ($i = 0; $i -lt $argv.Count; $i++) {
        $pad = ' ' * ($maxArgLen - $argv[$i].Length)
        Write-Host ("    {0}{1}" -f $argv[$i], $pad)
    }
    Write-Host "  Named arguments:"
    foreach ($key in $namedArgs.Keys) {
        Write-Host "    $key = $($namedArgs[$key])"
    }
    Write-Host "  Final arguments passed to checkver.ps1:"
    Write-Host "    $($finalArgs -join ' ')"
    Write-Host "  LocalOnlyParams: $(($LocalOnlyParams.GetEnumerator() | ForEach-Object { "$($_.Key)=$($_.Value)" }) -join ', ')"
    Write-Host "  Command: & `"$checkverPath`" $($finalArgs -join ' ')"
}

# Execute checkver.ps1 with the final argument list ---
if ($LocalOnlyParams.DryRun) {
    Write-Host "DRY RUN Arguments: $($finalArgs -join ' ')"
    exit 0
} else {
    & $checkverPath @finalArgs
}
