<#
.SYNOPSIS
    Creates shims for scripts in a directory tree for various app families, supporting PowerShell, Python, batch, and shell scripts.

.DESCRIPTION
    Scans a root directory (default: C:\Tools\apps) for app families and their apps, then creates Scoop shims for scripts found in each app's 'current' directory and its plugins.
    Shims are created using Scoop's 'shim add' command, with interpreter detection for PowerShell, Python, Git Bash, and WSL.
    The script supports filtering by family, including version in shim names, and dry-run mode.
    It outputs a summary CSV map and a state file listing all created shims to the specified bucket folder (default: D:\Dev\meibye-bucket\bucket).
    If -VerboseHost is specified, the script prints detailed information about major function calls, parameters, decisions, and exits to the host.

.PARAMETER Root
    (Optional) Root directory to scan for app families. Default: C:\Tools\apps

.PARAMETER OutBucket
    (Optional) Output bucket folder where produced Scoop manifests and summary/state files are placed. Default: D:\Dev\meibye-bucket\bucket

.PARAMETER Families
    (Optional) Comma-separated list of families to include (e.g., 'onemore,py,ps'). Overrides $env:MEIBYE_META_FAMILIES if set.

.PARAMETER IncludeVersion
    (Optional) Switch to include version in shim name. Overrides $env:MEIBYE_META_INCLUDE_VERSION if set.

.PARAMETER DryRun
    (Optional) Switch to only print plan and write summary map, without creating shims. Overrides $env:MEIBYE_META_DRYRUN if set.

.PARAMETER VerboseHost
    (Optional) Switch to enable verbose output to the host, showing major function calls, parameter values, decisions, and exits.

.OUTPUTS
    - shims.txt: List of created shims (in OutBucket).
    - shims-map.csv: CSV summary of all shims and their properties (in OutBucket).

.NOTES
    - Requires Scoop to be installed and available in PATH.
    - Supports PowerShell, Python, batch, and shell scripts.
    - Handles plugin scripts recursively.
    - Avoids shim name collisions by appending -2, -3, etc.

.EXAMPLE
    # Run normally
    .\apps-bucket-scan.ps1

    # Dry run, only for 'py' and 'ps' families, include version in shim name
    .\apps-bucket-scan.ps1 -Families 'py,ps' -IncludeVersion -DryRun

    # Run with verbose host output
    .\apps-bucket-scan.ps1 -VerboseHost
#>

param(
    [string]$Root = 'C:\Tools\apps',
    [string]$OutBucket = 'D:\Dev\meibye-bucket\bucket',
    [string]$Families,
    [switch]$IncludeVersion,
    [switch]$DryRun,
    [switch]$VerboseHost  # Optional: enable verbose output to host
)

$ErrorActionPreference = 'Stop'

# Controls: allow both env and param, param takes precedence
$envFamilies = if ($Families) { $Families } else { $env:MEIBYE_META_FAMILIES }
$envIncludeVersion = if ($IncludeVersion.IsPresent) { $true } elseif ($env:MEIBYE_META_INCLUDE_VERSION -eq '1') { $true } else { $false }
$envDryRun = if ($DryRun.IsPresent) { $true } elseif ($env:MEIBYE_META_DRYRUN -eq '1') { $true } else { $false }

# Output control values
Write-Host "Shim creation controls:"
Write-Host "  Root: $Root"
Write-Host "  Families: $envFamilies"
Write-Host "  IncludeVersion: $envIncludeVersion"
Write-Host "  DryRun: $envDryRun"

# Parse families into array
if ($envFamilies) {
    $familiesList = $envFamilies -split ',' | ForEach-Object { $_.Trim() } | Where-Object { $_ }
} else {
    $familiesList = @()
}

$includeVersion = [bool]($IncludeVersion.IsPresent -or $envIncludeVersion)
$isDryRun = [bool]($DryRun.IsPresent -or $envDryRun)

$stateDir = $OutBucket
New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
$stateFile = Join-Path $stateDir 'shims.txt'
$mapFile = Join-Path $stateDir 'shims-map.csv'
if (Test-Path $stateFile) { Remove-Item $stateFile -Force }
if (Test-Path $mapFile) { Remove-Item $mapFile -Force }

