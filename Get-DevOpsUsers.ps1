[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)]
    [string]$OrganizationUrl,
    
    [Parameter(Mandatory = $true)]
    [string]$PersonalAccessToken,
    
    [Parameter(Mandatory = $false)]
    [string]$OutputPath = ".\output"
)

# Function to create authentication header
function Get-AuthHeader {
    param([string]$Pat)
    
    $encodedPat = [System.Convert]::ToBase64String([System.Text.Encoding]::ASCII.GetBytes(":$Pat"))
    return @{
        'Authorization' = "Basic $encodedPat"
        'Content-Type' = 'application/json'
    }
}

# Function to make REST API calls with error handling
function Invoke-DevOpsRestMethod {
    param(
        [string]$Uri,
        [hashtable]$Headers,
        [string]$Method = "GET"
    )
    
    try {
        Write-Verbose "Making API call to: $Uri"
        $response = Invoke-RestMethod -Uri $Uri -Headers $Headers -Method $Method
        return $response
    }
    catch {
        Write-Error "Failed to call API: $Uri. Error: $($_.Exception.Message)"
        throw
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
        $users += $response.members
        $continuationToken = $response.continuationToken
        
        Write-Verbose "Retrieved $($response.members.Count) users. Total so far: $($users.Count)"
        
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
    
    Write-Verbose "Retrieved $($response.value.Count) projects"
    return $response.value
}

# Function to get project team members
function Get-ProjectMembers {
    param(
        [string]$OrgUrl,
        [string]$ProjectId,
        [hashtable]$Headers
    )
    
    try {
        # Get default team for the project
        $teamsUri = "$OrgUrl/_apis/projects/$ProjectId/teams?api-version=7.0"
        $teamsResponse = Invoke-DevOpsRestMethod -Uri $teamsUri -Headers $Headers
        
        $allMembers = @()
        
        foreach ($team in $teamsResponse.value) {
            $membersUri = "$OrgUrl/_apis/projects/$ProjectId/teams/$($team.id)/members?api-version=7.0"
            $membersResponse = Invoke-DevOpsRestMethod -Uri $membersUri -Headers $Headers
            $allMembers += $membersResponse.value
        }
        
        # Remove duplicates based on user ID
        $uniqueMembers = $allMembers | Sort-Object -Property id -Unique
        
        Write-Verbose "Retrieved $($uniqueMembers.Count) unique members for project $ProjectId"
        return $uniqueMembers
    }
    catch {
        Write-Warning "Could not retrieve members for project $ProjectId`: $($_.Exception.Message)"
        return @()
    }
}

# Main execution
try {
    Write-Host "Starting Azure DevOps Users Export..." -ForegroundColor Green
    
    # Validate and clean organization URL
    $orgUrl = $OrganizationUrl.TrimEnd('/')
    if ($orgUrl -notmatch "^https://dev\.azure\.com/[^/]+$") {
        throw "Organization URL must be in format: https://dev.azure.com/YourOrganization"
    }
    
    # Create output directory if it doesn't exist
    if (-not (Test-Path $OutputPath)) {
        New-Item -ItemType Directory -Path $OutputPath -Force | Out-Null
        Write-Verbose "Created output directory: $OutputPath"
    }
    
    # Setup authentication
    $headers = Get-AuthHeader -Pat $PersonalAccessToken
    Write-Verbose "Authentication header created"
    
    # Get all users
    Write-Host "Retrieving user entitlements..." -ForegroundColor Yellow
    $vsaexOrgUrl = $orgUrl -replace "https://dev\.azure\.com/", "https://vsaex.dev.azure.com/"
    $users = Get-UserEntitlements -OrgUrl $vsaexOrgUrl -Headers $headers
    Write-Host "Found $($users.Count) users" -ForegroundColor Green
    
    # Get all projects
    Write-Host "Retrieving projects..." -ForegroundColor Yellow
    $projects = Get-Projects -OrgUrl $orgUrl -Headers $headers
    Write-Host "Found $($projects.Count) projects" -ForegroundColor Green
    
    # Create user-project mapping
    Write-Host "Mapping users to projects..." -ForegroundColor Yellow
    $userProjectMapping = @{}
    
    foreach ($project in $projects) {
        Write-Verbose "Processing project: $($project.name)"
        $members = Get-ProjectMembers -OrgUrl $orgUrl -ProjectId $project.id -Headers $headers
        
        foreach ($member in $members) {
            $userId = $member.identity.id
            if (-not $userProjectMapping.ContainsKey($userId)) {
                $userProjectMapping[$userId] = @()
            }
            $userProjectMapping[$userId] += $project.name
        }
    }
    
    # Prepare CSV data
    Write-Host "Preparing CSV data..." -ForegroundColor Yellow
    $csvData = @()
    
    foreach ($user in $users) {
        $userId = $user.id
        $userName = if ($user.user.displayName) { $user.user.displayName } else { $user.user.principalName }
        $userEmail = $user.user.mailAddress
        $licenseLevel = $user.accessLevel.licenseDisplayName
        
        # Get projects for this user
        $userProjects = if ($userProjectMapping.ContainsKey($userId)) {
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
    $timestamp = Get-Date -Format "yyyy-MM-dd"
    $csvFileName = "devops-users-$timestamp.csv"
    $csvPath = Join-Path $OutputPath $csvFileName
    
    # Export to CSV
    Write-Host "Exporting to CSV: $csvPath" -ForegroundColor Yellow
    $csvData | Export-Csv -Path $csvPath -NoTypeInformation -Encoding UTF8
    
    Write-Host "Export completed successfully!" -ForegroundColor Green
    Write-Host "Total users exported: $($csvData.Count)" -ForegroundColor Green
    Write-Host "Output file: $csvPath" -ForegroundColor Green
    
}
catch {
    Write-Error "Script execution failed: $($_.Exception.Message)"
    Write-Error "Stack trace: $($_.ScriptStackTrace)"
    exit 1
}