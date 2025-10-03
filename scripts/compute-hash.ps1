<#
.SYNOPSIS
    Computes the SHA256 hash of a specified file.

.DESCRIPTION
    This script takes a file path as a parameter, verifies the file exists, and outputs its SHA256 hash using Get-FileHash.

.PARAMETER Path
    The path to the file for which to compute the SHA256 hash.

.EXAMPLE
    .\compute-hash.ps1 -Path 'C:\path\to\file.txt'
#>

param(
    [Parameter(Mandatory=$true, Position=0)]
    [string]$Path
)

if (-not (Test-Path $Path -PathType Leaf)) {
    Write-Error "File not found: $Path"
    exit 1
}

$hash = Get-FileHash -Path $Path -Algorithm SHA256
Write-Output $hash.Hash