function Write-VerboseHost {
    param(
        [string]$Function,
        [string]$Message,
        [int]$Line = $MyInvocation.ScriptLineNumber
    )
    if ($script:VerboseHost) {
        Write-Host "[${Function}:${Line}] $Message"
    }
}

# Writes the name of a created shim to the state file, unless in dry-run mode.
function Write-State([string]$name) {
    Write-VerboseHost -Function "Write-State" -Message "Called with name=$name"
    if (-not $isDryRun) { Add-Content -Path $stateFile -Value $name }
    Write-VerboseHost -Function "Write-State" -Message "Exit"
}

# Initializes the CSV summary map file with the header row.
function Initialize-Map() {
    Write-VerboseHost -Function "Initialize-Map" -Message "Called"
    'shim,type,family,app,tool,leaf,ext,version,interpreter,target,isDryRun' | Out-File -Encoding UTF8 $mapFile
    Write-VerboseHost -Function "Initialize-Map" -Message "Exit"
}

# Appends a row to the CSV summary map file for each shim, including its properties.
function Write-Map($shim,$type,$family,$app,$tool,$leaf,$ext,$ver,$interp,$target) {
    Write-VerboseHost -Function "Write-Map" -Message "Called with shim=$shim, type=$type, family=$family, app=$app, tool=$tool, leaf=$leaf, ext=$ext, ver=$ver, interp=$interp, target=$target"
    $row = @($shim,$type,$family,$app,$tool,$leaf,$ext,$ver,$interp,$target,([int]$isDryRun)) -join ','
    Add-Content -Path $mapFile -Value $row
    Write-VerboseHost -Function "Write-Map" -Message "Exit"
}

# Detect interpreters
$pwsh = (Get-Command pwsh.exe -ErrorAction SilentlyContinue)?.Source
if (-not $pwsh) { $pwsh = (Get-Command powershell.exe -ErrorAction SilentlyContinue)?.Source }
$py = (Get-Command py.exe -ErrorAction SilentlyContinue)?.Source
$python = (Get-Command python.exe -ErrorAction SilentlyContinue)?.Source
$gitBash = 'C:\Program Files\Git\bin\bash.exe'
$hasGitBash = Test-Path $gitBash
$hasWsl = [bool](Get-Command wsl.exe -ErrorAction SilentlyContinue)

# Adds a Scoop shim for the given script path, unless in dry-run mode.
function Add-Shim($shim,$path) {
    Write-VerboseHost -Function "Add-Shim" -Message "Called with shim=$shim, path=$path"
    if ($isDryRun) { Write-VerboseHost -Function "Add-Shim" -Message "Dry run, skipping actual shim add"; return }
    scoop shim add $shim $path | Out-Null
    Write-VerboseHost -Function "Add-Shim" -Message "Exit"
}

# Adds a Scoop shim for the given executable and arguments, unless in dry-run mode.
function Add-Shim-Args($shim,$exe,$shimArgs) {
    Write-VerboseHost -Function "Add-Shim-Args" -Message "Called with shim=$shim, exe=$exe, shimArgs=$shimArgs"
    if ($isDryRun) { Write-VerboseHost -Function "Add-Shim-Args" -Message "Dry run, skipping actual shim add"; return }
    # scoop shim add $shim $exe $shimArgs | Out-Null
    Write-Host scoop shim add $shim $exe $shimArgs
    scoop shim add $shim $exe $shimArgs
    Write-VerboseHost -Function "Add-Shim-Args" -Message "Exit"
}

# Resolves the version string for an app by inspecting the 'current' symlink or folder.
function Resolve-Version($currentPath) {
    Write-VerboseHost -Function "Resolve-Version" -Message "Called with currentPath=$currentPath"
    try {
        $it = Get-Item -LiteralPath $currentPath -ErrorAction Stop
        if ($it.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            $t = (Get-Item -LiteralPath $currentPath).Target
            if ($t) {
                Write-VerboseHost -Function "Resolve-Version" -Message "Found symlink target: $t"
                return Split-Path -Leaf $t
            }
        }
    } catch {
        Write-VerboseHost -Function "Resolve-Version" -Message "Exception: $_"
    }
    Write-VerboseHost -Function "Resolve-Version" -Message "Fallback: returning empty string"
    return ''
}

