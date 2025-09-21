<#
.SYNOPSIS
Installs a specified application from a local Scoop bucket.

.DESCRIPTION
This script adds a local Scoop bucket named 'mycorp' and installs the specified application from that bucket. It then displays the path to the installed application's executable.

.PARAMETER App
The name of the application to install from the local Scoop bucket.

.EXAMPLE
.\Test-Install.ps1 -App myapp

.NOTES
- Assumes Scoop is already installed and available in the system PATH.
- The script determines the bucket root based on the script's location.
#>
param([string]$App)
$bucketRoot = Split-Path $PSScriptRoot -Parent
scoop bucket add meibye $bucketRoot
scoop install $App
scoop which $App
