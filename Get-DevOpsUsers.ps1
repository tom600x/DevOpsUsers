[CmdletBinding()]
param(
    [Parameter(Mandatory = $true, HelpMessage = "Azure DevOps organization URL (e.g., https://dev.azure.com/YourOrg)")]
    [ValidatePattern('^https://dev\.azure\.com/[^/]+$')]
    [string]$OrganizationUrl,
    
    [Parameter(Mandatory = $true, HelpMessage = "Personal Access Token with required permissions")]
    [ValidateNotNullOrEmpty()]
    [string]$PersonalAccessToken,
    
    [Parameter(Mandatory = $false, HelpMessage = "Output directory for CSV files")]
    [ValidateNotNullOrEmpty()]
    [string]$OutputPath = ".\output",
    
    [Parameter(Mandatory = $false, HelpMessage = "Optional log file path for detailed logging")]
    [string]$LogPath = $null,
    
    [Parameter(Mandatory = $false, HelpMessage = "Maximum number of retry attempts for API calls")]
    [ValidateRange(1, 10)]
    [int]$MaxRetries = 3
)

# Function to write log messages with timestamps
function Write-Log {
    param(
        [string]$Message,
        [ValidateSet("INFO", "WARNING", "ERROR", "SUCCESS")]
        [string]$Level = "INFO",
        [string]$LogPath = $script:LogPath
    )
    
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    
    # Write to console with appropriate color
    switch ($Level) {
        "INFO"    { Write-Host $logEntry -ForegroundColor White }
        "SUCCESS" { Write-Host $logEntry -ForegroundColor Green }
        "WARNING" { Write-Host $logEntry -ForegroundColor Yellow }
        "ERROR"   { Write-Host $logEntry -ForegroundColor Red }
    }
    
    # Write to log file if specified
    if ($LogPath) {
        try {
            Add-Content -Path $LogPath -Value $logEntry -ErrorAction Stop
        }
        catch {
            Write-Warning "Failed to write to log file: $($_.Exception.Message)"
        }
    }
}

# Function to create authentication header
function Get-AuthHeader {
    param([string]$Pat)
    
    $encodedPat = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(":$Pat"))
    return @{
        'Authorization' = "Basic $encodedPat"
        'Content-Type' = 'application/json'
    }
}

# Function to make REST API calls with retry logic and error handling
function Invoke-DevOpsRestMethod {
    param(
        [string]$Uri,
        [hashtable]$Headers,
        [string]$Method = "GET",
        [int]$MaxRetries = $script:MaxRetries,
        [int]$BaseDelaySeconds = 1
    )
    
    for ($attempt = 1; $attempt -le $MaxRetries; $attempt++) {
        try {
            Write-Verbose "Making API call to: $Uri (Attempt $attempt/$MaxRetries)"
            $response = Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method -TimeoutSec 30
            
            if ($attempt -gt 1) {
                Write-Log "API call succeeded on attempt $attempt" "SUCCESS"
            }
            
            return $response
        }
        catch {
            $errorMessage = $_.Exception.Message
            $statusCode = $null
            
            if ($_.Exception.Response) {
                $statusCode = $_.Exception.Response.StatusCode.value__
            }
            
            if ($attempt -eq $MaxRetries) {
                Write-Log "API call failed after $MaxRetries attempts. URI: $Uri. Error: $errorMessage" "ERROR"
                throw
            }
            
            # Calculate delay with exponential backoff
            $delay = $BaseDelaySeconds * [Math]::Pow(2, $attempt - 1)
            
            # Check if it's a rate limiting error (429) or server error (5xx)
            $shouldRetry = $statusCode -eq 429 -or ($statusCode -ge 500 -and $statusCode -le 599) -or $null -eq $statusCode
            
            if ($shouldRetry) {
                Write-Log "API call failed (attempt $attempt/$MaxRetries). Status: $statusCode. Retrying in $delay seconds..." "WARNING"
                Start-Sleep -Seconds $delay
            }
            else {
                Write-Log "API call failed with non-retryable error. Status: $statusCode. Error: $errorMessage" "ERROR"
                throw
            }
        }
    }
}