# Constructs a shim name based on family, app, plugin, leaf, and version.
function New-ShimName($family,$app,$plugin,$leaf,$ver) {
    Write-VerboseHost -Function "New-ShimName" -Message "Called with family=$family, app=$app, plugin=$plugin, leaf=$leaf, ver=$ver"
    $base = if ($plugin) { "$family-$plugin-$leaf" } else { "$family-$app-$leaf" }
    if ($includeVersion -and $ver) { 
        Write-VerboseHost -Function "New-ShimName" -Message "Including version in shim name"
        return ("$base-v$ver")
    }
    Write-VerboseHost -Function "New-ShimName" -Message "Exit with base=$base"
    return $base
}

# Ensures shim name uniqueness by appending a numeric suffix if a collision is detected.
function Get-UniqueShimName($name) {
    Write-VerboseHost -Function "Get-UniqueShimName" -Message "Called with name=$name"
    $n = $name; $i = 2
    $shimsDir = Join-Path (scoop prefix scoop) 'shims'
    while (Test-Path (Join-Path $shimsDir ($n + '.exe'))) {
        Write-VerboseHost -Function "Get-UniqueShimName" -Message "Collision detected for $n, incrementing"
        $n = "$name-$i"; $i++
    }
    Write-VerboseHost -Function "Get-UniqueShimName" -Message "Exit with unique name $n"
    return $n
}

if (-not (Test-Path $Root)) { Write-Warning "Root not found: $Root"; return }

