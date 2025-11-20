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
    [int]$MaxRetries = 3,
    
    [Parameter(Mandatory = $false, HelpMessage = "Skip pagination and use only first batch of users (for large orgs with API issues)")]
    [switch]$SkipPagination,
    
    [Parameter(Mandatory = $false, HelpMessage = "Maximum number of users to retrieve (0 = no limit)")]
    [ValidateRange(0, 10000)]
    [int]$MaxUsers = 0,
    
    [Parameter(Mandatory = $false, HelpMessage = "Use alternative Graph API method to retrieve all users")]
    [switch]$UseGraphAPI,
    
    [Parameter(Mandatory = $false, HelpMessage = "Force retrieve all users using multiple API attempts")]
    [switch]$ForceAllUsers,
    
    [Parameter(Mandatory = $false, HelpMessage = "Use project-based approach to collect all users (bypasses entitlements API)")]
    [switch]$UseProjectBased,
    
    [Parameter(Mandatory = $false, HelpMessage = "Show users with no project assignments by comparing entitlements vs project-based data")]
    [switch]$ShowUsersWithoutProjects,
    
    [Parameter(Mandatory = $false, HelpMessage = "Export separate CSV file containing only users without project assignments")]
    [switch]$ExportUsersWithoutProjects
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

# Function to get users via Graph API method (alternative approach)
function Get-UsersViaGraph {
    param(
        [string]$OrgUrl,
        [hashtable]$Headers
    )
    
    try {
        Write-Log "Attempting to retrieve users via Graph API method..." "INFO"
        $graphUri = "$OrgUrl/_apis/graph/users?api-version=7.0"
        $response = Invoke-DevOpsRestMethod -Uri $graphUri -Headers $Headers
        
        if ($response.value) {
            Write-Log "Graph API retrieved $($response.value.Count) users" "SUCCESS"
            return $response.value
        }
        else {
            Write-Log "No users found via Graph API" "WARNING"
            return @()
        }
    }
    catch {
        Write-Log "Graph API method failed: $($_.Exception.Message)" "WARNING"
        return @()
    }
}

# Function to get comprehensive user data from projects (bypasses entitlements API)
function Get-AllUsersViaProjects {
    param(
        [string]$OrgUrl,
        [hashtable]$Headers,
        [array]$Projects
    )
    
    Write-Log "Using project-based approach to collect all users..." "INFO"
    $allUsers = @{}
    $totalProjects = $Projects.Count
    
    for ($i = 0; $i -lt $totalProjects; $i++) {
        $project = $Projects[$i]
        $percentComplete = [math]::Round(($i / $totalProjects) * 100, 1)
        
        Write-Progress -Activity "Scanning Projects for Users" -Status "Project: $($project.name) ($($i + 1)/$totalProjects)" -PercentComplete $percentComplete
        
        try {
            # Get all teams in the project
            $teamsUri = "$OrgUrl/_apis/projects/$($project.id)/teams?api-version=7.0"
            $teamsResponse = Invoke-DevOpsRestMethod -Uri $teamsUri -Headers $Headers
            
            if ($teamsResponse.value) {
                foreach ($team in $teamsResponse.value) {
                    try {
                        # Get team members
                        $membersUri = "$OrgUrl/_apis/projects/$($project.id)/teams/$($team.id)/members?api-version=7.0"
                        $membersResponse = Invoke-DevOpsRestMethod -Uri $membersUri -Headers $Headers
                        
                        if ($membersResponse.value) {
                            foreach ($member in $membersResponse.value) {
                                if ($member.identity.id -and -not $allUsers.ContainsKey($member.identity.id)) {
                                    $allUsers[$member.identity.id] = @{
                                        id = $member.identity.id
                                        user = @{
                                            displayName = $member.identity.displayName
                                            mailAddress = $member.identity.uniqueName
                                            principalName = $member.identity.uniqueName
                                        }
                                        accessLevel = @{
                                            licenseDisplayName = "Unknown License (Project-based collection)"
                                        }
                                        projects = @()
                                    }
                                }
                                
                                # Add project to user's project list
                                if ($allUsers.ContainsKey($member.identity.id)) {
                                    if ($allUsers[$member.identity.id].projects -notcontains $project.name) {
                                        $allUsers[$member.identity.id].projects += $project.name
                                    }
                                }
                            }
                        }
                    }
                    catch {
                        Write-Log "Warning: Could not get members for team '$($team.name)' in project '$($project.name)': $($_.Exception.Message)" "WARNING"
                    }
                }
            }
        }
        catch {
            Write-Log "Warning: Could not process project '$($project.name)': $($_.Exception.Message)" "WARNING"
        }
    }
    
    Write-Progress -Activity "Scanning Projects for Users" -Completed
    
    # Convert hashtable to array format expected by rest of script
    $userList = @()
    foreach ($userId in $allUsers.Keys) {
        $userList += $allUsers[$userId]
    }
    
    Write-Log "Project-based collection found $($userList.Count) unique users across $totalProjects projects" "SUCCESS"
    return $userList
}

