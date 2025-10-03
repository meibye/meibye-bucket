<#
.SYNOPSIS
    Unblocks a specified file to allow script execution.

.DESCRIPTION
    This script takes a file path as a parameter, verifies the file exists, and removes the "blocked" status (Zone.Identifier) from the file using Unblock-File. This is useful for enabling execution of scripts downloaded from the internet.

.PARAMETER Path
    The path to the file to unblock.

.EXAMPLE
    .\unblock-script.ps1 -Path 'C:\path\to\file.ps1'
#>

param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$Path
)

if (-not (Test-Path $Path -PathType Leaf)) {
    Write-Error "File not found: $Path"
    exit 1
}

Unblock-File -Path $Path