# Function to get all users with their entitlements
function Get-UserEntitlements {
    param(
        [string]$OrgUrl,
        [hashtable]$Headers
    )
    
    $users = @()
    $continuationToken = $null
    
    do {
        $uri = if ($continuationToken) {
            "$OrgUrl/_apis/userentitlements?api-version=7.0&continuationToken=$continuationToken"
        } else {
            "$OrgUrl/_apis/userentitlements?api-version=7.0"
        }
        
        $response = Invoke-DevOpsRestMethod -Uri $uri -Headers $Headers
        
        if ($response.members) {
            $users += $response.members
            $continuationToken = $response.continuationToken
            
            Write-Log "Retrieved $($response.members.Count) users. Total so far: $($users.Count)" "INFO"
        }
        else {
            Write-Log "No users found in response" "WARNING"
            break
        }
        
    } while ($continuationToken)
    
    return $users
}

# Function to get all projects
function Get-Projects {
    param(
        [string]$OrgUrl,
        [hashtable]$Headers
    )
    
    $uri = "$OrgUrl/_apis/projects?api-version=7.0"
    $response = Invoke-DevOpsRestMethod -Uri $uri -Headers $Headers
    
    if ($response.value) {
        Write-Log "Retrieved $($response.value.Count) projects" "INFO"
        return $response.value
    }
    else {
        Write-Log "No projects found" "WARNING"
        return @()
    }
}

# Function to get project team members
function Get-ProjectMembers {
    param(
        [string]$OrgUrl,
        [string]$ProjectId,
        [hashtable]$Headers
    )
    
    try {
        # Get all teams for the project
        $teamsUri = "$OrgUrl/_apis/projects/$ProjectId/teams?api-version=7.0"
        $teamsResponse = Invoke-DevOpsRestMethod -Uri $teamsUri -Headers $Headers
        
        $allMembers = @()
        
        if ($teamsResponse.value) {
            foreach ($team in $teamsResponse.value) {
                try {
                    $membersUri = "$OrgUrl/_apis/projects/$ProjectId/teams/$($team.id)/members?api-version=7.0"
                    $membersResponse = Invoke-DevOpsRestMethod -Uri $membersUri -Headers $Headers
                    
                    if ($membersResponse.value) {
                        $allMembers += $membersResponse.value
                    }
                }
                catch {
                    Write-Log "Could not retrieve members for team '$($team.name)' in project $ProjectId`: $($_.Exception.Message)" "WARNING"
                }
            }
        }
        
        # Remove duplicates based on user ID
        $uniqueMembers = $allMembers | Where-Object { $_.identity.id } | Sort-Object -Property { $_.identity.id } -Unique
        
        Write-Verbose "Retrieved $($uniqueMembers.Count) unique members for project $ProjectId"
        return $uniqueMembers
    }
    catch {
        Write-Log "Could not retrieve members for project $ProjectId`: $($_.Exception.Message)" "WARNING"
        return @()
    }
}