# Function to get users via project memberships (alternative approach)
function Get-UsersViaProjects {
    param(
        [string]$OrgUrl,
        [hashtable]$Headers,
        [array]$Projects
    )
    
    Write-Log "Attempting to collect users via project memberships..." "INFO"
    $allUsers = @{}
    
    foreach ($project in $Projects) {
        try {
            $members = Get-ProjectMembers -OrgUrl $OrgUrl -ProjectId $project.id -Headers $Headers
            foreach ($member in $members) {
                if ($member.identity.id -and -not $allUsers.ContainsKey($member.identity.id)) {
                    $allUsers[$member.identity.id] = @{
                        id = $member.identity.id
                        displayName = $member.identity.displayName
                        uniqueName = $member.identity.uniqueName
                        mailAddress = $member.identity.uniqueName
                    }
                }
            }
        }
        catch {
            Write-Log "Failed to get members for project $($project.name): $($_.Exception.Message)" "WARNING"
        }
    }
    
    $userList = $allUsers.Values
    Write-Log "Collected $($userList.Count) unique users from project memberships" "SUCCESS"
    return $userList
}

# Function to get comprehensive user data from projects (bypasses entitlements API)
function Get-AllUsersViaProjects {
    param(
        [string]$OrgUrl,
        [hashtable]$Headers,
        [array]$Projects
    )
    
    Write-Log "Using comprehensive project-based approach to collect all users..." "INFO"
    $allUsers = @{}
    $totalProjects = $Projects.Count
    
    for ($i = 0; $i -lt $totalProjects; $i++) {
        $project = $Projects[$i]
        $percentComplete = [math]::Round(($i / $totalProjects) * 100, 1)
        
        Write-Progress -Activity "Scanning Projects for Users" -Status "Project: $($project.name) ($($i + 1)/$totalProjects)" -PercentComplete $percentComplete
        
        try {
            # Get all teams in the project
            $teamsUri = "$OrgUrl/_apis/projects/$($project.id)/teams?api-version=7.0"
            $teamsResponse = Invoke-DevOpsRestMethod -Uri $teamsUri -Headers $Headers
            
            if ($teamsResponse.value) {
                foreach ($team in $teamsResponse.value) {
                    try {
                        # Get team members
                        $membersUri = "$OrgUrl/_apis/projects/$($project.id)/teams/$($team.id)/members?api-version=7.0"
                        $membersResponse = Invoke-DevOpsRestMethod -Uri $membersUri -Headers $Headers
                        
                        if ($membersResponse.value) {
                            foreach ($member in $membersResponse.value) {
                                if ($member.identity.id -and -not $allUsers.ContainsKey($member.identity.id)) {
                                    $allUsers[$member.identity.id] = @{
                                        id = $member.identity.id
                                        user = @{
                                            displayName = $member.identity.displayName
                                            mailAddress = $member.identity.uniqueName
                                            principalName = $member.identity.uniqueName
                                        }
                                        accessLevel = @{
                                            licenseDisplayName = "Unknown License (Project-based collection)"
                                        }
                                        projects = @()
                                    }
                                }
                                
                                # Add project to user's project list
                                if ($allUsers.ContainsKey($member.identity.id)) {
                                    if ($allUsers[$member.identity.id].projects -notcontains $project.name) {
                                        $allUsers[$member.identity.id].projects += $project.name
                                    }
                                }
                            }
                        }
                    }
                    catch {
                        Write-Log "Warning: Could not get members for team '$($team.name)' in project '$($project.name)': $($_.Exception.Message)" "WARNING"
                    }
                }
            }
        }
        catch {
            Write-Log "Warning: Could not process project '$($project.name)': $($_.Exception.Message)" "WARNING"
        }
    }
    
    Write-Progress -Activity "Scanning Projects for Users" -Completed
    
    # Convert hashtable to array format expected by rest of script
    $userList = @()
    foreach ($userId in $allUsers.Keys) {
        $userList += $allUsers[$userId]
    }
    
    Write-Log "Comprehensive project-based collection found $($userList.Count) unique users across $totalProjects projects" "SUCCESS"
    return $userList
}