Get-ChildItem -Path $Root -Directory | ForEach-Object {
    $family = $_.Name
    Write-VerboseHost -Function "Family" -Message "Processing family: $family"
    if ($familiesList.Count -gt 0 -and ($familiesList -notcontains $family)) { 
        Write-VerboseHost -Function "Family" -Message "Skipping family $family (not in filter list)"
        return 
    }
    Get-ChildItem -Path $_.FullName -Directory | ForEach-Object {
        $app = $_.Name
        Write-VerboseHost -Function "App" -Message "Processing app: $app"
        $current = Join-Path $_.FullName 'current'
        if (!(Test-Path $current)) { 
            Write-VerboseHost -Function "App" -Message "Skipping app $app (no 'current' directory)"
            return 
        }
        $ver = Resolve-Version $current

        function Invoke-Files($files,$tool) {
            Write-VerboseHost -Function "Invoke-Files" -Message "Called with tool=$tool, files count=$($files.Count)"
            foreach ($f in $files) {
                $leaf = [IO.Path]::GetFileNameWithoutExtension($f.Name)
                $ext = $f.Extension.ToLower()
                $shimBase = New-ShimName $family $app $tool $leaf $ver
                $shim = Get-UniqueShimName $shimBase
                Write-VerboseHost -Function "Invoke-Files" -Message "Processing $($f.FullName) as $shim ($ext)"
                switch ($ext) {
                    '.ps1' {
                        $interp = 'pwsh'
                        if ($pwsh) { 
                            Write-VerboseHost -Function "Invoke-Files" -Message "Adding PowerShell shim for $($f.FullName) with pwsh"
                            Add-Shim-Args $shim $pwsh "-NoProfile -ExecutionPolicy Bypass -File `"$($f.FullName)`" -- %*" 
                        }
                        else { 
                            Write-VerboseHost -Function "Invoke-Files" -Message "Adding PowerShell shim for $($f.FullName) direct"
                            $interp = 'direct'; Add-Shim $shim $f.FullName 
                        }
                        Write-Map $shim 'root' $family $app $tool $leaf $ext $ver $interp $($f.FullName)
                        Write-State $shim
                    }
                    '.py' {
                        $interp = if ($py) { 'py' } elseif ($python) { 'python' } else { 'direct' }
                        if ($py) { 
                            Write-VerboseHost -Function "Invoke-Files" -Message "Adding Python shim for $($f.FullName) with py"
                            Add-Shim-Args $shim $py "-3 `"$($f.FullName)`" %*" 
                        }
                        elseif ($python) { 
                            Write-VerboseHost -Function "Invoke-Files" -Message "Adding Python shim for $($f.FullName) with python"
                            Add-Shim-Args $shim $python "`"$($f.FullName)`" %*" 
                        }
                        else { 
                            Write-VerboseHost -Function "Invoke-Files" -Message "Adding Python shim for $($f.FullName) direct"
                            Add-Shim $shim $f.FullName 
                        }
                        Write-Map $shim 'root' $family $app $tool $leaf $ext $ver $interp $($f.FullName)
                        Write-State $shim
                    }
                    '.cmd' { 
                        Write-VerboseHost -Function "Invoke-Files" -Message "Adding CMD shim for $($f.FullName)"
                        Add-Shim $shim $f.FullName
                        Write-Map $shim 'root' $family $app $tool $leaf $ext $ver 'direct' $($f.FullName)
                        Write-State $shim 
                    }
                    '.bat' { 
                        Write-VerboseHost -Function "Invoke-Files" -Message "Adding BAT shim for $($f.FullName)"
                        Add-Shim $shim $f.FullName
                        Write-Map $shim 'root' $family $app $tool $leaf $ext $ver 'direct' $($f.FullName)
                        Write-State $shim 
                    }
                    '.sh' {
                        if ($hasGitBash) {
                            Write-VerboseHost -Function "Invoke-Files" -Message "Adding SH shim for $($f.FullName) with Git Bash"
                            $posix = $f.FullName -replace '\\','/'
                            Add-Shim-Args $shim $gitBash "-c `"`"$posix`" %*`""
                            Write-Map $shim 'root' $family $app $tool $leaf $ext $ver 'git-bash' $($f.FullName)
                            Write-State $shim
                        } elseif ($hasWsl) {
                            Write-VerboseHost -Function "Invoke-Files" -Message "Adding SH shim for $($f.FullName) with WSL bash"
                            $posix = $f.FullName -replace '\\','/'
                            Add-Shim-Args $shim 'wsl.exe' "bash -lc `"`"$posix`" %*`""
                            Write-Map $shim 'root' $family $app $tool $leaf $ext $ver 'wsl-bash' $($f.FullName)
                            Write-State $shim
                        } else { 
                            Write-Warning "Skipping .sh: $($f.Name) — no Git Bash/WSL found" 
                            Write-VerboseHost -Function "Invoke-Files" -Message "Skipping SH file $($f.FullName) (no Git Bash/WSL found)"
                        }
                    }
                    '.zsh' {
                        if ($hasWsl) {
                            Write-VerboseHost -Function "Invoke-Files" -Message "Adding ZSH shim for $($f.FullName) with WSL zsh"
                            $posix = $f.FullName -replace '\\','/'
                            Add-Shim-Args $shim 'wsl.exe' "zsh -lc `"`"$posix`" %*`""
                            Write-Map $shim 'root' $family $app $tool $leaf $ext $ver 'wsl-zsh' $($f.FullName)
                            Write-State $shim
                        } else { 
                            Write-Warning "Skipping .zsh: $($f.Name) — no WSL zsh found" 
                            Write-VerboseHost -Function "Invoke-Files" -Message "Skipping ZSH file $($f.FullName) (no WSL zsh found)"
                        }
                    }
                }
            }
            Write-VerboseHost -Function "Invoke-Files" -Message "Exit"
        }

        # 1) Root-level scripts in current
        $rootFiles = Get-ChildItem -Path $current\* -File -Recurse -Include *.ps1,*.py,*.cmd,*.bat,*.sh,*.zsh -ErrorAction SilentlyContinue
        Write-VerboseHost -Function "App" -Message "Scanning root-level scripts in $current"
        Invoke-Files $rootFiles $null

        # 2) Tool scripts (was plugins)
        $tools = Join-Path $current 'plugins'
        if (Test-Path $tools) {
            Write-VerboseHost -Function "App" -Message "Scanning tools in $tools"
            Get-ChildItem -Path $tools -Directory | ForEach-Object {
                $tool = $_.Name
                Write-VerboseHost -Function "Tool" -Message "Processing tool: $tool"
                $tfiles = Get-ChildItem -Path $_.FullName -File -Recurse -Include *.ps1,*.py,*.cmd,*.bat,*.sh,*.zsh -ErrorAction SilentlyContinue
                Invoke-Files $tfiles $tool
            }
        } else {
            Write-VerboseHost -Function "App" -Message "No tools directory found in $current"
        }
    }
}

# Print summary information about the shim creation process and output files.
Write-Host ("Meta-shims " + ($(if($isDryRun){'planned'} else {'installed'}) + ". Summary map: " + $mapFile))
if (-not $isDryRun -and (Test-Path $stateFile)) {
    $n = (Get-Content $stateFile).Count
    Write-Host ("Created $n shims. State file: $stateFile")
}

