<#
.SYNOPSIS
    Pester tests for checkver.ps1 wrapper script.

.DESCRIPTION
    This test suite verifies the main behaviors of checkver.ps1:
    - Handles -help and -verbose locally.
    - Normalizes argument order and inserts -Dir if missing.
    - Passes correct arguments to Scoop's checkver.ps1.
    - Prints help and parameter documentation when requested.
    - Handles positional and named arguments correctly.

.EXAMPLE
    Invoke-Pester -Path .\meibye-bucket\scripts\checkver.Tests.ps1
#>

# Pester tests for checkver.ps1
# See https://pester.dev/docs/quick-start

BeforeAll {
    $scriptPath = "D:\Dev\meibye-bucket\scripts\checkver.ps1"

    # define a function to write debug output given a message
    function Write-DebugLog {
        param (
            [string]$Message
        )
        Write-Host "[DEBUG] $Message"
    }   
}

Describe "checkver.ps1 wrapper" {
    
    Context "Help, Detail and DryRun flags" {
        It "prints dry run output when -dryrun is passed" {
            $result = $(powershell -NoProfile -File $scriptPath -DryRun -App apps-bucket-scan)
            ($result -join "`n") | Should -Match "DRY RUN Arguments: "
            ($result -join "`n") | Should -Match "-App apps-bucket-scan"
        }
        
        It "prints help and exits when -help is passed" {
            $result = $(powershell -NoProfile -File $scriptPath -Help)
            # Combine an array of strings into a single string
            ($result -join "`n") | Should -Match "USAGE: checkver.ps1 -Args '<params>'"
        }
        
        It "prints detail output when -detail is passed" {
            $result = $(powershell -NoProfile -File $scriptPath -DryRun -Detail)
            ($result -join "`n") | Should -Match "DETAIL MODE:"
            ($result -join "`n") | Should -Match "DRY RUN Arguments: "
        }
    }

    Context "Argument normalization and -Dir insertion" {
        It "inserts -Dir if missing" {
            $result = $(powershell -NoProfile -File $scriptPath -DryRun apps-bucket-scan)
            # Write-DebugLog "Result: $($result -join "`n")"
            ($result -join "`n") | Should -Match "-Dir D:\\Dev\\meibye-bucket\\bucket"
        }

        It "does not insert -Dir if already present" {
            $result = $(powershell -NoProfile -File $scriptPath -DryRun apps-bucket-scan -Dir C:\Other\Bucket)
            # Remember to escape backslashes in the regex pattern
            ($result -join "`n") | Should -Match "-Dir C:\\Other\\Bucket"
            ($result -join "`n") | Should -Not -Match "-Dir D:\\Dev\\meibye-bucket\\bucket"
        }
    }
    
    Context "Positional and named argument mapping" {
        It "maps positional arguments to named parameters" {
            $result = $(powershell -NoProfile -File $scriptPath -DryRun apps-bucket-scan)
            ($result -join "`n") | Should -Match "-App apps-bucket-scan"
        }
        
        It "passes named arguments through" {
            $result = $(powershell -NoProfile -File $scriptPath -DryRun -App myapp -Dir C:\Bucket)
            ($result -join "`n") | Should -Match "-App myapp"
            # Remember to escape backslashes in the regex pattern
            ($result -join "`n") | Should -Match "-Dir C:\\Bucket"
        }
    }

    Context "Integration with Scoop checkver.ps1" {
        It "calls scoop checkver.ps1 with normalized arguments" {
            $result = $(powershell -NoProfile -File $scriptPath -DryRun apps-bucket-scan)
            ($result -join "`n") | Should -Not -BeNullOrEmpty
        }
    }
}