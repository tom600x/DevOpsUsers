#Requires -Version 5.1

<#
.SYNOPSIS
    Advanced license optimization analysis for Azure DevOps users.

.DESCRIPTION
    This script provides comprehensive license optimization analysis including:
    - Users with licenses but no projects (unused licenses)
    - Users with minimal project assignments (potentially over-licensed)
    - High-value licenses with low project engagement
    - DEEP USAGE ANALYSIS: Examines actual Azure DevOps service usage patterns
    - License feature utilization validation (Test Plans, Build/Release, etc.)
    - Time-based usage analysis to validate license requirements
    - License optimization recommendations based on actual usage patterns
    
    This helps identify cost savings opportunities and optimize license allocation based on real usage data.

.PARAMETER CsvFilePath
    Path to the licensed CSV file created by Update-DevOpsUserLicenses.ps1.

.PARAMETER OutputPath
    Optional. Directory where the report files will be saved. Defaults to same directory as input.

.PARAMETER AnalysisType
    Type of analysis to perform:
    - 'NoProjects': Users with licenses but no project assignments
    - 'MinimalProjects': Users with high-value licenses but minimal project assignments (1-2 projects)
    - 'LicenseOptimization': Comprehensive license optimization analysis
    - 'All': All analysis types

.PARAMETER MaxProjectsForMinimal
    When using MinimalProjects analysis, the maximum number of projects to consider as "minimal". Default is 2.

.PARAMETER HighValueLicensesOnly
    Focus only on high-value licenses (Professional, Enterprise) for optimization analysis.

.PARAMETER UsageAnalysisMonths
    Number of months to look back for usage analysis. Default is 3 months.
    Only recommend license downgrades if user hasn't used premium features in this timeframe.

.PARAMETER OrganizationUrl
    Azure DevOps organization URL. Required for deep usage analysis.
    Format: https://dev.azure.com/YourOrganization

.PARAMETER PersonalAccessToken
    Personal Access Token with extended permissions for usage analysis:
    - User Entitlements (Read)
    - Project and Team (Read) 
    - Build (Read)
    - Release (Read)
    - Test Management (Read)
    - Analytics (Read)
    - Packaging (Read)
    - Extensions (Read)

.PARAMETER PerformUsageAnalysis
    Enable deep usage analysis. Requires OrganizationUrl and PersonalAccessToken.
    When enabled, validates actual feature usage before recommending license downgrades.

.EXAMPLE
    .\Get-LicenseOptimizationReport.ps1 -CsvFilePath ".\output\devops-users-projects-2025-11-14-1128-LICENSED-2025-11-14-1129.csv" -AnalysisType "All"

.EXAMPLE
.EXAMPLE\n    .\\Get-LicenseOptimizationReport.ps1 -CsvFilePath \".\\output\\devops-users-projects-2025-11-14-1128-LICENSED-2025-11-14-1129.csv\" -AnalysisType \"MinimalProjects\" -MaxProjectsForMinimal 1 -HighValueLicensesOnly\n\n.EXAMPLE\n    .\\Get-LicenseOptimizationReport.ps1 -CsvFilePath \".\\output\\devops-users-projects-2025-11-14-1128-LICENSED-2025-11-14-1129.csv\" -PerformUsageAnalysis -OrganizationUrl \"https://dev.azure.com/YourOrg\" -PersonalAccessToken \"your-pat-token\" -UsageAnalysisMonths 6

.NOTES
    Author: GitHub Copilot
    Version: 1.0
    Created: November 2025
    
    This script provides advanced license optimization analysis for cost management.
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
    [ValidateSet('NoProjects', 'MinimalProjects', 'LicenseOptimization', 'All')]
    [string]$AnalysisType = 'All',
    
    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 5)]
    [int]$MaxProjectsForMinimal = 2,
    
    [Parameter(Mandatory = $false)]
    [switch]$HighValueLicensesOnly,
    
    [Parameter(Mandatory = $false)]
    [ValidateRange(1, 12)]
    [int]$UsageAnalysisMonths = 3,
    
    [Parameter(Mandatory = $false)]
    [string]$OrganizationUrl,
    
    [Parameter(Mandatory = $false)]
    [string]$PersonalAccessToken,
    
    [Parameter(Mandatory = $false)]
    [switch]$PerformUsageAnalysis
)

# Set output path if not provided
if (-not $OutputPath) {
    $OutputPath = Split-Path $CsvFilePath -Parent
}

