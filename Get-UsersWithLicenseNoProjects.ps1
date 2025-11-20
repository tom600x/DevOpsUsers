#Requires -Version 5.1

<#
.SYNOPSIS
    Identifies Azure DevOps users with license levels who are not assigned to any projects.

.DESCRIPTION
    This script analyzes a licensed CSV file (created by Update-DevOpsUserLicenses.ps1) to find users
    who have valid license assignments but are not currently assigned to any projects. This helps
    identify potentially unused licenses that could be reassigned or removed for cost optimization.
    
    The script creates a detailed report showing users with licenses but no project assignments,
    along with license value analysis for cost optimization insights.

.PARAMETER CsvFilePath
    Path to the licensed CSV file created by Update-DevOpsUserLicenses.ps1.

.PARAMETER OutputPath
    Optional. Directory where the report files will be saved. Defaults to same directory as input.

.PARAMETER MinimumLicenseValue
    Optional. Filter to show only licenses above a certain value tier. Options: 'All', 'Basic', 'Professional', 'Enterprise'.
    Default is 'All' to show all license levels.

.PARAMETER IncludeLicenseSummary
    Optional. Include a summary report with license cost analysis by type.

.EXAMPLE
    .\Get-UsersWithLicenseNoProjects.ps1 -CsvFilePath ".\output\devops-users-projects-2025-11-14-1128-LICENSED-2025-11-14-1129.csv"

.EXAMPLE
    .\Get-UsersWithLicenseNoProjects.ps1 -CsvFilePath ".\output\devops-users-projects-2025-11-14-1128-LICENSED-2025-11-14-1129.csv" -MinimumLicenseValue "Professional" -IncludeLicenseSummary

.NOTES
    Author: GitHub Copilot
    Version: 1.0
    Created: November 2025
    
    This script is designed to work with CSV files created by the two-script DevOps user reporting solution.
    Use this for license optimization and cost analysis.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({
        if (-not (Test-Path $_)) { throw "CSV file not found: $_" }
        $true
    })]
    [string]$CsvFilePath,
    
    [Parameter(Mandatory = $false)]
    [string]$OutputPath,
    
    [Parameter(Mandatory = $false)]
    [ValidateSet('All', 'Basic', 'Professional', 'Enterprise')]
    [string]$MinimumLicenseValue = 'All',
    
    [Parameter(Mandatory = $false)]
    [switch]$IncludeLicenseSummary
)

# Set output path if not provided
if (-not $OutputPath) {
    $OutputPath = Split-Path $CsvFilePath -Parent
}

# License value hierarchy for filtering
$LicenseHierarchy = @{
    'Stakeholder' = 0
    'Basic' = 1
    'Basic + Test Plans' = 2
    'Visual Studio Professional subscription' = 3
    'VS Test Pro with MSDN' = 3
    'Visual Studio Subscriber' = 3
    'Visual Studio Enterprise subscription' = 4
}

$MinimumValueMap = @{
    'All' = -1
    'Basic' = 1
    'Professional' = 3
    'Enterprise' = 4
}

Write-Host "Starting licensed users with no projects analysis..." -ForegroundColor Green
Write-Host "Input CSV: $CsvFilePath" -ForegroundColor Cyan
Write-Host "Minimum License Level: $MinimumLicenseValue" -ForegroundColor Cyan