# Function to get all users with their entitlements
function Get-UserEntitlements {
    param(
        [string]$OrgUrl,
        [hashtable]$Headers,
        [bool]$SkipPagination = $false,
        [int]$MaxUsers = 0,
        [bool]$ForceAllUsers = $false
    )
    
    $users = @()
    $continuationToken = $null
    $totalRetrieved = 0
    $retryCount = 0
    $maxPaginationRetries = if ($ForceAllUsers) { 10 } else { 3 }
    
    do {
        # Check if we've hit the max users limit
        if ($MaxUsers -gt 0 -and $totalRetrieved -ge $MaxUsers) {
            Write-Log "Reached maximum user limit of $MaxUsers. Stopping retrieval." "INFO"
            break
        }
        
        $uri = if ($continuationToken) {
            "$OrgUrl/_apis/userentitlements?api-version=7.0&continuationToken=$continuationToken"
        } else {
            "$OrgUrl/_apis/userentitlements?api-version=7.0"
        }
        
        try {
            $response = Invoke-DevOpsRestMethod -Uri $uri -Headers $Headers
            
            if ($response.members) {
                $users += $response.members
                $totalRetrieved += $response.members.Count
                $continuationToken = $response.continuationToken
                
                Write-Log "Retrieved $($response.members.Count) users. Total so far: $($users.Count)" "INFO"
                
                # Reset retry count on successful call
                $retryCount = 0
                
                # If SkipPagination is enabled, only get the first batch
                if ($SkipPagination) {
                    Write-Log "SkipPagination enabled - stopping after first batch of users" "INFO"
                    break
                }
            }
            else {
                Write-Log "No users found in response" "WARNING"
                break
            }
        }
        catch {
            $retryCount++
            Write-Log "Pagination attempt $retryCount failed: $($_.Exception.Message)" "WARNING"
            
            if ($ForceAllUsers -and $retryCount -le $maxPaginationRetries -and $continuationToken) {
                Write-Log "ForceAllUsers enabled - retrying pagination with delay..." "INFO"
                Start-Sleep -Seconds (2 * $retryCount)
                continue
            }
            else {
                Write-Log "Pagination failed after $retryCount attempts. Continuing with $($users.Count) users retrieved so far" "WARNING"
                break
            }
        }
        
    } while ($continuationToken -and -not $SkipPagination -and $retryCount -le $maxPaginationRetries)
    
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
    
    # Get all users using the best available method
    Write-Log "Retrieving user entitlements..." "INFO"
    if ($SkipPagination) {
        Write-Log "SkipPagination mode enabled - will retrieve only first batch to avoid API issues" "INFO"
    }
    if ($MaxUsers -gt 0) {
        Write-Log "Maximum users limit set to: $MaxUsers" "INFO"
    }
    if ($ForceAllUsers) {
        Write-Log "ForceAllUsers mode enabled - will attempt multiple methods to retrieve all users" "INFO"
    }
    if ($UseGraphAPI) {
        Write-Log "UseGraphAPI mode enabled - will try Graph API method first" "INFO"
    }
    if ($UseProjectBased) {
        Write-Log "UseProjectBased mode enabled - will collect users via project memberships" "INFO"
    }
    if ($ShowUsersWithoutProjects) {
        Write-Log "ShowUsersWithoutProjects mode enabled - will identify users with no project assignments" "INFO"
    }
    
    $users = @()
    $allEntitlementUsers = @()
    
    # If ShowUsersWithoutProjects is enabled, we need both datasets
    if ($ShowUsersWithoutProjects) {
        Write-Log "Collecting users from both entitlements API and project memberships for comparison..." "INFO"
        
        # First get users from entitlements API (with SkipPagination to avoid 500 errors)
        $vsaexOrgUrl = $orgUrl -replace "https://dev\.azure\.com/", "https://vsaex.dev.azure.com/"
        Write-Log "Getting users from entitlements API (first batch only to avoid pagination errors)..." "INFO"
        $allEntitlementUsers = Get-UserEntitlements -OrgUrl $vsaexOrgUrl -Headers $headers -SkipPagination $true -MaxUsers 0 -ForceAllUsers $false
        Write-Log "Found $($allEntitlementUsers.Count) users in entitlements API" "SUCCESS"
        
        # Then get users from project memberships
        Write-Log "Retrieving projects for project-based user collection..." "INFO"
        $projects = Get-Projects -OrgUrl $orgUrl -Headers $headers
        Write-Log "Found $($projects.Count) projects" "SUCCESS"
        
        if ($projects.Count -gt 0) {
            $projectUsers = Get-AllUsersViaProjects -OrgUrl $orgUrl -Headers $headers -Projects $projects
            Write-Log "Found $($projectUsers.Count) users with project assignments" "SUCCESS"
            
            # Create a set of user IDs from project memberships for comparison
            $projectUserIds = @{}
            foreach ($projUser in $projectUsers) {
                if ($projUser.id) {
                    $projectUserIds[$projUser.id] = $true
                }
            }
            
            # Identify users without projects by comparing entitlements vs project users
            $usersWithoutProjects = @()
            foreach ($entitlementUser in $allEntitlementUsers) {
                if ($entitlementUser.id -and -not $projectUserIds.ContainsKey($entitlementUser.id)) {
                    $usersWithoutProjects += $entitlementUser
                }
            }
            
            Write-Log "Found $($usersWithoutProjects.Count) users with NO project assignments" "SUCCESS"
            Write-Log "Found $($projectUsers.Count) users WITH project assignments" "SUCCESS"
            
            # Create license lookup from entitlements data
            $licenseLookup = @{}
            foreach ($entUser in $allEntitlementUsers) {
                if ($entUser.id -and $entUser.accessLevel.licenseDisplayName) {
                    $licenseLookup[$entUser.id] = $entUser.accessLevel.licenseDisplayName
                }
            }
            
            # Enhance project users with license information from entitlements
            foreach ($projUser in $projectUsers) {
                if ($projUser.id -and $licenseLookup.ContainsKey($projUser.id)) {
                    $projUser.accessLevel.licenseDisplayName = $licenseLookup[$projUser.id]
                }
            }
            
            # Combine project users (with licenses) and users without projects
            $users = $projectUsers + $usersWithoutProjects
            Write-Log "Combined dataset: $($users.Count) total users with license information preserved" "SUCCESS"
        }
        else {
            Write-Log "No projects found - cannot compare project memberships" "ERROR"
            $users = $allEntitlementUsers
        }
    }
    # If UseProjectBased is enabled, skip entitlements API entirely
    elseif ($UseProjectBased) {
        # Get projects first
        Write-Log "Retrieving projects for project-based user collection..." "INFO"
        $projects = Get-Projects -OrgUrl $orgUrl -Headers $headers
        Write-Log "Found $($projects.Count) projects" "SUCCESS"
        
        if ($projects.Count -gt 0) {
            $users = Get-AllUsersViaProjects -OrgUrl $orgUrl -Headers $headers -Projects $projects
            
            # Try to enhance with license information from entitlements API (first batch only)
            Write-Log "Attempting to enhance project-based data with license information..." "INFO"
            try {
                $vsaexOrgUrl = $orgUrl -replace "https://dev\.azure\.com/", "https://vsaex.dev.azure.com/"
                
                # Try to get more users by attempting multiple smaller batches
                $allLicenseData = @{}
                $batchSize = 50
                $maxAttempts = 5
                $totalLicenseUsers = 0
                
                for ($attempt = 1; $attempt -le $maxAttempts; $attempt++) {
                    try {
                        Write-Log "Attempting to retrieve license batch $attempt of $maxAttempts..." "INFO"
                        
                        # Try with different approaches for each batch
                        if ($attempt -eq 1) {
                            # First attempt: Standard entitlements call
                            $batchUsers = Get-UserEntitlements -OrgUrl $vsaexOrgUrl -Headers $headers -SkipPagination $true -MaxUsers 0 -ForceAllUsers $false
                        } 
                        elseif ($attempt -eq 2) {
                            # Second attempt: Try with smaller batch size
                            $batchUsers = Get-UserEntitlements -OrgUrl $vsaexOrgUrl -Headers $headers -SkipPagination $false -MaxUsers $batchSize -ForceAllUsers $false
                        }
                        elseif ($attempt -eq 3) {
                            # Third attempt: Try with ForceAllUsers but limited
                            $batchUsers = Get-UserEntitlements -OrgUrl $vsaexOrgUrl -Headers $headers -SkipPagination $false -MaxUsers ($batchSize * 2) -ForceAllUsers $true
                        }
                        elseif ($attempt -eq 4) {
                            # Fourth attempt: Try Graph API approach
                            try {
                                $batchUsers = Get-UsersViaGraph -OrgUrl $orgUrl -Headers $headers
                            } catch {
                                Write-Log "Graph API attempt failed: $($_.Exception.Message)" "WARNING"
                                $batchUsers = @()
                            }
                        }
                        else {
                            # Final attempt: Try a different API endpoint approach
                            try {
                                # Try organization users endpoint
                                $orgUsersUri = "$vsaexOrgUrl/_apis/graph/users?api-version=7.0"
                                $orgUsersResponse = Invoke-DevOpsRestMethod -Uri $orgUsersUri -Headers $headers
                                $batchUsers = $orgUsersResponse.value
                            } catch {
                                Write-Log "Organization users API attempt failed: $($_.Exception.Message)" "WARNING"
                                $batchUsers = @()
                            }
                        }
                        
                        if ($batchUsers -and $batchUsers.Count -gt 0) {
                            $newLicenses = 0
                            foreach ($user in $batchUsers) {
                                if ($user.id -and $user.accessLevel.licenseDisplayName -and -not $allLicenseData.ContainsKey($user.id)) {
                                    $allLicenseData[$user.id] = $user.accessLevel.licenseDisplayName
                                    $newLicenses++
                                }
                            }
                            
                            $totalLicenseUsers += $newLicenses
                            Write-Log "Batch $attempt retrieved $newLicenses new license records. Total: $totalLicenseUsers" "SUCCESS"
                            
                            # If we got a good batch, continue
                            if ($newLicenses -gt 0) {
                                Start-Sleep -Seconds 1  # Brief pause between attempts
                            }
                        } else {
                            Write-Log "Batch $attempt returned no users" "WARNING"
                        }
                        
                    } catch {
                        Write-Log "Batch $attempt failed: $($_.Exception.Message)" "WARNING"
                    }
                }
                
                Write-Log "Total license records collected: $totalLicenseUsers from $maxAttempts attempts" "INFO"
                
                if ($allLicenseData.Count -gt 0) {
                    # Enhance project users with all collected license information
                    $licensesFound = 0
                    foreach ($projUser in $users) {
                        if ($projUser.id -and $allLicenseData.ContainsKey($projUser.id)) {
                            $projUser.accessLevel.licenseDisplayName = $allLicenseData[$projUser.id]
                            $licensesFound++
                        }
                    }
                    
                    Write-Log "Enhanced $licensesFound users with license information from multiple API attempts" "SUCCESS"
                } else {
                    Write-Log "No license information could be retrieved from any API method" "WARNING"
                }
            }
            catch {
                Write-Log "Could not retrieve license information: $($_.Exception.Message)" "WARNING"
                Write-Log "Continuing with project-based data only (licenses will show as 'Unknown')" "INFO"
            }
        }
        else {
            Write-Log "No projects found - cannot use project-based collection" "ERROR"
            throw "No projects available for user collection"
        }
    }
    else {
        $vsaexOrgUrl = $orgUrl -replace "https://dev\.azure\.com/", "https://vsaex.dev.azure.com/"
        
        # Try Graph API method first if requested
        if ($UseGraphAPI) {
            $users = Get-UsersViaGraph -OrgUrl $orgUrl -Headers $headers
            if ($users.Count -eq 0) {
                Write-Log "Graph API method failed, falling back to entitlements API" "WARNING"
            }
        }
        
        # Use standard entitlements API if Graph API wasn't used or failed
        if ($users.Count -eq 0) {
            $users = Get-UserEntitlements -OrgUrl $vsaexOrgUrl -Headers $headers -SkipPagination $SkipPagination -MaxUsers $MaxUsers -ForceAllUsers $ForceAllUsers
        }
        
        # If we still don't have many users and ForceAllUsers is enabled, try project-based approach
        if ($ForceAllUsers -and $users.Count -lt 100) {
            Write-Log "Primary method returned few users, attempting project-based user collection..." "INFO"
            
            # Get projects first
            $projects = Get-Projects -OrgUrl $orgUrl -Headers $headers
            if ($projects.Count -gt 0) {
                $projectUsers = Get-AllUsersViaProjects -OrgUrl $orgUrl -Headers $headers -Projects $projects
                
                if ($projectUsers.Count -gt $users.Count) {
                    Write-Log "Project-based method found more users ($($projectUsers.Count) vs $($users.Count)). Using project-based results." "SUCCESS"
                    $users = $projectUsers
                }
            }
        }
    }
    
    Write-Log "Final user count: $($users.Count)" "SUCCESS"
    
    if ($SkipPagination -and $users.Count -gt 0) {
        Write-Log "Note: SkipPagination was used - there may be more users in the organization" "WARNING"
    }
    
    if ($users.Count -lt 100 -and -not $SkipPagination -and -not $ForceAllUsers) {
        Write-Log "Retrieved fewer than 100 users. Consider using -ForceAllUsers for large organizations" "WARNING"
    }
    
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
        
        # Get projects for this user - handle both project mapping and direct project data
        $userProjects = ""
        
        # If user has projects array (from project-based collection)
        if ($user.projects -and $user.projects.Count -gt 0) {
            $userProjects = $user.projects -join "; "
        }
        # Otherwise use the project mapping approach
        elseif ($userProjectMapping.ContainsKey($userId) -and $userProjectMapping[$userId].Count -gt 0) {
            $userProjects = $userProjectMapping[$userId] -join "; "
        }
        else {
            if ($ShowUsersWithoutProjects) {
                $userProjects = "*** NO PROJECT ASSIGNMENTS ***"
            } else {
                $userProjects = "No project assignments"
            }
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

    # If ShowUsersWithoutProjects or ExportUsersWithoutProjects is enabled, create separate file for users without projects
    if ($ShowUsersWithoutProjects -or $ExportUsersWithoutProjects) {
        $usersWithoutProjectsCsv = $csvData | Where-Object { $_."Project Names" -eq "*** NO PROJECT ASSIGNMENTS ***" }
        
        if ($usersWithoutProjectsCsv.Count -gt 0) {
            $noProjectsFileName = "devops-users-NO-PROJECTS-$timestamp.csv"
            $noProjectsPath = Join-Path $OutputPath $noProjectsFileName
            
            Write-Log "Exporting users without projects to: $noProjectsPath" "INFO"
            $usersWithoutProjectsCsv | Export-Csv -Path $noProjectsPath -NoTypeInformation -Encoding UTF8
            Write-Log "Users without projects exported: $($usersWithoutProjectsCsv.Count)" "SUCCESS"
            Write-Log "No-projects file: $noProjectsPath" "SUCCESS"
        } else {
            Write-Log "No users without project assignments found" "INFO"
        }
    }

    Write-Log "Export completed successfully!" "SUCCESS"
    Write-Log "Total users exported: $($csvData.Count)" "SUCCESS"
    Write-Log "Output file: $csvPath" "SUCCESS"}
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