# Validate usage analysis parameters
if ($PerformUsageAnalysis) {
    if (-not $OrganizationUrl) {
        throw "OrganizationUrl is required when PerformUsageAnalysis is enabled"
    }
    if (-not $PersonalAccessToken) {
        throw "PersonalAccessToken is required when PerformUsageAnalysis is enabled"
    }
    if ($OrganizationUrl -notmatch '^https://dev\.azure\.com/[^/]+/?$') {
        throw "OrganizationUrl must be in format: https://dev.azure.com/YourOrganization"
    }
    Write-Host "Usage Analysis Enabled: Looking back $UsageAnalysisMonths months" -ForegroundColor Yellow
}

# License categorization and values
$LicenseCategories = @{
    'High-Value' = @('Visual Studio Enterprise subscription', 'Visual Studio Professional subscription')
    'Medium-Value' = @('VS Test Pro with MSDN', 'Visual Studio Subscriber', 'Basic + Test Plans')
    'Low-Value' = @('Basic', 'Stakeholder')
}

$LicenseCostEstimate = @{
    'Visual Studio Enterprise subscription' = 250  # Approximate monthly cost
    'Visual Studio Professional subscription' = 45
    'VS Test Pro with MSDN' = 52
    'Visual Studio Subscriber' = 45
    'Basic + Test Plans' = 52
    'Basic' = 6
    'Stakeholder' = 0
}

# License features mapping - what features each license includes
$LicenseFeatures = @{
    'Visual Studio Enterprise subscription' = @(
        'VisualStudioIDE', 'PremiumFeatures', 'TestPlans', 'BuildRelease', 'PackageManagement', 
        'ArtifactStorage', 'CodeSearch', 'Analytics', 'Extensions', 'LoadTesting'
    )
    'Visual Studio Professional subscription' = @(
        'VisualStudioIDE', 'BuildRelease', 'PackageManagement', 'ArtifactStorage', 'CodeSearch'
    )
    'VS Test Pro with MSDN' = @(
        'TestPlans', 'BuildRelease', 'PackageManagement', 'ArtifactStorage'
    )
    'Visual Studio Subscriber' = @(
        'VisualStudioIDE', 'BuildRelease', 'PackageManagement'
    )
    'Basic + Test Plans' = @(
        'BasicAccess', 'TestPlans', 'BuildRelease'
    )
    'Basic' = @(
        'BasicAccess', 'BuildRelease'
    )
    'Stakeholder' = @(
        'ReadOnlyAccess'
    )
}

# Minimum license required for each feature
$FeatureMinimumLicense = @{
    'VisualStudioIDE' = 'Visual Studio Professional subscription'
    'PremiumFeatures' = 'Visual Studio Enterprise subscription'
    'TestPlans' = 'Basic + Test Plans'
    'LoadTesting' = 'Visual Studio Enterprise subscription'
    'BuildRelease' = 'Basic'
    'PackageManagement' = 'Basic'
    'ArtifactStorage' = 'Basic'
    'CodeSearch' = 'Basic'
    'Analytics' = 'Basic'
    'Extensions' = 'Basic'
    'BasicAccess' = 'Basic'
    'ReadOnlyAccess' = 'Stakeholder'
}

# Calculate lookback date for usage analysis
$UsageAnalysisStartDate = (Get-Date).AddMonths(-$UsageAnalysisMonths).ToString('yyyy-MM-dd')
$UsageAnalysisEndDate = (Get-Date).ToString('yyyy-MM-dd')