# Main execution
try {
    Write-Log "Starting Azure DevOps Users Export..." "SUCCESS"
    
    # Validate and clean organization URL
    $orgUrl = $OrganizationUrl.TrimEnd('/')
    Write-Log "Organization URL: $orgUrl" "INFO"
    
    # Create output directory if it doesn't exist
    if (-not (Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
        Write-Log "Created output directory: $OutputPath" "INFO"
    }
    
    # Setup authentication
    $headers = Get-AuthHeader -Pat $PersonalAccessToken
    Write-Log "Authentication header created successfully" "INFO"
    
    # Get all users
    Write-Log "Retrieving user entitlements..." "INFO"
    $vsaexOrgUrl = $orgUrl -replace "https://dev\.azure\.com/", "https://vsaex.dev.azure.com/"
    $users = Get-UserEntitlements -OrgUrl $vsaexOrgUrl -Headers $headers
    Write-Log "Found $($users.Count) users" "SUCCESS"
    
    # Get all projects
    Write-Log "Retrieving projects..." "INFO"
    $projects = Get-Projects -OrgUrl $orgUrl -Headers $headers
    Write-Log "Found $($projects.Count) projects" "SUCCESS"
    
    # Create user-project mapping with progress reporting
    Write-Log "Mapping users to projects..." "INFO"
    $userProjectMapping = @{}
    $totalProjects = $projects.Count
    
    for ($i = 0; $i -lt $totalProjects; $i++) {
        $project = $projects[$i]
        $percentComplete = [math]::Round(($i / $totalProjects) * 100, 1)
        
        Write-Progress -Activity "Processing Projects" -Status "Project: $($project.name) ($($i + 1)/$totalProjects)" -PercentComplete $percentComplete
        Write-Verbose "Processing project: $($project.name) ($($i + 1)/$totalProjects)"
        
        $members = Get-ProjectMembers -OrgUrl $orgUrl -ProjectId $project.id -Headers $headers
        
        foreach ($member in $members) {
            $userId = $member.identity.id
            if ($userId) {  # Null safety check
                if (-not $userProjectMapping.ContainsKey($userId)) {
                    $userProjectMapping[$userId] = @()
                }
                $userProjectMapping[$userId] += $project.name
            }
        }
    }
    
    # Clear progress bar
    Write-Progress -Activity "Processing Projects" -Completed
    Write-Log "Project mapping completed" "SUCCESS"
    
    # Prepare CSV data with improved null safety
    Write-Log "Preparing CSV data..." "INFO"
    $csvData = @()
    
    foreach ($user in $users) {
        # Improved null safety for user data
        $userId = $user.id
        if (-not $userId) {
            Write-Log "Skipping user with missing ID" "WARNING"
            continue
        }
        
        # Safe extraction of user properties with fallbacks
        $userName = if ($user.user.displayName) { 
            $user.user.displayName 
        } elseif ($user.user.principalName) { 
            $user.user.principalName 
        } else { 
            "Unknown User ($userId)" 
        }
        
        $userEmail = if ($user.user.mailAddress) { 
            $user.user.mailAddress 
        } else { 
            "No email available" 
        }
        
        $licenseLevel = if ($user.accessLevel.licenseDisplayName) { 
            $user.accessLevel.licenseDisplayName 
        } else { 
            "Unknown License" 
        }
        
        # Get projects for this user with null safety
        $userProjects = if ($userProjectMapping.ContainsKey($userId) -and $userProjectMapping[$userId].Count -gt 0) {
            $userProjectMapping[$userId] -join "; "
        } else {
            "No project assignments"
        }
        
        $csvData += [PSCustomObject]@{
            'User Name' = $userName
            'Email' = $userEmail
            'Project Names' = $userProjects
            'License Level' = $licenseLevel
        }
    }
    
    # Generate timestamped filename
    $timestamp = Get-Date -Format "yyyy-MM-dd-HHmm"
    $csvFileName = "devops-users-$timestamp.csv"
    $csvPath = Join-Path $OutputPath $csvFileName
    
    # Export to CSV
    Write-Log "Exporting to CSV: $csvPath" "INFO"
    $csvData | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
    
    Write-Log "Export completed successfully!" "SUCCESS"
    Write-Log "Total users exported: $($csvData.Count)" "SUCCESS"
    Write-Log "Output file: $csvPath" "SUCCESS"
    
}
catch {
    Write-Log "Script execution failed: $($_.Exception.Message)" "ERROR"
    Write-Log "Stack trace: $($_.ScriptStackTrace)" "ERROR"
    exit 1
}
finally {
    # Cleanup sensitive data from memory
    Write-Log "Clearing sensitive data from memory..." "INFO"
    
    # Clear variables (avoid validation errors by using Remove-Variable)
    try {
        Remove-Variable -Name "PersonalAccessToken" -Scope Script -ErrorAction SilentlyContinue
        Remove-Variable -Name "headers" -Scope Script -ErrorAction SilentlyContinue
    }
    catch {
        # Ignore cleanup errors
    }
    
    # Force garbage collection
    [System.GC]::Collect()
    Write-Log "Cleanup completed" "INFO"
}