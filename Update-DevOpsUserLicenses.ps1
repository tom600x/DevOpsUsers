#Requires -Version 5.1

<#
.SYNOPSIS
    Updates Azure DevOps user CSV files with license information from the Azure DevOps API.

.DESCRIPTION
    This script reads a CSV file created by Get-DevOpsUsersAndProjects.ps1 and enhances it
    with license information from the Azure DevOps user entitlements API. The script handles
    API pagination limitations and provides detailed progress reporting.
    
    The script will attempt multiple strategies to retrieve license information and updates
    the CSV with actual license levels where possible.

.PARAMETER CsvFilePath
    Path to the CSV file created by Get-DevOpsUsersAndProjects.ps1.

.PARAMETER OrganizationUrl
    The URL of the Azure DevOps organization (e.g., "https://dev.azure.com/YourOrg").

.PARAMETER PersonalAccessToken
    Personal Access Token with permissions to read user entitlements.
    Required permissions: User Entitlements (Read).

.PARAMETER OutputPath
    Optional. Directory where the updated CSV file will be saved. Defaults to same directory as input.

.PARAMETER BatchSize
    Optional. Number of users to process in each API batch. Default is 100.

.PARAMETER MaxRetries
    Optional. Maximum number of retry attempts for failed API calls. Default is 3.

.EXAMPLE
    .\Update-DevOpsUserLicenses.ps1 -CsvFilePath ".\output\devops-users-projects-2025-11-13-1410.csv" -OrganizationUrl "https://dev.azure.com/YourOrg" -PersonalAccessToken "your-pat-here"

.EXAMPLE
    .\Update-DevOpsUserLicenses.ps1 -CsvFilePath ".\output\devops-users-projects-2025-11-13-1410.csv" -OrganizationUrl "https://dev.azure.com/YourOrg" -PersonalAccessToken "your-pat-here" -BatchSize 50

.NOTES
    Author: GitHub Copilot
    Version: 1.0
    Created: November 2025
    
    This script is designed to work with CSV files created by Get-DevOpsUsersAndProjects.ps1.
    Due to Azure DevOps API limitations, not all users may have license information retrieved,
    especially in large organizations.
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [ValidateScript({
        if (-not (Test-Path $_)) { throw "CSV file not found: $_" }
        $true
    })]
    [string]$CsvFilePath,
    
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$OrganizationUrl,
    
    [Parameter(Mandatory = $true)]
    [ValidateNotNullOrEmpty()]
    [string]$PersonalAccessToken,
    
    [Parameter(Mandatory = $false)]
    [string]$OutputPath,
    
    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 1000)]
    [int]$BatchSize = 100,
    
    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 10)]
    [int]$MaxRetries = 3
)

# Normalize organization URL
$OrganizationUrl = $OrganizationUrl.TrimEnd('/')
if ($OrganizationUrl -notmatch '^https://dev\.azure\.com/[^/]+$') {
    Write-Error "Organization URL must be in format: https://dev.azure.com/YourOrganization"
    exit 1
}

# Extract organization name
$OrgName = ($OrganizationUrl -split '/')[-1]

# Set output path if not provided
if (-not $OutputPath) {
    $OutputPath = Split-Path $CsvFilePath -Parent
}

# Load required assemblies for URL encoding
Add-Type -AssemblyName System.Web

# Create authorization header
$EncodedPAT = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(":$PersonalAccessToken"))
$Headers = @{
    'Authorization' = "Basic $EncodedPAT"
    'Content-Type' = 'application/json'
}

# Function to make API calls with retry logic
function Invoke-ApiWithRetry {
    param(
        [string]$Uri,
        [hashtable]$Headers,
        [int]$MaxRetries = 3,
        [string]$Description = "API call"
    )
    
    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        try {
            Write-Verbose "$Description - Attempt $attempt of $MaxRetries"
            $response = Invoke-RestMethod -Uri $Uri -Headers $Headers -Method Get
            return $response
        }
        catch {
            $statusCode = $_.Exception.Response.StatusCode.value__
            $errorMessage = $_.Exception.Message
            
            Write-Warning "$Description failed (Attempt $attempt/$MaxRetries): $errorMessage"
            
            if ($attempt -eq $MaxRetries) {
                Write-Error "$Description failed after $MaxRetries attempts: $errorMessage"
                throw
            }
            
            # Wait before retry (exponential backoff)
            $waitTime = [Math]::Pow(2, $attempt - 1)
            Write-Verbose "Waiting $waitTime seconds before retry..."
            Start-Sleep -Seconds $waitTime
        }
    }
}

Write-Host "Starting license information enhancement..." -ForegroundColor Green
Write-Host "Organization: $OrgName" -ForegroundColor Cyan
Write-Host "Input CSV: $CsvFilePath" -ForegroundColor Cyan