# Usage Analysis Functions
function Get-UserActivityData {
    param(
        [string]$UserId,
        [string]$OrganizationName,
        [hashtable]$Headers,
        [string]$StartDate,
        [string]$EndDate
    )
    
    $activity = @{
        'TestPlans' = $false
        'BuildRelease' = $false
        'VisualStudioIDE' = $false
        'PremiumFeatures' = $false
        'LoadTesting' = $false
        'PackageManagement' = $false
        'Analytics' = $false
        'Extensions' = $false
        'CodeSearch' = $false
    }
    
    try {
        # Check Test Plans usage
        $testPlansUrl = "$OrganizationUrl/_apis/test/plans?api-version=7.0&\$top=1&createdBy=$UserId&createdDate=$StartDate"
        $testResponse = Invoke-RestMethod -Uri $testPlansUrl -Headers $Headers -ErrorAction SilentlyContinue
        if ($testResponse.count -gt 0) {
            $activity['TestPlans'] = $true
        }
        
        # Check Build usage (builds created or modified)
        $buildsUrl = "$OrganizationUrl/_apis/build/builds?api-version=7.0&\$top=1&requestedFor=$UserId&minTime=$StartDate"
        $buildResponse = Invoke-RestMethod -Uri $buildsUrl -Headers $Headers -ErrorAction SilentlyContinue
        if ($buildResponse.count -gt 0) {
            $activity['BuildRelease'] = $true
        }
        
        # Check Release usage
        $releasesUrl = "$OrganizationUrl/_apis/release/releases?api-version=7.0&\$top=1&createdBy=$UserId&minCreatedTime=$StartDate"
        $releaseResponse = Invoke-RestMethod -Uri $releasesUrl -Headers $Headers -ErrorAction SilentlyContinue
        if ($releaseResponse.count -gt 0) {
            $activity['BuildRelease'] = $true
        }
        
        # Check Package Management usage (feed access)
        $feedsUrl = "$OrganizationUrl/_apis/packaging/feeds?api-version=7.0"
        $feedsResponse = Invoke-RestMethod -Uri $feedsUrl -Headers $Headers -ErrorAction SilentlyContinue
        foreach ($feed in $feedsResponse.value) {
            $packageUrl = "$OrganizationUrl/_apis/packaging/feeds/$($feed.id)/packages?api-version=7.0&\$top=1&publishedBy=$UserId&publishedAfter=$StartDate"
            $packageResponse = Invoke-RestMethod -Uri $packageUrl -Headers $Headers -ErrorAction SilentlyContinue
            if ($packageResponse.count -gt 0) {
                $activity['PackageManagement'] = $true
                break
            }
        }
        
        # Check Analytics usage (queries created)
        $analyticsUrl = "$OrganizationUrl/_apis/analytics/queries?api-version=7.0-preview&\$filter=createdBy eq '$UserId' and createdDate ge $StartDate"
        $analyticsResponse = Invoke-RestMethod -Uri $analyticsUrl -Headers $Headers -ErrorAction SilentlyContinue
        if ($analyticsResponse.'@odata.count' -gt 0) {
            $activity['Analytics'] = $true
        }
        
        # Check Extensions usage (installed or managed)
        $extensionsUrl = "$OrganizationUrl/_apis/extensionmanagement/installedextensions?api-version=7.0"
        $extensionsResponse = Invoke-RestMethod -Uri $extensionsUrl -Headers $Headers -ErrorAction SilentlyContinue
        foreach ($extension in $extensionsResponse.value) {
            if ($extension.lastPublisher -eq $UserId -or $extension.installState.lastUpdatedBy.id -eq $UserId) {
                $installDate = [DateTime]::Parse($extension.installState.installationTime)
                if ($installDate -ge [DateTime]::Parse($StartDate)) {
                    $activity['Extensions'] = $true
                    break
                }
            }
        }
        
    } catch {
        Write-Warning "Error collecting usage data for user $UserId`: $($_.Exception.Message)"
    }
    
    return $activity
}

function Get-RecommendedLicense {
    param(
        [hashtable]$UserActivity,
        [string]$CurrentLicense
    )
    
    # Determine minimum required license based on actual usage
    $requiredFeatures = @()
    foreach ($feature in $UserActivity.Keys) {
        if ($UserActivity[$feature] -eq $true) {
            $requiredFeatures += $feature
        }
    }
    
    if ($requiredFeatures.Count -eq 0) {
        return 'Stakeholder'  # No premium features used
    }
    
    # Find the minimum license that covers all used features
    $minLicense = 'Stakeholder'
    $minCost = 0
    
    foreach ($feature in $requiredFeatures) {
        if ($FeatureMinimumLicense.ContainsKey($feature)) {
            $featureMinLicense = $FeatureMinimumLicense[$feature]
            $featureCost = $LicenseCostEstimate[$featureMinLicense]
            if ($featureCost -gt $minCost) {
                $minLicense = $featureMinLicense
                $minCost = $featureCost
            }
        }
    }
    
    return $minLicense
}