try {
    # Step 1: Load and validate the CSV file
    Write-Host "`nStep 1: Loading licensed CSV file..." -ForegroundColor Yellow
    $AllUsers = Import-Csv -Path $CsvFilePath
    Write-Host "Loaded $($AllUsers.Count) users from CSV" -ForegroundColor Green
    
    # Validate CSV structure
    $requiredColumns = @('User ID', 'User Name', 'Email', 'License Level', 'Project Count')
    $csvColumns = $AllUsers[0].PSObject.Properties.Name
    $missingColumns = $requiredColumns | Where-Object { $_ -notin $csvColumns }
    
    if ($missingColumns.Count -gt 0) {
        Write-Error "CSV file missing required columns: $($missingColumns -join ', ')"
        exit 1
    }
    
    # Step 2: Filter users with licenses but no projects
    Write-Host "`nStep 2: Identifying users with licenses but no projects..." -ForegroundColor Yellow
    
    # Get users with valid licenses (not "License Not Found" or "Not Retrieved")
    $UsersWithLicenses = $AllUsers | Where-Object { 
        $_.'License Level' -notin @('License Not Found', 'Not Retrieved', '') -and
        $_.'License Level' -ne $null
    }
    
    # Filter to users with no projects (Project Count = 0 or empty/null Project Names)
    $LicensedUsersNoProjects = $UsersWithLicenses | Where-Object {
        ([int]$_.'Project Count') -eq 0 -or 
        [string]::IsNullOrWhiteSpace($_.'Project Names')
    }
    
    Write-Host "Users with valid licenses: $($UsersWithLicenses.Count)" -ForegroundColor White
    Write-Host "Licensed users with no projects: $($LicensedUsersNoProjects.Count)" -ForegroundColor White
    
    # Step 3: Apply minimum license value filter if specified
    if ($MinimumLicenseValue -ne 'All') {
        Write-Host "`nStep 3: Applying minimum license value filter ($MinimumLicenseValue)..." -ForegroundColor Yellow
        $MinValue = $MinimumValueMap[$MinimumLicenseValue]
        
        $FilteredUsers = $LicensedUsersNoProjects | Where-Object {
            $licenseValue = $LicenseHierarchy[$_.'License Level']
            if ($licenseValue -eq $null) { $licenseValue = 0 }  # Unknown licenses treated as lowest value
            $licenseValue -ge $MinValue
        }
        
        Write-Host "Users after license value filter: $($FilteredUsers.Count)" -ForegroundColor White
        $LicensedUsersNoProjects = $FilteredUsers
    } else {
        Write-Host "`nStep 3: No license value filtering applied (showing all license levels)" -ForegroundColor Yellow
    }
    
    # Step 4: Generate detailed report
    Write-Host "`nStep 4: Generating detailed report..." -ForegroundColor Yellow
    
    $Timestamp = Get-Date -Format "yyyy-MM-dd-HHmm"
    $InputFileName = [System.IO.Path]::GetFileNameWithoutExtension($CsvFilePath)
    $ReportPath = Join-Path $OutputPath "licensed-users-no-projects-$Timestamp.csv"
    
    if ($LicensedUsersNoProjects.Count -gt 0) {
        # Add additional analysis columns
        $EnhancedReport = $LicensedUsersNoProjects | ForEach-Object {
            $licenseValue = $LicenseHierarchy[$_.'License Level']
            if ($licenseValue -eq $null) { $licenseValue = 0 }
            
            [PSCustomObject]@{
                'User ID' = $_.'User ID'
                'User Name' = $_.'User Name'
                'Email' = $_.'Email'
                'License Level' = $_.'License Level'
                'License Value Tier' = $licenseValue
                'Project Count' = $_.'Project Count'
                'Project Names' = $_.'Project Names'
                'Potential Cost Saving' = switch ($_.'License Level') {
                    'Visual Studio Enterprise subscription' { 'High' }
                    'Visual Studio Professional subscription' { 'Medium' }
                    'VS Test Pro with MSDN' { 'Medium' }
                    'Visual Studio Subscriber' { 'Medium' }
                    'Basic + Test Plans' { 'Low' }
                    'Basic' { 'Low' }
                    'Stakeholder' { 'Minimal' }
                    default { 'Unknown' }
                }
                'Recommendation' = switch ($_.'License Level') {
                    'Visual Studio Enterprise subscription' { 'Review for downgrade or removal' }
                    'Visual Studio Professional subscription' { 'Consider downgrade to Basic if no dev work' }
                    'VS Test Pro with MSDN' { 'Review testing requirements' }
                    'Visual Studio Subscriber' { 'Review subscription usage' }
                    'Basic + Test Plans' { 'Review test plan usage' }
                    'Basic' { 'Consider Stakeholder if read-only access sufficient' }
                    'Stakeholder' { 'Minimal cost - review if access needed' }
                    default { 'Review license necessity' }
                }
            }
        }
        
        $EnhancedReport | Sort-Object 'License Value Tier', 'User Name' -Descending | 
            Export-Csv -Path $ReportPath -NoTypeInformation -Encoding UTF8
        
        Write-Host "Detailed report exported: $ReportPath" -ForegroundColor Green
        Write-Host "Records in report: $($EnhancedReport.Count)" -ForegroundColor Cyan
    } else {
        Write-Host "No users found matching criteria - no report file created" -ForegroundColor Yellow
    }
    
    # Step 5: Generate license summary if requested
    if ($IncludeLicenseSummary) {
        Write-Host "`nStep 5: Generating license cost summary..." -ForegroundColor Yellow
        
        $SummaryPath = Join-Path $OutputPath "license-cost-summary-$Timestamp.csv"
        
        # Group by license type
        $LicenseGroups = $LicensedUsersNoProjects | Group-Object 'License Level' | Sort-Object Count -Descending
        
        $CostSummary = $LicenseGroups | ForEach-Object {
            $potentialSaving = switch ($_.Name) {
                'Visual Studio Enterprise subscription' { 'High' }
                'Visual Studio Professional subscription' { 'Medium' }
                'VS Test Pro with MSDN' { 'Medium' }
                'Visual Studio Subscriber' { 'Medium' }
                'Basic + Test Plans' { 'Low' }
                'Basic' { 'Low' }
                'Stakeholder' { 'Minimal' }
                default { 'Unknown' }
            }
            
            [PSCustomObject]@{
                'License Type' = $_.Name
                'Unused Count' = $_.Count
                'Potential Saving Level' = $potentialSaving
                'Priority for Review' = switch ($potentialSaving) {
                    'High' { 1 }
                    'Medium' { 2 }
                    'Low' { 3 }
                    'Minimal' { 4 }
                    default { 5 }
                }
                'Recommendation' = switch ($_.Name) {
                    'Visual Studio Enterprise subscription' { 'Immediate review - highest cost licenses' }
                    'Visual Studio Professional subscription' { 'Review for potential downgrade' }
                    'VS Test Pro with MSDN' { 'Assess testing tool requirements' }
                    'Visual Studio Subscriber' { 'Review subscription benefits usage' }
                    'Basic + Test Plans' { 'Review test planning needs' }
                    'Basic' { 'Consider downgrade to Stakeholder' }
                    'Stakeholder' { 'Low priority - minimal cost' }
                    default { 'General review recommended' }
                }
            }
        }
        
        $CostSummary | Sort-Object 'Priority for Review' | Export-Csv -Path $SummaryPath -NoTypeInformation -Encoding UTF8
        Write-Host "License cost summary exported: $SummaryPath" -ForegroundColor Green
    }
    
    # Step 6: Display results summary
    Write-Host "`nStep 6: Analysis summary..." -ForegroundColor Yellow
    
    if ($LicensedUsersNoProjects.Count -gt 0) {
        Write-Host "`nLicense distribution for users with no projects:" -ForegroundColor Cyan
        $LicensedUsersNoProjects | Group-Object 'License Level' | Sort-Object Count -Descending | ForEach-Object {
            $costLevel = switch ($_.Name) {
                'Visual Studio Enterprise subscription' { ' (HIGH COST)' }
                'Visual Studio Professional subscription' { ' (MEDIUM COST)' }
                'VS Test Pro with MSDN' { ' (MEDIUM COST)' }
                'Visual Studio Subscriber' { ' (MEDIUM COST)' }
                default { '' }
            }
            Write-Host "  $($_.Name): $($_.Count) users$costLevel" -ForegroundColor White
        }
        
        # Highlight high-value licenses
        $HighValueLicenses = $LicensedUsersNoProjects | Where-Object { 
            $_.'License Level' -in @('Visual Studio Enterprise subscription', 'Visual Studio Professional subscription') 
        }
        
        if ($HighValueLicenses.Count -gt 0) {
            Write-Host "`n⚠️  HIGH-VALUE LICENSES WITHOUT PROJECTS: $($HighValueLicenses.Count)" -ForegroundColor Red
            Write-Host "These licenses may represent significant cost savings opportunities." -ForegroundColor Yellow
        }
    }
    
    # Final summary
    Write-Host "`n" + "="*60 -ForegroundColor Green
    Write-Host "LICENSED USERS WITH NO PROJECTS ANALYSIS COMPLETED" -ForegroundColor Green
    Write-Host "="*60 -ForegroundColor Green
    Write-Host "Input file: $CsvFilePath" -ForegroundColor Cyan
    Write-Host "Total users analyzed: $($AllUsers.Count)" -ForegroundColor Cyan
    Write-Host "Users with valid licenses: $($UsersWithLicenses.Count)" -ForegroundColor Cyan
    Write-Host "Licensed users with no projects: $($LicensedUsersNoProjects.Count)" -ForegroundColor Cyan
    if ($LicensedUsersNoProjects.Count -gt 0) {
        Write-Host "Detailed report: $ReportPath" -ForegroundColor Cyan
        if ($IncludeLicenseSummary) {
            Write-Host "Cost summary: $SummaryPath" -ForegroundColor Cyan
        }
    }
    Write-Host "="*60 -ForegroundColor Green

}
catch {
    Write-Error "Script execution failed: $($_.Exception.Message)"
    Write-Host "Stack Trace:" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}