try {
    # Step 1: Load the CSV file
    Write-Host "`nStep 1: Loading CSV file..." -ForegroundColor Yellow
    $Users = Import-Csv -Path $CsvFilePath
    Write-Host "Loaded $($Users.Count) users from CSV" -ForegroundColor Green
    
    # Validate CSV structure
    $requiredColumns = @('User ID', 'User Name', 'Email', 'License Level')
    $csvColumns = $Users[0].PSObject.Properties.Name
    $missingColumns = $requiredColumns | Where-Object { $_ -notin $csvColumns }
    
    if ($missingColumns.Count -gt 0) {
        Write-Error "CSV file missing required columns: $($missingColumns -join ', ')"
        exit 1
    }
    
    # Step 2: Get license information from API
    Write-Host "`nStep 2: Retrieving license information..." -ForegroundColor Yellow
    $LicenseMap = @{}
    $ProcessedUsers = 0
    $EnhancedUsers = 0
    $ContinuationToken = $null
    $BatchNumber = 1
    $CurrentBatchSize = $BatchSize
    $ConsecutiveFailures = 0
    
    do {
        Write-Host "Processing batch $BatchNumber..." -ForegroundColor Cyan
        
        try {
            # Build API URI with proper encoding
            $BaseUri = "https://vsaex.dev.azure.com/$OrgName/_apis/userentitlements"
            $ApiUri = "$BaseUri" + "?api-version=7.0&" + "`$top=$CurrentBatchSize"
            
            if ($ContinuationToken) {
                # Properly encode the continuation token
                $EncodedToken = [System.Web.HttpUtility]::UrlEncode($ContinuationToken)
                $ApiUri += "&continuationToken=$EncodedToken"
            }
            
            Write-Verbose "API URI: $ApiUri"
            
            # Make API call with retry logic
            $Response = Invoke-ApiWithRetry -Uri $ApiUri -Headers $Headers -MaxRetries $MaxRetries -Description "License batch $BatchNumber"
            
            if ($Response.members) {
                foreach ($Member in $Response.members) {
                    $UserId = $Member.id
                    # Try multiple fields to get license information
                    $LicenseDisplayName = if ($Member.accessLevel -and $Member.accessLevel.licenseDisplayName) {
                        $Member.accessLevel.licenseDisplayName
                    } elseif ($Member.accessLevel -and $Member.accessLevel.displayName) {
                        $Member.accessLevel.displayName
                    } elseif ($Member.accessLevel -and $Member.accessLevel.msdnLicenseType) {
                        # Fallback to MSDN license type if display name not available
                        switch ($Member.accessLevel.msdnLicenseType) {
                            "enterprise" { "Visual Studio Enterprise subscription" }
                            "professional" { "Visual Studio Professional subscription" }
                            "testProfessional" { "Visual Studio Test Professional subscription" }
                            "basic" { "Basic" }
                            default { "MSDN: $($Member.accessLevel.msdnLicenseType)" }
                        }
                    } else {
                        "Unknown License"
                    }
                    
                    $LicenseMap[$UserId] = $LicenseDisplayName
                    $ProcessedUsers++
                    
                    # Debug: Show first few licenses in first batch with full member structure
                    if ($BatchNumber -eq 1 -and $ProcessedUsers -le 3) {
                        Write-Verbose "Debug: User $($UserId) -> $($LicenseDisplayName)"
                        Write-Verbose "  Access Level: $($Member.accessLevel | ConvertTo-Json -Compress)"
                        Write-Verbose "  User: $($Member.user.displayName)"
                    }
                }
                
                Write-Host "  Retrieved $($Response.members.Count) license records (batch size: $CurrentBatchSize)" -ForegroundColor White
                Write-Host "  Total processed: $ProcessedUsers" -ForegroundColor White
                $ConsecutiveFailures = 0  # Reset failure counter on success
                
                # Check for continuation token - handle both string and object formats
                if ($Response.PSObject.Properties['continuationToken']) {
                    $NewToken = $Response.continuationToken
                    if ($NewToken -ne $ContinuationToken -and -not [string]::IsNullOrWhiteSpace($NewToken)) {
                        $ContinuationToken = $NewToken
                        Write-Verbose "Continuation token updated: $($ContinuationToken.Substring(0, [Math]::Min(50, $ContinuationToken.Length)))..."
                    } else {
                        Write-Host "  No new continuation token - ending pagination" -ForegroundColor Yellow
                        $ContinuationToken = $null
                    }
                } else {
                    Write-Host "  No continuation token in response - ending pagination" -ForegroundColor Yellow
                    $ContinuationToken = $null
                }
                $BatchNumber++
            }
            else {
                Write-Warning "No members found in API response for batch $BatchNumber"
                break
            }
        }
        catch {
            $errorMessage = $_.Exception.Message
            $statusCode = if ($_.Exception.Response) { $_.Exception.Response.StatusCode.value__ } else { "Unknown" }
            
            Write-Warning "Failed to retrieve batch $BatchNumber after all retries: $errorMessage (Status: $statusCode)"
            
            # For first batch failure, this is critical
            if ($BatchNumber -eq 1) {
                Write-Error "Failed to retrieve any license information. Cannot proceed."
                exit 1
            }
            
            # For subsequent batches, check if it's a continuation token issue
            if ($statusCode -eq 500 -or $errorMessage -like "*continuation*") {
                Write-Host "This appears to be a continuation token/pagination issue - Azure DevOps API limitation for large organizations" -ForegroundColor Yellow
                $ConsecutiveFailures++
                
                # Try reducing batch size if we haven't already tried
                if ($CurrentBatchSize -gt 10 -and $ConsecutiveFailures -eq 1) {
                    $CurrentBatchSize = [Math]::Max(10, $CurrentBatchSize / 2)
                    Write-Host "Trying smaller batch size: $CurrentBatchSize" -ForegroundColor Yellow
                    $ContinuationToken = $null  # Reset and start over with smaller batches
                    $BatchNumber = 1
                    continue
                }
            }
            
            # Continue with partial data
            Write-Host "Continuing with partial license data from successful batches..." -ForegroundColor Yellow
            break
        }
        
    } while ($ContinuationToken)
    
    Write-Host "License retrieval completed. Retrieved $ProcessedUsers license records." -ForegroundColor Green
    
    # Step 3: Update users with license information
    Write-Host "`nStep 3: Updating user records with license information..." -ForegroundColor Yellow
    
    foreach ($User in $Users) {
        $UserId = $User.'User ID'
        
        if ($LicenseMap.ContainsKey($UserId)) {
            $User.'License Level' = $LicenseMap[$UserId]
            $EnhancedUsers++
        } else {
            # Keep existing value or set to indicate not found
            if ($User.'License Level' -eq 'Not Retrieved' -or [string]::IsNullOrWhiteSpace($User.'License Level')) {
                $User.'License Level' = 'License Not Found'
            }
        }
    }
    
    Write-Host "Enhanced $EnhancedUsers out of $($Users.Count) users with license information" -ForegroundColor Green
    
    # Step 4: Export updated CSV
    Write-Host "`nStep 4: Exporting updated CSV..." -ForegroundColor Yellow
    
    $Timestamp = Get-Date -Format "yyyy-MM-dd-HHmm"
    $InputFileName = [System.IO.Path]::GetFileNameWithoutExtension($CsvFilePath)
    $UpdatedCsvPath = Join-Path $OutputPath "$InputFileName-LICENSED-$Timestamp.csv"
    
    $Users | Sort-Object 'User Name' | Export-Csv -Path $UpdatedCsvPath -NoTypeInformation -Encoding UTF8
    Write-Host "Updated CSV exported: $UpdatedCsvPath" -ForegroundColor Green
    
    # Step 5: Generate summary report
    Write-Host "`nStep 5: License distribution summary..." -ForegroundColor Yellow
    
    $LicenseGroups = $Users | Group-Object 'License Level'
    $LicenseGroups | Sort-Object Count -Descending | ForEach-Object {
        Write-Host "  $($_.Name): $($_.Count) users" -ForegroundColor White
    }
    
    # Calculate enhancement percentage
    $EnhancementPercentage = if ($Users.Count -gt 0) { 
        [Math]::Round(($EnhancedUsers / $Users.Count) * 100, 1) 
    } else { 0 }
    
    # Final summary
    Write-Host "`n" + "="*60 -ForegroundColor Green
    Write-Host "LICENSE ENHANCEMENT COMPLETED" -ForegroundColor Green
    Write-Host "="*60 -ForegroundColor Green
    Write-Host "Organization: $OrgName" -ForegroundColor Cyan
    Write-Host "Input file: $CsvFilePath" -ForegroundColor Cyan
    Write-Host "Output file: $UpdatedCsvPath" -ForegroundColor Cyan
    Write-Host "Total users: $($Users.Count)" -ForegroundColor Cyan
    Write-Host "Users enhanced with license data: $EnhancedUsers ($EnhancementPercentage%)" -ForegroundColor Cyan
    Write-Host "API records processed: $ProcessedUsers" -ForegroundColor Cyan
    
    if ($EnhancedUsers -lt $Users.Count) {
        Write-Host "`nNote: Some users may not have license information due to API limitations" -ForegroundColor Yellow
        Write-Host "or insufficient permissions. This is common with large organizations." -ForegroundColor Yellow
    }
    
    Write-Host "="*60 -ForegroundColor Green

}
catch {
    Write-Error "Script execution failed: $($_.Exception.Message)"
    Write-Host "Stack Trace:" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}