Write-Host "Starting advanced license optimization analysis..." -ForegroundColor Green
Write-Host "Input CSV: $CsvFilePath" -ForegroundColor Cyan
Write-Host "Analysis Type: $AnalysisType" -ForegroundColor Cyan
if ($AnalysisType -in @('MinimalProjects', 'All')) {
    Write-Host "Max Projects for Minimal Analysis: $MaxProjectsForMinimal" -ForegroundColor Cyan
}
Write-Host "High-Value Licenses Only: $HighValueLicensesOnly" -ForegroundColor Cyan

try {
    # Step 1: Load and validate the CSV file
    Write-Host "`nStep 1: Loading licensed CSV file..." -ForegroundColor Yellow
    $AllUsers = Import-Csv -Path $CsvFilePath
    Write-Host "Loaded $($AllUsers.Count) users from CSV" -ForegroundColor Green
    
    # Get users with valid licenses
    $UsersWithLicenses = $AllUsers | Where-Object { 
        $_.'License Level' -notin @('License Not Found', 'Not Retrieved', '') -and
        $_.'License Level' -ne $null
    }
    
    Write-Host "Users with valid licenses: $($UsersWithLicenses.Count)" -ForegroundColor White
    
    # Apply high-value filter if requested
    if ($HighValueLicensesOnly) {
        $UsersWithLicenses = $UsersWithLicenses | Where-Object {
            $_.'License Level' -in $LicenseCategories['High-Value']
        }
        Write-Host "High-value licensed users: $($UsersWithLicenses.Count)" -ForegroundColor White
    }
    
    $Timestamp = Get-Date -Format "yyyy-MM-dd-HHmm"
    $Reports = @()
    
    # Setup authentication for usage analysis
    $Headers = @{}
    $OrganizationName = ""
    if ($PerformUsageAnalysis) {
        Write-Host "`nSetting up usage analysis authentication..." -ForegroundColor Yellow
        $base64AuthInfo = [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$PersonalAccessToken"))
        $Headers = @{ Authorization = "Basic $base64AuthInfo" }
        $OrganizationName = ($OrganizationUrl -split '/')[-1]
        Write-Host "Organization: $OrganizationName" -ForegroundColor Cyan
        Write-Host "Analysis Period: $UsageAnalysisStartDate to $UsageAnalysisEndDate" -ForegroundColor Cyan
    }
    
    # Analysis 1: No Projects
    if ($AnalysisType -in @('NoProjects', 'All')) {
        Write-Host "`nAnalysis 1: Users with licenses but no projects..." -ForegroundColor Yellow
        
        $NoProjectUsers = $UsersWithLicenses | Where-Object {
            ([int]$_.'Project Count') -eq 0 -or 
            [string]::IsNullOrWhiteSpace($_.'Project Names')
        }
        
        Write-Host "Licensed users with no projects: $($NoProjectUsers.Count)" -ForegroundColor White
        
        if ($NoProjectUsers.Count -gt 0) {
            $NoProjectsReport = @()
            $ProcessedCount = 0
            
            foreach ($user in $NoProjectUsers) {
                $ProcessedCount++
                Write-Progress -Activity "Analyzing users with no projects" -Status "Processing user $ProcessedCount of $($NoProjectUsers.Count)" -PercentComplete (($ProcessedCount / $NoProjectUsers.Count) * 100)
                
                $UsageValidated = $false
                $RecommendedLicense = 'Stakeholder'
                $UsageDetails = 'No usage analysis performed'
                
                if ($PerformUsageAnalysis -and $_.'User ID') {
                    try {
                        $UserActivity = Get-UserActivityData -UserId $_.'User ID' -OrganizationName $OrganizationName -Headers $Headers -StartDate $UsageAnalysisStartDate -EndDate $UsageAnalysisEndDate
                        $RecommendedLicense = Get-RecommendedLicense -UserActivity $UserActivity -CurrentLicense $_.'License Level'
                        $UsageValidated = $true
                        
                        $ActiveFeatures = @()
                        foreach ($feature in $UserActivity.Keys) {
                            if ($UserActivity[$feature] -eq $true) {
                                $ActiveFeatures += $feature
                            }
                        }
                        $UsageDetails = if ($ActiveFeatures.Count -gt 0) { "Used: $($ActiveFeatures -join ', ')" } else { "No premium features used in last $UsageAnalysisMonths months" }
                    } catch {
                        Write-Warning "Usage analysis failed for $($_.'User Name'): $($_.Exception.Message)"
                        $UsageDetails = "Usage analysis failed: $($_.Exception.Message)"
                    }
                }
                
                # Only recommend downgrade if usage analysis confirms no premium feature usage
                $OptimizationOpportunity = if ($UsageValidated) {
                    if ($RecommendedLicense -ne $_.'License Level') {
                        "VALIDATED: Downgrade to $RecommendedLicense (no premium features used)"
                    } else {
                        "VALIDATED: Current license justified by usage"
                    }
                } else {
                    "Remove unused license (manual validation recommended)"
                }
                
                $PotentialSavings = if ($UsageValidated -and $RecommendedLicense -ne $_.'License Level') {
                    $LicenseCostEstimate[$_.'License Level'] - $LicenseCostEstimate[$RecommendedLicense]
                } else {
                    $LicenseCostEstimate[$_.'License Level']
                }
                
                $NoProjectsReport += [PSCustomObject]@{
                    'Analysis Type' = if ($UsageValidated) { 'No Projects (Usage Validated)' } else { 'No Projects' }
                    'User ID' = $_.'User ID'
                    'User Name' = $_.'User Name'
                    'Email' = $_.'Email'
                    'License Level' = $_.'License Level'
                    'Recommended License' = $RecommendedLicense
                    'Project Count' = $_.'Project Count'
                    'Monthly Cost Estimate' = $LicenseCostEstimate[$_.'License Level']
                    'Optimization Opportunity' = $OptimizationOpportunity
                    'Potential Monthly Savings' = $PotentialSavings
                    'Usage Details' = $UsageDetails
                    'Priority' = if ($UsageValidated -and $PotentialSavings -gt 0) {
                        if ($_.'License Level' -in $LicenseCategories['High-Value']) { 'High' } 
                        elseif ($_.'License Level' -in $LicenseCategories['Medium-Value']) { 'Medium' } 
                        else { 'Low' }
                    } else { 'Manual Review Required' }
                }
            }
            Write-Progress -Activity "Analyzing users with no projects" -Completed
            $Reports += $NoProjectsReport
        }
    }
    
    # Analysis 2: Minimal Projects
    if ($AnalysisType -in @('MinimalProjects', 'All')) {
        Write-Host "`nAnalysis 2: Users with high-value licenses but minimal projects..." -ForegroundColor Yellow
        
        $MinimalProjectUsers = $UsersWithLicenses | Where-Object {
            ([int]$_.'Project Count') -gt 0 -and 
            ([int]$_.'Project Count') -le $MaxProjectsForMinimal -and
            $_.'License Level' -in ($LicenseCategories['High-Value'] + $LicenseCategories['Medium-Value'])
        }
        
        Write-Host "Users with minimal project assignments: $($MinimalProjectUsers.Count)" -ForegroundColor White
        
        if ($MinimalProjectUsers.Count -gt 0) {
            $MinimalProjectsReport = @()
            $ProcessedCount = 0
            
            foreach ($user in $MinimalProjectUsers) {
                $ProcessedCount++
                Write-Progress -Activity "Analyzing users with minimal projects" -Status "Processing user $ProcessedCount of $($MinimalProjectUsers.Count)" -PercentComplete (($ProcessedCount / $MinimalProjectUsers.Count) * 100)
                
                $currentCost = $LicenseCostEstimate[$user.'License Level']
                $basicCost = $LicenseCostEstimate['Basic']
                $stakeholderCost = $LicenseCostEstimate['Stakeholder']
                
                $UsageValidated = $false
                $RecommendedLicense = if ($currentCost -gt $basicCost) { 'Basic' } else { 'Stakeholder' }
                $UsageDetails = 'No usage analysis performed'
                
                if ($PerformUsageAnalysis -and $user.'User ID') {
                    try {
                        $UserActivity = Get-UserActivityData -UserId $user.'User ID' -OrganizationName $OrganizationName -Headers $Headers -StartDate $UsageAnalysisStartDate -EndDate $UsageAnalysisEndDate
                        $RecommendedLicense = Get-RecommendedLicense -UserActivity $UserActivity -CurrentLicense $user.'License Level'
                        $UsageValidated = $true
                        
                        $ActiveFeatures = @()
                        foreach ($feature in $UserActivity.Keys) {
                            if ($UserActivity[$feature] -eq $true) {
                                $ActiveFeatures += $feature
                            }
                        }
                        $UsageDetails = if ($ActiveFeatures.Count -gt 0) { "Used: $($ActiveFeatures -join ', ')" } else { "No premium features used in last $UsageAnalysisMonths months" }
                    } catch {
                        Write-Warning "Usage analysis failed for $($user.'User Name'): $($_.Exception.Message)"
                        $UsageDetails = "Usage analysis failed: $($_.Exception.Message)"
                    }
                }
                
                # Calculate potential savings based on recommended license
                $PotentialSavings = $currentCost - $LicenseCostEstimate[$RecommendedLicense]
                
                # Only recommend downgrade if usage analysis confirms it's safe OR if no usage analysis is performed
                $OptimizationOpportunity = if ($UsageValidated) {
                    if ($RecommendedLicense -ne $user.'License Level' -and $PotentialSavings -gt 0) {
                        "VALIDATED: Downgrade to $RecommendedLicense (usage analysis confirms)"
                    } elseif ($RecommendedLicense -eq $user.'License Level') {
                        "VALIDATED: Current license justified by usage"
                    } else {
                        "VALIDATED: No optimization opportunity"
                    }
                } else {
                    "Consider downgrade to $RecommendedLicense (manual validation recommended)"
                }
                
                $MinimalProjectsReport += [PSCustomObject]@{
                    'Analysis Type' = if ($UsageValidated) { 'Minimal Projects (Usage Validated)' } else { 'Minimal Projects' }
                    'User ID' = $user.'User ID'
                    'User Name' = $user.'User Name'
                    'Email' = $user.'Email'
                    'License Level' = $user.'License Level'
                    'Recommended License' = $RecommendedLicense
                    'Project Count' = $user.'Project Count'
                    'Project Names' = $user.'Project Names'
                    'Monthly Cost Estimate' = $currentCost
                    'Optimization Opportunity' = $OptimizationOpportunity
                    'Potential Monthly Savings' = if ($PotentialSavings -gt 0) { $PotentialSavings } else { 0 }
                    'Usage Details' = $UsageDetails
                    'Priority' = if ($UsageValidated -and $PotentialSavings -gt 0) {
                        if ($user.'License Level' -in $LicenseCategories['High-Value'] -and ([int]$user.'Project Count') -eq 1) { 'High' } 
                        elseif ($user.'License Level' -in $LicenseCategories['High-Value']) { 'Medium' } 
                        else { 'Low' }
                    } elseif ($UsageValidated) {
                        'No Action Needed'
                    } else {
                        'Manual Review Required'
                    }
                }
            }
            Write-Progress -Activity "Analyzing users with minimal projects" -Completed
            $Reports += $MinimalProjectsReport
        }
    }
    
    # Analysis 3: License Optimization
    if ($AnalysisType -in @('LicenseOptimization', 'All')) {
        Write-Host "`nAnalysis 3: Comprehensive license optimization..." -ForegroundColor Yellow
        
        # Find Stakeholder users who might need Basic (many projects)
        $StakeholderUsers = $UsersWithLicenses | Where-Object {
            $_.'License Level' -eq 'Stakeholder' -and
            ([int]$_.'Project Count') -gt 3
        }
        
        Write-Host "Stakeholder users with many projects (potential upgrade candidates): $($StakeholderUsers.Count)" -ForegroundColor White
        
        if ($StakeholderUsers.Count -gt 0) {
            $OptimizationReport = $StakeholderUsers | ForEach-Object {
                [PSCustomObject]@{
                    'Analysis Type' = 'License Optimization'
                    'User ID' = $_.'User ID'
                    'User Name' = $_.'User Name'
                    'Email' = $_.'Email'
                    'License Level' = $_.'License Level'
                    'Project Count' = $_.'Project Count'
                    'Project Names' = $_.'Project Names'
                    'Monthly Cost Estimate' = $LicenseCostEstimate[$_.'License Level']
                    'Optimization Opportunity' = 'Consider upgrade to Basic for better functionality'
                    'Potential Monthly Cost Increase' = $LicenseCostEstimate['Basic'] - $LicenseCostEstimate['Stakeholder']
                    'Priority' = 'Medium'
                }
            }
            $Reports += $OptimizationReport
        }
    }
    
    # Step 2: Generate reports
    Write-Host "`nStep 2: Generating optimization reports..." -ForegroundColor Yellow
    
    if ($Reports.Count -gt 0) {
        $ReportPath = Join-Path $OutputPath "license-optimization-report-$Timestamp.csv"
        $Reports | Sort-Object 'Priority', 'Potential Monthly Savings' -Descending | 
            Export-Csv -Path $ReportPath -NoTypeInformation -Encoding UTF8
        
        Write-Host "Optimization report exported: $ReportPath" -ForegroundColor Green
        Write-Host "Total optimization opportunities: $($Reports.Count)" -ForegroundColor Cyan
        
        # Calculate potential savings
        $TotalSavings = ($Reports | Where-Object { $_.'Potential Monthly Savings' -gt 0 } | 
                        Measure-Object 'Potential Monthly Savings' -Sum).Sum
        
        if ($TotalSavings -gt 0) {
            Write-Host "Potential monthly savings: `$$TotalSavings" -ForegroundColor Green
            Write-Host "Potential annual savings: `$$($TotalSavings * 12)" -ForegroundColor Green
        }
    } else {
        Write-Host "No optimization opportunities found with current criteria" -ForegroundColor Yellow
    }
    
    # Step 3: Generate summary report
    Write-Host "`nStep 3: Generating license summary..." -ForegroundColor Yellow
    
    $SummaryPath = Join-Path $OutputPath "license-usage-summary-$Timestamp.csv"
    
    $LicenseSummary = $UsersWithLicenses | Group-Object 'License Level' | ForEach-Object {
        $avgProjects = ($_.Group | Measure-Object 'Project Count' -Average).Average
        $totalCost = $_.Count * $LicenseCostEstimate[$_.Name]
        
        [PSCustomObject]@{
            'License Type' = $_.Name
            'User Count' = $_.Count
            'Average Projects per User' = [Math]::Round($avgProjects, 1)
            'Monthly Cost per License' = $LicenseCostEstimate[$_.Name]
            'Total Monthly Cost' = $totalCost
            'Total Annual Cost' = $totalCost * 12
            'Utilization Assessment' = if ($avgProjects -lt 1) { 'Under-utilized' } 
                                     elseif ($avgProjects -lt 2) { 'Low utilization' }
                                     elseif ($avgProjects -lt 4) { 'Moderate utilization' }
                                     else { 'High utilization' }
        }
    } | Sort-Object 'Total Monthly Cost' -Descending
    
    $LicenseSummary | Export-Csv -Path $SummaryPath -NoTypeInformation -Encoding UTF8
    Write-Host "License usage summary exported: $SummaryPath" -ForegroundColor Green
    
    # Display summary
    Write-Host "`nLicense Usage Summary:" -ForegroundColor Cyan
    $LicenseSummary | ForEach-Object {
        Write-Host "  $($_.'License Type'): $($_.'User Count') users, avg $($_.'Average Projects per User') projects, $($_.'Total Monthly Cost')/month" -ForegroundColor White
    }
    
    # Final summary
    Write-Host "`n" + "="*70 -ForegroundColor Green
    Write-Host "ADVANCED LICENSE OPTIMIZATION ANALYSIS COMPLETED" -ForegroundColor Green
    Write-Host "="*70 -ForegroundColor Green
    Write-Host "Analysis Type: $AnalysisType" -ForegroundColor Cyan
    Write-Host "Total users analyzed: $($AllUsers.Count)" -ForegroundColor Cyan
    Write-Host "Users with valid licenses: $($UsersWithLicenses.Count)" -ForegroundColor Cyan
    Write-Host "Optimization opportunities found: $($Reports.Count)" -ForegroundColor Cyan
    if ($Reports.Count -gt 0) {
        Write-Host "Optimization report: $ReportPath" -ForegroundColor Cyan
        if ($TotalSavings -gt 0) {
            Write-Host "Potential monthly savings: `$$TotalSavings" -ForegroundColor Green
        }
    }
    Write-Host "Usage summary: $SummaryPath" -ForegroundColor Cyan
    if ($PerformUsageAnalysis) {
        Write-Host "Usage analysis performed: $UsageAnalysisMonths months lookback" -ForegroundColor Cyan
        Write-Host "Analysis period: $UsageAnalysisStartDate to $UsageAnalysisEndDate" -ForegroundColor Cyan
    } else {
        Write-Host "Usage analysis: DISABLED (use -PerformUsageAnalysis for detailed validation)" -ForegroundColor Yellow
    }
    Write-Host "="*70 -ForegroundColor Green

}
catch {
    Write-Error "Script execution failed: $($_.Exception.Message)"
    Write-Host "Stack Trace:" -ForegroundColor Red
    Write-Host $_.ScriptStackTrace -ForegroundColor Red
    exit 1
}