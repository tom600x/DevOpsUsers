#Requires -Version 5.1

<#
.SYNOPSIS
    Exports Azure DevOps users and their project assignments to CSV (without license information).

.DESCRIPTION
    This script connects to Azure DevOps Services and exports all users with their project assignments.
    License information is intentionally excluded and should be added using the companion script
    Update-DevOpsUserLicenses.ps1.
    
    This script focuses solely on user and project data collection, making it more reliable for
    large organizations where license API calls may fail.

.PARAMETER OrganizationUrl
    The URL of the Azure DevOps organization (e.g., "https://dev.azure.com/YourOrg").

.PARAMETER PersonalAccessToken
    Personal Access Token with permissions to read user entitlements and projects.
    Required permissions: User Entitlements (Read), Project and Team (Read).

.PARAMETER OutputPath
    Optional. Directory where the CSV file will be saved. Defaults to "output" subdirectory.

.PARAMETER ShowUsersWithoutProjects
    Optional. Include users who are not assigned to any projects in the main CSV.

.PARAMETER ExportUsersWithoutProjects
    Optional. Create a separate CSV file for users without project assignments.

.EXAMPLE
    .\Get-DevOpsUsersAndProjects.ps1 -OrganizationUrl "https://dev.azure.com/YourOrg" -PersonalAccessToken "your-pat-here"

.EXAMPLE
    .\Get-DevOpsUsersAndProjects.ps1 -OrganizationUrl "https://dev.azure.com/YourOrg" -PersonalAccessToken "your-pat-here" -ShowUsersWithoutProjects -ExportUsersWithoutProjects

.NOTES
    Author: GitHub Copilot
    Version: 1.0
    Created: November 2025
    
    This script is designed to work with the companion script Update-DevOpsUserLicenses.ps1
    for complete user and license reporting.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$OrganizationUrl,
    
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$PersonalAccessToken,
    
    [Parameter(Mandatory = $false)]
    [string]$OutputPath = "output",
    
    [Parameter(Mandatory = $false)]
    [switch]$ShowUsersWithoutProjects,
    
    [Parameter(Mandatory = $false)]
    [switch]$ExportUsersWithoutProjects
)

# Normalize organization URL
$OrganizationUrl = $OrganizationUrl.TrimEnd('/')
if ($OrganizationUrl -notmatch '^https://dev\.azure\.com/[^/]+$') {
    Write-Error "Organization URL must be in format: https://dev.azure.com/YourOrganization"
    exit 1
}

# Extract organization name
$OrgName = ($OrganizationUrl -split '/')[-1]

# Create output directory if it doesn't exist
if (-not (Test-Path $OutputPath)) {
    New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
}

# Create authorization header
$EncodedPAT = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(":$PersonalAccessToken"))
$Headers = @{
    'Authorization' = "Basic $EncodedPAT"
    'Content-Type' = 'application/json'
}

Write-Host "Starting Azure DevOps user and project collection..." -ForegroundColor Green
Write-Host "Organization: $OrgName" -ForegroundColor Cyan
Write-Host "Target: User and project data only (no license information)" -ForegroundColor Yellow

# Initialize collections
$AllUsers = @()
$ProjectUserMap = @{}

