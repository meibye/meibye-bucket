<#
.SYNOPSIS
    Creates shims for scripts in a directory tree for various app families, supporting PowerShell, Python, batch, and shell scripts.

.DESCRIPTION
    Scans a root directory (default: C:\Tools\apps) for app families and their apps, then creates Scoop shims for scripts found in each app's 'current' directory and its plugins.
    Shims are created using Scoop's 'shim add' command, with interpreter detection for PowerShell, Python, Git Bash, and WSL.
    The script supports filtering by family, including version in shim names, and dry-run mode.
    It outputs a summary CSV map and a state file listing all created shims to the specified bucket folder (default: D:\Dev\meibye-bucket\bucket).

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
#>

param(
    [string]$Root = 'C:\Tools\apps',
    [string]$OutBucket = 'D:\Dev\meibye-bucket\bucket',
    [string]$Families,
    [switch]$IncludeVersion,
    [switch]$DryRun
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

$includeVersion = $envIncludeVersion
$dryRun = $envDryRun

$stateDir = $OutBucket
New-Item -ItemType Directory -Force -Path $stateDir | Out-Null
$stateFile = Join-Path $stateDir 'shims.txt'
$mapFile = Join-Path $stateDir 'shims-map.csv'
if (Test-Path $stateFile) { Remove-Item $stateFile -Force }
if (Test-Path $mapFile) { Remove-Item $mapFile -Force }

# Writes the name of a created shim to the state file, unless in dry-run mode.
function Write-State([string]$name) { if (-not $dryRun) { Add-Content -Path $stateFile -Value $name } }

# Initializes the CSV summary map file with the header row.
function Initialize-Map() { 'shim,type,family,app,plugin,leaf,ext,version,interpreter,target,dryrun' | Out-File -Encoding UTF8 $mapFile }

# Appends a row to the CSV summary map file for each shim, including its properties.
function Write-Map($shim,$type,$family,$app,$plugin,$leaf,$ext,$ver,$interp,$target) {
    $row = @($shim,$type,$family,$app,$plugin,$leaf,$ext,$ver,$interp,$target,([int]$dryRun)) -join ','
    Add-Content -Path $mapFile -Value $row
}

Initialize-Map

# Detect interpreters
$pwsh = (Get-Command pwsh.exe -ErrorAction SilentlyContinue)?.Source
if (-not $pwsh) { $pwsh = (Get-Command powershell.exe -ErrorAction SilentlyContinue)?.Source }
$py = (Get-Command py.exe -ErrorAction SilentlyContinue)?.Source
$python = (Get-Command python.exe -ErrorAction SilentlyContinue)?.Source
$gitBash = 'C:\Program Files\Git\bin\bash.exe'
$hasGitBash = Test-Path $gitBash
$hasWsl = [bool](Get-Command wsl.exe -ErrorAction SilentlyContinue)

# Adds a Scoop shim for the given script path, unless in dry-run mode.
function Add-Shim($shim,$path) { if ($dryRun) { return } ; scoop shim add $shim $path | Out-Null }

# Adds a Scoop shim for the given executable and arguments, unless in dry-run mode.
function Add-Shim-Args($shim,$exe,$shimArgs) { if ($dryRun) { return } ; scoop shim add $shim $exe $shimArgs | Out-Null }

# Resolves the version string for an app by inspecting the 'current' symlink or folder.
function Resolve-Version($currentPath) {
    try {
        $it = Get-Item -LiteralPath $currentPath -ErrorAction Stop
        if ($it.Attributes -band [IO.FileAttributes]::ReparsePoint) {
            $t = (Get-Item -LiteralPath $currentPath).Target
            if ($t) { return Split-Path -Leaf $t }
        }
    } catch { }
    # Fallback: last non-'current' segment if path is already a version folder
    return ''
}

# Constructs a shim name based on family, app, plugin, leaf, and version.
function New-ShimName($family,$app,$plugin,$leaf,$ver) {
    $base = if ($plugin) { "$family-$plugin-$leaf" } else { "$family-$app-$leaf" }
    if ($includeVersion -and $ver) { return ("$base-v$ver") }
    return $base
}

# Ensures shim name uniqueness by appending a numeric suffix if a collision is detected.
function Get-UniqueShimName($name) {
    # Avoid collisions by appending -2, -3, ... if shim already exists
    $n = $name; $i = 2
    $shimsDir = Join-Path (scoop prefix scoop) 'shims'
    while (Test-Path (Join-Path $shimsDir ($n + '.exe'))) { $n = "$name-$i"; $i++ }
    return $n
}

if (-not (Test-Path $Root)) { Write-Warning "Root not found: $Root"; return }

Get-ChildItem -Path $Root -Directory | ForEach-Object {
    $family = $_.Name
    if ($familiesList.Count -gt 0 -and ($familiesList -notcontains $family)) { return }
    Get-ChildItem -Path $_.FullName -Directory | ForEach-Object {
        $app = $_.Name
        $current = Join-Path $_.FullName 'current'
        if (!(Test-Path $current)) { return }
        $ver = Resolve-Version $current

        function Invoke-Files($files,$pluginName) {
            foreach ($f in $files) {
                $leaf = [IO.Path]::GetFileNameWithoutExtension($f.Name)
                $ext = $f.Extension.ToLower()
                $shimBase = New-ShimName $family $app $pluginName $leaf $ver
                $shim = Get-UniqueShimName $shimBase
                switch ($ext) {
                    '.ps1' {
                        $interp = 'pwsh'
                        if ($pwsh) { Add-Shim-Args $shim $pwsh "-NoProfile -ExecutionPolicy Bypass -File `"$($f.FullName)`" -- %*" }
                        else { $interp = 'direct'; Add-Shim $shim $f.FullName }
                        Write-Map $shim 'root' $family $app $pluginName $leaf $ext $ver $interp $($f.FullName)
                        Write-State $shim
                    }
                    '.py' {
                        $interp = if ($py) { 'py' } elseif ($python) { 'python' } else { 'direct' }
                        if ($py) { Add-Shim-Args $shim $py "-3 `"$($f.FullName)`" %*" }
                        elseif ($python) { Add-Shim-Args $shim $python "`"$($f.FullName)`" %*" }
                        else { Add-Shim $shim $f.FullName }
                        Write-Map $shim 'root' $family $app $pluginName $leaf $ext $ver $interp $($f.FullName)
                        Write-State $shim
                    }
                    '.cmd' { Add-Shim $shim $f.FullName; Write-Map $shim 'root' $family $app $pluginName $leaf $ext $ver 'direct' $($f.FullName); Write-State $shim }
                    '.bat' { Add-Shim $shim $f.FullName; Write-Map $shim 'root' $family $app $pluginName $leaf $ext $ver 'direct' $($f.FullName); Write-State $shim }
                    '.sh' {
                        if ($hasGitBash) {
                            $posix = $f.FullName -replace '\\','/'
                            Add-Shim-Args $shim $gitBash "-c `"`"$posix`" %*`""
                            Write-Map $shim 'root' $family $app $pluginName $leaf $ext $ver 'git-bash' $($f.FullName)
                            Write-State $shim
                        } elseif ($hasWsl) {
                            $posix = $f.FullName -replace '\\','/'
                            Add-Shim-Args $shim 'wsl.exe' "bash -lc `"`"$posix`" %*`""
                            Write-Map $shim 'root' $family $app $pluginName $leaf $ext $ver 'wsl-bash' $($f.FullName)
                            Write-State $shim
                        } else { Write-Warning "Skipping .sh: $($f.Name) — no Git Bash/WSL found" }
                    }
                    '.zsh' {
                        if ($hasWsl) {
                            $posix = $f.FullName -replace '\\','/'
                            Add-Shim-Args $shim 'wsl.exe' "zsh -lc `"`"$posix`" %*`""
                            Write-Map $shim 'root' $family $app $pluginName $leaf $ext $ver 'wsl-zsh' $($f.FullName)
                            Write-State $shim
                        } else { Write-Warning "Skipping .zsh: $($f.Name) — no WSL zsh found" }
                    }
                }
            }
        }

        # 1) Root-level scripts in current
        $rootFiles = Get-ChildItem -Path $current -File -Include *.ps1,*.py,*.cmd,*.bat,*.sh,*.zsh -ErrorAction SilentlyContinue
        Invoke-Files $rootFiles $null

        # 2) Plugin scripts
        $plugins = Join-Path $current 'plugins'
        if (Test-Path $plugins) {
            Get-ChildItem -Path $plugins -Directory | ForEach-Object {
                $plugin = $_.Name
                $pfiles = Get-ChildItem -Path $_.FullName -File -Recurse -Include *.ps1,*.py,*.cmd,*.bat,*.sh,*.zsh -ErrorAction SilentlyContinue
                Invoke-Files $pfiles $plugin
            }
        }
    }
}

# Print summary information about the shim creation process and output files.
Write-Host ("Meta-shims " + ($(if($dryRun){'planned'} else {'installed'}) + ". Summary map: " + $mapFile))
if (-not $dryRun -and (Test-Path $stateFile)) {
    $n = (Get-Content $stateFile).Count
    Write-Host ("Created $n shims. State file: $stateFile")
}

