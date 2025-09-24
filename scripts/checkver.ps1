<#
.SYNOPSIS
    Runs Scoop's checkver.ps1 against your bucket for the apps-bucket-scan manifest.

.DESCRIPTION
    This script locates Scoop's own app folder, then runs checkver.ps1 for the apps-bucket-scan manifest in your bucket.
    All arguments are passed as a single string via the -Args parameter. The script splits this string into arguments, handles 'help' and 'verbose' locally, and passes the rest to checkver.ps1.
    If '-Dir <folder>' is not specified, it prepends '-Dir D:\Dev\meibye-bucket\bucket' to the arguments by default.

.PARAMETER Args
    String of arguments to pass. Handles 'help' and 'verbose' locally, passes the rest to checkver.ps1.
#>

param(
    [string]$Args = ""
)

# Split arguments
$argsList = @()
if ($Args) {
    # Split arguments on whitespace, but preserve quoted substrings
    $argsList = @()
    if ($Args) {
        # Properly escape single quotes inside the pattern for PowerShell
        $pattern = '("[^""]*"|''[^'']*''|\S+)'
        $matches = [regex]::Matches($Args, $pattern)
        foreach ($m in $matches) {
            $arg = $m.Value
            # Remove surrounding quotes if present
            if (($arg.StartsWith('"') -and $arg.EndsWith('"')) -or ($arg.StartsWith("'") -and $arg.EndsWith("'"))) {
                $arg = $arg.Substring(1, $arg.Length - 2)
            }
            $argsList += $arg
        }
    }
} else {
    $argsList = @()
}

# Handle help/verbose
$help = $false
$verbose = $false
$remainingArgs = @()
foreach ($a in $argsList) {
    if ($a -ieq '-help' -or $a -ieq '/?' -or $a -ieq '--help') { $help = $true }
    elseif ($a -ieq '-verbose' -or $a -ieq '--verbose') { $verbose = $true }
    else { $remainingArgs += $a }
}

# Get the path to Scoop's own app folder
$SCOOPROOT = scoop prefix scoop    # typically: ~\scoop\apps\scoop\current

if ($help) {
    $checkverPath = Join-Path $SCOOPROOT 'bin\checkver.ps1'
    if (Test-Path $checkverPath) {
        $lines = Get-Content $checkverPath

        # Extract .PARAMETER descriptions from comment block, skipping .EXAMPLE sections
        $paramDescs = @{}
        $inComment = $false
        $currentParam = $null
        $foundParams = @()
        $inExample = $false
        foreach ($line in $lines) {
            if ($line -match '^<#') { $inComment = $true; continue }
            if ($line -match '^#>') { $inComment = $false; break }
            if ($inComment) {
                if ($line -match '^\s*\.EXAMPLE') { $inExample = $true; $currentParam = $null; continue }
                if ($inExample) {
                    if ($line -match '^\s*$') { $inExample = $false }
                    continue
                }
                if ($line -match '^\s*\.PARAMETER\s+(\w+)') {
                    $currentParam = $Matches[1]
                    $paramDescs[$currentParam] = ""
                    $foundParams += $currentParam
                } elseif ($currentParam -and $line -match '^\s{4,}(.*\S.*)$') {
                    $paramDescs[$currentParam] += ($paramDescs[$currentParam] ? " " : "") + $Matches[1].Trim()
                } elseif ($currentParam -and $line -match '^\s*$') {
                    $currentParam = $null
                }
            }
        }

        Write-Host "USAGE: checkver.ps1 -Args '<params>'"
        Write-Host ""
        Write-Host "Parameters found in offical checkver.ps1:"
        $maxlen = 0
        foreach ($p in $foundParams) {
            $len = ("  -" + $p).Length
            if ($len -gt $maxlen) { $maxlen = $len }
        }
        foreach ($p in $foundParams) {
            $desc = $paramDescs[$p]
            $paramStr = "  -$p"
            if ($desc) {
                $pad = " " * ($maxlen - $paramStr.Length + 2)
                Write-Host ("$paramStr$pad$desc")
            } else {
                Write-Host $paramStr
            }
        }
        Write-Host ""
        Write-Host "Special wrapper arguments handled locally: -help, -verbose"
        Write-Host ""
        Write-Host "Example:"
        Write-Host "  .\checkver.ps1 -Args '-u -Dir D:\Dev\meibye-bucket\bucket'"
        Write-Host "  .\checkver.ps1 -Args '-help'"
    } else {
        Write-Host "Could not find checkver.ps1 at $checkverPath"
    }
    exit 0
}

# Default Dir logic: if -Dir is not present, insert default before verbose print
$dirIdx = $null
for ($i = 0; $i -lt $remainingArgs.Count; $i++) {
    if ($remainingArgs[$i] -ieq '-Dir' -and ($i + 1) -lt $remainingArgs.Count) {
        $dirIdx = $i
        break
    }
}
$hasValidDir = $false
if ($dirIdx -ne $null) {
    $dirValue = $remainingArgs[$dirIdx + 1]
    if ($dirValue -and (Test-Path $dirValue -PathType Container)) {
        $hasValidDir = $true
    }
}
if (-not $hasValidDir) {
    $remainingArgs = @('-Dir', 'D:\Dev\meibye-bucket\bucket') + $remainingArgs
}

if ($verbose) {
    Write-Host "PARAMETERS:"
    Write-Host "  Args: $Args"
    Write-Host "  Parsed: $($argsList -join ', ')"
    Write-Host "  Remaining: $($remainingArgs -join ', ')"
    Write-Host "  help: $help"
    Write-Host "  verbose: $verbose"
}

# Run checkver.ps1 against your bucket
& "$SCOOPROOT\bin\checkver.ps1" @remainingArgs