try {
    # Step 1: Get all projects
    Write-Host "`nStep 1: Retrieving projects..." -ForegroundColor Yellow
    $ProjectsUri = "$OrganizationUrl/_apis/projects?api-version=7.0"
    $ProjectsResponse = Invoke-RestMethod -Uri $ProjectsUri -Headers $Headers -Method Get
    $Projects = $ProjectsResponse.value
    Write-Host "Found $($Projects.Count) projects" -ForegroundColor Green

    # Step 2: Get users from each project
    Write-Host "`nStep 2: Collecting users from projects..." -ForegroundColor Yellow
    $ProjectCounter = 0
    
    foreach ($Project in $Projects) {
        $ProjectCounter++
        Write-Progress -Activity "Processing Projects" -Status "Project: $($Project.name)" -PercentComplete (($ProjectCounter / $Projects.Count) * 100)
        
        try {
            # Get default team for the project
            $TeamsUri = "$OrganizationUrl/_apis/projects/$($Project.id)/teams?api-version=7.0"
            $TeamsResponse = Invoke-RestMethod -Uri $TeamsUri -Headers $Headers -Method Get
            
            foreach ($Team in $TeamsResponse.value) {
                try {
                    # Get team members
                    $MembersUri = "$OrganizationUrl/_apis/projects/$($Project.id)/teams/$($Team.id)/members?api-version=7.0"
                    $MembersResponse = Invoke-RestMethod -Uri $MembersUri -Headers $Headers -Method Get
                    
                    foreach ($Member in $MembersResponse.value) {
                        $UserId = $Member.identity.id
                        $UserDisplayName = $Member.identity.displayName
                        $UserEmail = if ($Member.identity.uniqueName) { $Member.identity.uniqueName } else { "No email available" }
                        
                        # Add to project mapping
                        if (-not $ProjectUserMap.ContainsKey($UserId)) {
                            $ProjectUserMap[$UserId] = @{
                                DisplayName = $UserDisplayName
                                Email = $UserEmail
                                Projects = @()
                            }
                        }
                        
                        # Add project if not already present
                        if ($ProjectUserMap[$UserId].Projects -notcontains $Project.name) {
                            $ProjectUserMap[$UserId].Projects += $Project.name
                        }
                    }
                }
                catch {
                    Write-Warning "Failed to get members for team '$($Team.name)' in project '$($Project.name)': $($_.Exception.Message)"
                }
            }
        }
        catch {
            Write-Warning "Failed to process project '$($Project.name)': $($_.Exception.Message)"
        }
    }
    
    Write-Progress -Activity "Processing Projects" -Completed
    
    # Step 3: Convert to user objects
    Write-Host "`nStep 3: Converting to user objects..." -ForegroundColor Yellow
    
    foreach ($UserId in $ProjectUserMap.Keys) {
        $UserData = $ProjectUserMap[$UserId]
        $ProjectNames = $UserData.Projects -join "; "
        
        $UserObject = [PSCustomObject]@{
            'User ID' = $UserId
            'User Name' = $UserData.DisplayName
            'Email' = $UserData.Email
            'Project Names' = $ProjectNames
            'Project Count' = $UserData.Projects.Count
            'License Level' = 'Not Retrieved'  # Placeholder for license enhancement
        }
        
        $AllUsers += $UserObject
    }
    
    Write-Host "Collected $($AllUsers.Count) unique users" -ForegroundColor Green
    
    # Step 4: Handle users without projects
    $UsersWithProjects = $AllUsers | Where-Object { $_.'Project Count' -gt 0 }
    $UsersWithoutProjects = $AllUsers | Where-Object { $_.'Project Count' -eq 0 }
    
    Write-Host "`nUser Distribution:" -ForegroundColor Cyan
    Write-Host "  Users with projects: $($UsersWithProjects.Count)" -ForegroundColor White
    Write-Host "  Users without projects: $($UsersWithoutProjects.Count)" -ForegroundColor White
    
    # Step 5: Export main CSV
    $Timestamp = Get-Date -Format "yyyy-MM-dd-HHmm"
    $MainCsvPath = Join-Path $OutputPath "devops-users-projects-$Timestamp.csv"
    
    if ($ShowUsersWithoutProjects) {
        $ExportUsers = $AllUsers
        Write-Host "`nExporting all users (including those without projects)..." -ForegroundColor Yellow
    } else {
        $ExportUsers = $UsersWithProjects
        Write-Host "`nExporting users with projects only..." -ForegroundColor Yellow
    }
    
    $ExportUsers | Sort-Object 'User Name' | Export-Csv -Path $MainCsvPath -NoTypeInformation -Encoding UTF8
    Write-Host "Main CSV exported: $MainCsvPath" -ForegroundColor Green
    Write-Host "Records exported: $($ExportUsers.Count)" -ForegroundColor Cyan
    
    # Step 6: Export users without projects (if requested)
    if ($ExportUsersWithoutProjects -and $UsersWithoutProjects.Count -gt 0) {
        $NoProjectsCsvPath = Join-Path $OutputPath "devops-users-NO-PROJECTS-$Timestamp.csv"
        $UsersWithoutProjects | Sort-Object 'User Name' | Export-Csv -Path $NoProjectsCsvPath -NoTypeInformation -Encoding UTF8
        Write-Host "Users without projects CSV: $NoProjectsCsvPath" -ForegroundColor Green
        Write-Host "Records exported: $($UsersWithoutProjects.Count)" -ForegroundColor Cyan
    }
    
    # Summary
    Write-Host "`n" + "="*60 -ForegroundColor Green
    Write-Host "USER AND PROJECT COLLECTION COMPLETED SUCCESSFULLY" -ForegroundColor Green
    Write-Host "="*60 -ForegroundColor Green
    Write-Host "Organization: $OrgName" -ForegroundColor Cyan
    Write-Host "Total users found: $($AllUsers.Count)" -ForegroundColor Cyan
    Write-Host "Users with projects: $($UsersWithProjects.Count)" -ForegroundColor Cyan
    Write-Host "Users without projects: $($UsersWithoutProjects.Count)" -ForegroundColor Cyan
    Write-Host "Main export file: $MainCsvPath" -ForegroundColor Cyan
    if ($ExportUsersWithoutProjects -and $UsersWithoutProjects.Count -gt 0) {
        Write-Host "No-projects file: $NoProjectsCsvPath" -ForegroundColor Cyan
    }
    Write-Host "`nNext Step: Use Update-DevOpsUserLicenses.ps1 to add license information" -ForegroundColor Yellow
    Write-Host "="*60 -ForegroundColor Green

}
catch {
    Write-Error "Script execution failed: $($_.Exception.Message)"
    Write-Host "Stack Trace:" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}