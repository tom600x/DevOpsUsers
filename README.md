# Azure DevOps User Reporting Scripts

This project provides PowerShell scripts to extract and report on Azure DevOps Services users, their project assignments, and license levels. The solution uses a two-script approach to handle large organizations and API limitations effectively.

## Quick Start

### Two-Script Approach

This solution uses two separate scripts for optimal reliability:

1. **`Get-DevOpsUsersAndProjects.ps1`** - Collects all users and project assignments
2. **`Update-DevOpsUserLicenses.ps1`** - Enhances the CSV with license information

### Basic Usage

```powershell
# Step 1: Collect users and projects
.\Get-DevOpsUsersAndProjects.ps1 -OrganizationUrl "https://dev.azure.com/YourOrg" -PersonalAccessToken "your-pat-here"

# Step 2: Add license information
.\Update-DevOpsUserLicenses.ps1 -CsvFilePath ".\output\devops-users-projects-2025-11-13-1410.csv" -OrganizationUrl "https://dev.azure.com/YourOrg" -PersonalAccessToken "your-pat-here"
```

## Scripts Overview

### Get-DevOpsUsersAndProjects.ps1

**Purpose**: Reliably collects all users and their project assignments without license information.

**Key Features**:
- Project-based user enumeration (works with large organizations)
- Handles users with and without project assignments
- No license API dependencies (more reliable)
- Comprehensive error handling

**Parameters**:
- `OrganizationUrl` (Required): Azure DevOps organization URL
- `PersonalAccessToken` (Required): PAT with User Entitlements and Project permissions
- `OutputPath` (Optional): Output directory (default: "output")
- `ShowUsersWithoutProjects` (Optional): Include users without projects in main CSV
- `ExportUsersWithoutProjects` (Optional): Create separate CSV for users without projects

**Output**: 
- `devops-users-projects-YYYY-MM-DD-HHMM.csv` - Main user and project data
- `devops-users-NO-PROJECTS-YYYY-MM-DD-HHMM.csv` - Users without projects (if requested)

### Update-DevOpsUserLicenses.ps1

**Purpose**: Enhances existing CSV files with license information from the Azure DevOps API.

**Key Features**:
- Reads CSV files created by the first script
- Multiple retry strategies for API reliability
- Batch processing with configurable batch sizes
- Detailed progress reporting and statistics

**Parameters**:
- `CsvFilePath` (Required): Path to CSV file from first script
- `OrganizationUrl` (Required): Azure DevOps organization URL
- `PersonalAccessToken` (Required): PAT with User Entitlements permissions
- `OutputPath` (Optional): Output directory (default: same as input)
- `BatchSize` (Optional): API batch size (default: 100)
- `MaxRetries` (Optional): Maximum retry attempts (default: 3)

**Output**: 
- `[original-filename]-LICENSED-YYYY-MM-DD-HHMM.csv` - Enhanced with license data

### Get-UsersWithLicenseNoProjects.ps1

**Purpose**: Basic license optimization analysis to identify users with licenses but no project assignments.

**Key Features**:
- Identifies licensed users without project assignments
- Calculates potential cost savings
- Provides license hierarchy and cost estimates
- Simple optimization recommendations

**Parameters**:
- `CsvFilePath` (Required): Path to licensed CSV file
- `OutputPath` (Optional): Output directory (default: "output")

**Output**: 
- `users-with-license-no-projects-YYYY-MM-DD-HHMM.csv` - Users with licenses but no projects

### Get-LicenseOptimizationReport.ps1

**Purpose**: Advanced license optimization analysis with comprehensive cost management insights.

**Key Features**:
- Multiple analysis types: NoProjects, MinimalProjects, LicenseOptimization, All
- Detailed cost calculations for each license type
- Potential savings identification with priority rankings
- Utilization assessments and recommendations
- Comprehensive reporting with monthly/annual cost estimates

**Parameters**:
- `CsvFilePath` (Required): Path to licensed CSV file
- `AnalysisType` (Optional): Type of analysis - "NoProjects", "MinimalProjects", "LicenseOptimization", "All" (default: "All")
- `MaxProjectsForMinimal` (Optional): Max projects considered "minimal" (default: 2)
- `HighValueLicensesOnly` (Optional): Focus only on expensive licenses (default: false)
- `OutputPath` (Optional): Output directory (default: "output")

**Output**: 
- `license-optimization-report-YYYY-MM-DD-HHMM.csv` - Detailed optimization opportunities
- `license-usage-summary-YYYY-MM-DD-HHMM.csv` - License usage and cost summary

## Prerequisites

### PowerShell Version
- PowerShell 5.1 or later
- Works with both Windows PowerShell and PowerShell Core

### Azure DevOps Permissions
Create a Personal Access Token (PAT) with these permissions:
- **User Entitlements**: Read
- **Project and Team**: Read

### PAT Creation Steps
1. Go to Azure DevOps → User Settings → Personal Access Tokens
2. Click "New Token"
3. Set appropriate expiration
4. Select required scopes:
   - User Entitlements (Read)
   - Project and Team (Read)
5. Copy the generated token

4. **Copy and Secure Token**
   - ⚠️ **Important**: Copy the token immediately - you won't be able to see it again
   - Store it securely (consider using a password manager)

### Token Security Best Practices
- Never commit PAT tokens to source control
- Use tokens with minimal required permissions
- Set appropriate expiration dates
- Rotate tokens regularly
- Consider using service accounts for automated scenarios

## Installation and Setup

1. **Clone or Download**
   ```powershell
   # Clone the repository
   git clone <repository-url>
   cd DevOpsUsers
   
   # Or download the Get-DevOpsUsers.ps1 file directly
   ```

2. **Verify PowerShell Version**
   ```powershell
   $PSVersionTable.PSVersion
   ```

3. **Test Azure DevOps Connectivity**
   ```powershell
   # Test connection to your organization
   Test-NetConnection dev.azure.com -Port 443
   ```

## Usage

### Basic Execution
```powershell
.\Get-DevOpsUsers.ps1 -OrganizationUrl "https://dev.azure.com/YourOrganization" -PersonalAccessToken "your-pat-token-here"
```

### With Custom Output Directory and Logging
```powershell
.\Get-DevOpsUsers.ps1 -OrganizationUrl "https://dev.azure.com/YourOrganization" -PersonalAccessToken "your-pat-token-here" -OutputPath "C:\Reports" -LogPath "C:\Logs\devops-export.log"
```

### With Custom Retry Settings
```powershell
.\Get-DevOpsUsers.ps1 -OrganizationUrl "https://dev.azure.com/YourOrganization" -PersonalAccessToken "your-pat-token-here" -MaxRetries 5
```

### For Large Organizations (Skip Pagination)
```powershell
.\Get-DevOpsUsers.ps1 -OrganizationUrl "https://dev.azure.com/YourOrganization" -PersonalAccessToken "your-pat-token-here" -SkipPagination
```

### Limit Number of Users Retrieved
```powershell
.\Get-DevOpsUsers.ps1 -OrganizationUrl "https://dev.azure.com/YourOrganization" -PersonalAccessToken "your-pat-token-here" -MaxUsers 100
```

### With Verbose Logging
```powershell
.\Get-DevOpsUsers.ps1 -OrganizationUrl "https://dev.azure.com/YourOrganization" -PersonalAccessToken "your-pat-token-here" -Verbose
```

### Parameters

| Parameter | Required | Description | Example |
|---|---|---|---|
| `OrganizationUrl` | Yes | Full Azure DevOps organization URL | `https://dev.azure.com/contoso` |
| `PersonalAccessToken` | Yes | PAT token with required permissions | `abcd1234...` |
| `OutputPath` | No | Directory for output files (default: `.\.output`) | `C:\Reports` |
| `LogPath` | No | Optional log file path for detailed logging | `C:\Logs\export.log` |
| `MaxRetries` | No | Maximum retry attempts for API calls (default: 3) | `5` |
| `SkipPagination` | No | Skip pagination for large orgs with API issues | `-SkipPagination` |
| `MaxUsers` | No | Maximum number of users to retrieve (default: 0=no limit) | `100` |
| `UseGraphAPI` | No | Try alternative Graph API method for user retrieval | `-UseGraphAPI` |
| `ForceAllUsers` | No | Attempt multiple API methods to retrieve all users | `-ForceAllUsers` |
| `UseProjectBased` | No | **Recommended for large orgs**: Collect users via project memberships | `-UseProjectBased` |
| `ShowUsersWithoutProjects` | No | Identify and highlight users with no project assignments | `-ShowUsersWithoutProjects` |
| `ExportUsersWithoutProjects` | No | Create separate CSV file for users without projects | `-ExportUsersWithoutProjects` |

## Advanced Usage Examples

### For Large Organizations (Recommended - Project-Based Approach)
```powershell
# Best approach for large organizations with 500+ users
# Bypasses entitlements API pagination issues completely
.\Get-DevOpsUsers.ps1 -OrganizationUrl "https://dev.azure.com/YourOrganization" -PersonalAccessToken "your-pat-token-here" -UseProjectBased
```

### Find Users Without Project Assignments
```powershell
# Identifies users who have organization access but no specific project assignments
.\Get-DevOpsUsers.ps1 -OrganizationUrl "https://dev.azure.com/YourOrganization" -PersonalAccessToken "your-pat-token-here" -ShowUsersWithoutProjects -ExportUsersWithoutProjects
```

### Multiple Fallback Methods for Maximum Coverage
```powershell
# Tries multiple API methods to get the most complete user list
.\Get-DevOpsUsers.ps1 -OrganizationUrl "https://dev.azure.com/YourOrganization" -PersonalAccessToken "your-pat-token-here" -ForceAllUsers
```

### Large Organization Troubleshooting
```powershell
# For organizations experiencing API pagination errors (HTTP 500)
.\Get-DevOpsUsers.ps1 -OrganizationUrl "https://dev.azure.com/YourOrganization" -PersonalAccessToken "your-pat-token-here" -SkipPagination
```

## Real-World Usage Examples

### Example: HHSDC Organization Results
Based on testing with a large organization (HHSDC) containing 1,168 users:

**Standard Entitlements API (with pagination issues):**
- ❌ **Result**: Only 67 users retrieved due to HTTP 500 errors during pagination
- ❌ **Issue**: Azure DevOps API pagination fails on large user datasets

**Project-Based Approach (`-UseProjectBased`):**
- ✅ **Result**: 804 users successfully retrieved
- ✅ **Coverage**: ~69% of organization users (those with active project assignments)
- ✅ **Reliability**: No API pagination errors

**User Analysis (`-ShowUsersWithoutProjects`):**
- **Users with project assignments**: 804 users
- **Users without projects**: 2 users
  - 1 Stakeholder license holder (read-only access)  
  - 1 Service account with Basic license

### Choosing the Right Approach

| Organization Size | Recommended Parameters | Expected Results |
|---|---|---|
| **Small (< 100 users)** | Standard run (no special parameters) | 100% user coverage |
| **Medium (100-500 users)** | `-ForceAllUsers` | High coverage with fallback methods |
| **Large (500+ users)** | `-UseProjectBased` | Active users with project assignments |
| **Analysis Focus** | `-ShowUsersWithoutProjects` | Identify inactive or admin-only users |

## Output

### CSV File Format
The script generates a timestamped CSV file with the following columns:

| Column | Description | Example |
|---|---|---|
| User Name | Display name of the user | John Smith |
| Email | Email address | john.smith@contoso.com |
| Project Names | Semicolon-separated list of projects | ProjectA; ProjectB; ProjectC |
| License Level | Azure DevOps license type | Visual Studio Professional |

### Special Indicators

| Project Names Value | Meaning |
|---|---|
| `ProjectA; ProjectB` | User has assignments in multiple projects |
| `No project assignments` | User has org access but no specific project assignments |
| `*** NO PROJECT ASSIGNMENTS ***` | Highlighted when using `-ShowUsersWithoutProjects` |
| `Unknown License (Project-based collection)` | License info unavailable when using project-based approach |

### Sample Output Files

**Main Export (`devops-users-2025-11-13-1341.csv`):**
```csv
User Name,Email,Project Names,License Level
Manduri Nagaraju,c-nmanduri@pa.gov,"DHS Modernized Applications","Unknown License (Project-based collection)"
Holvick Aric,aholvick@pa.gov,"DHS-Web Development; DHS-Legacy Applications; DHS-EKMS","Unknown License (Project-based collection)"
Jennifer Bowers,c-jennibow@pa.gov,"*** NO PROJECT ASSIGNMENTS ***",Stakeholder
SVC-ccmpdevops,pwsvcccmpdevops@pa.gov,"*** NO PROJECT ASSIGNMENTS ***",Basic
```

**Users Without Projects (`devops-users-NO-PROJECTS-2025-11-13-1341.csv`):**
```csv
User Name,Email,Project Names,License Level
Jennifer Bowers,c-jennibow@pa.gov,"*** NO PROJECT ASSIGNMENTS ***",Stakeholder
SVC-ccmpdevops,pwsvcccmpdevops@pa.gov,"*** NO PROJECT ASSIGNMENTS ***",Basic
```

### File Naming Convention
- Format: `devops-users-YYYY-MM-DD-HHMM.csv`
- Example: `devops-users-2025-10-20-1430.csv`
- Location: `output` directory (or specified `OutputPath`)

## New Features

### Enhanced Error Handling & Retry Logic
- **Automatic Retry**: API calls automatically retry with exponential backoff
- **Rate Limiting**: Handles Azure DevOps rate limiting (HTTP 429) gracefully
- **Configurable Retries**: Set maximum retry attempts with `-MaxRetries` parameter
- **Detailed Logging**: Comprehensive logging with timestamps and severity levels

### Progress Reporting
- **Visual Progress**: Shows progress bar during project processing
- **Detailed Status**: Displays current project being processed
- **Performance Monitoring**: Tracks processing time and completion percentage

### Improved Data Safety
- **Null Safety**: Robust handling of missing or null user data
- **Data Validation**: Validates all user fields before export
- **Graceful Degradation**: Continues processing even if some data is unavailable
- **Memory Cleanup**: Automatically clears sensitive data from memory

### Advanced Logging
- **File Logging**: Optional log file output with `-LogPath` parameter
- **Severity Levels**: INFO, WARNING, ERROR, SUCCESS log levels
- **Timestamps**: All log entries include precise timestamps
- **Color Coding**: Console output uses colors for different severity levels

### Large Organization Support
- **Skip Pagination**: Use `-SkipPagination` to avoid API issues with large user lists
- **User Limits**: Set `-MaxUsers` to limit the number of users retrieved
- **Graceful Degradation**: Continues with partial data if pagination fails
- **API Issue Handling**: Robust handling of Azure DevOps API limitations

## Common License Levels

| License Type | Description |
|---|---|
| **Basic** | Standard access for up to 5 free users |
| **Basic + Test Plans** | Basic + test case management |
| **Visual Studio Professional** | Includes Visual Studio IDE subscription |
| **Visual Studio Enterprise** | Full Visual Studio Enterprise subscription |
| **Stakeholder** | Limited access for unlimited users |

## Troubleshooting

### Authentication Issues

**Error**: `401 Unauthorized`
- ✅ Verify PAT token has correct permissions
- ✅ Check token expiration date
- ✅ Ensure organization URL is correct

**Error**: `403 Forbidden`
- ✅ Verify your account has access to the organization
- ✅ Check if you have "Project Collection Administrators" or "Organization Owner" permissions

### Connection Issues

**Error**: Network connectivity problems
- ✅ Verify internet connection
- ✅ Check if corporate firewall blocks Azure DevOps
- ✅ Test: `Test-NetConnection dev.azure.com -Port 443`

**Error**: Rate limiting (HTTP 429)
- ✅ Script automatically handles rate limiting with retry logic
- ✅ Increase `-MaxRetries` parameter if needed
- ✅ Run during off-peak hours for better performance

### Script Execution Issues

**Error**: `Execution Policy` restrictions
```powershell
# Check current policy
Get-ExecutionPolicy

# Set policy for current user (if needed)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

**Error**: Large organizations timeout or API failures during user retrieval
- ✅ **Use Project-Based Approach (Recommended)**: `-UseProjectBased` bypasses entitlements API completely
- ✅ **Skip Pagination**: Use `-SkipPagination` flag to retrieve only the first batch of users  
- ✅ **Multiple Methods**: Use `-ForceAllUsers` to try multiple API approaches
- ✅ **User Limits**: Use `-MaxUsers` parameter to limit the number of users retrieved
- ✅ Some large organizations (500+ users) have API pagination issues with Azure DevOps
- ✅ The script will continue with partial data if pagination fails

### Large Organizations - Detailed Solutions

**Problem**: HTTP 500 errors during user entitlements pagination
```
[ERROR] API call failed after 3 attempts. Status: 500 (Internal Server Error)
[WARNING] Pagination attempt failed: Response status code does not indicate success: 500
```

**Root Cause**: Azure DevOps API has known limitations with large user datasets during pagination

**Recommended Solutions (in order of preference)**:

1. **Project-Based Collection (`-UseProjectBased`)** ⭐ **Best for large orgs**
   ```powershell
   .\Get-DevOpsUsers.ps1 -OrganizationUrl "https://dev.azure.com/YourOrg" -PersonalAccessToken "token" -UseProjectBased
   ```
   - ✅ **Bypasses entitlements API completely**
   - ✅ **No pagination issues**
   - ✅ **Collects active users with project assignments**
   - ❌ **May miss admin-only users or those without project assignments**

2. **Skip Pagination (`-SkipPagination`)**
   ```powershell
   .\Get-DevOpsUsers.ps1 -OrganizationUrl "https://dev.azure.com/YourOrg" -PersonalAccessToken "token" -SkipPagination
   ```
   - ✅ **Gets first batch of users reliably**
   - ✅ **Includes license information**
   - ❌ **Limited to ~67 users per batch**

3. **Multiple Fallback Methods (`-ForceAllUsers`)**
   ```powershell
   .\Get-DevOpsUsers.ps1 -OrganizationUrl "https://dev.azure.com/YourOrg" -PersonalAccessToken "token" -ForceAllUsers
   ```
   - ✅ **Tries multiple API approaches**
   - ✅ **Automatic fallback to project-based if entitlements fail**
   - ❌ **May still encounter same API limitations**

### Understanding User Coverage Results

**Real-World Example: HHSDC Organization (1,168 total users)**

| Method | Users Retrieved | Coverage | Notes |
|---|---|---|---|
| **Standard Entitlements** | 67 users | 6% | ❌ HTTP 500 errors during pagination |
| **Project-Based** | 804 users | 69% | ✅ All active users with project assignments |
| **Users Without Projects** | 2 users | <1% | 📊 Identified from entitlements sample |

**User Categories Explanation**:
- **Active Users (804)**: Users actively assigned to project teams
- **Administrative Users**: Organization admins without specific project assignments
- **Stakeholder Users**: Read-only users (often no direct project assignments)
- **Service Accounts**: Automation accounts with org-level access
- **Inactive Users**: Users with access but no current project work

**Example Analysis Output**:
```
Found 804 users with project assignments
Found 2 users with NO project assignments:
- Jennifer Bowers (Stakeholder license)
- SVC-ccmpdevops (Basic license - service account)
```

### Data Issues

**Missing project assignments**:
- Some users may not be assigned to any projects
- These appear as "No project assignments" in the CSV

**Duplicate users in different teams**:
- Script automatically deduplicates users within projects
- Users appear once per organization in the output

**Missing user information**:
- Script now handles missing display names, emails, and license info gracefully
- Missing data is replaced with descriptive placeholders

## Complete Workflow Examples

### Standard Two-Script Workflow

**Step 1: Collect Users and Projects**
```powershell
# Collect all users and their project assignments
.\Get-DevOpsUsersAndProjects.ps1 -OrganizationUrl "https://dev.azure.com/YourOrg" -PersonalAccessToken "your-pat-here"
```

**Step 2: Add License Information**
```powershell
# Enhance the CSV with license data
.\Update-DevOpsUserLicenses.ps1 -CsvFilePath ".\output\devops-users-projects-2025-11-14-1128.csv" -OrganizationUrl "https://dev.azure.com/YourOrg" -PersonalAccessToken "your-pat-here"
```

**Expected Output:**
- `devops-users-projects-2025-11-14-1128.csv` (users and projects)
- `devops-users-projects-2025-11-14-1128-LICENSED-2025-11-14-1129.csv` (enhanced with licenses)

### Complete License Optimization Workflow

**Step 3: Basic License Analysis**
```powershell
# Find users with licenses but no projects
.\Get-UsersWithLicenseNoProjects.ps1 -CsvFilePath ".\output\devops-users-projects-2025-11-14-1128-LICENSED-2025-11-14-1129.csv"
```

**Step 4: Advanced License Optimization**
```powershell
# Comprehensive license optimization analysis
.\Get-LicenseOptimizationReport.ps1 -CsvFilePath ".\output\devops-users-projects-2025-11-14-1128-LICENSED-2025-11-14-1129.csv" -AnalysisType "All"
```

**Expected Output:**
- `users-with-license-no-projects-2025-11-14-1135.csv` (basic analysis)
- `license-optimization-report-2025-11-14-1138.csv` (detailed optimization opportunities)
- `license-usage-summary-2025-11-14-1138.csv` (cost analysis and usage summary)

### Real-World Results Example

**HHSDC Organization Analysis (804 users processed):**

**License Distribution:**
- Visual Studio Enterprise: 346 users ($86,500/month)
- Basic + Test Plans: 191 users ($9,932/month)
- Visual Studio Professional: 41 users ($1,845/month)
- Stakeholder: 117 users (free)
- Other licenses: 109 users

**Optimization Opportunities:**
- Total opportunities found: 519 users
- Potential monthly savings: $73,325
- Potential annual savings: $879,900
- Average projects per user: 2.4

**Key Insights:**
- 518 users with minimal project assignments (potential downgrades)
- 1 stakeholder user with many projects (potential upgrade)
- High-value licenses with low utilization identified
- Cost-effective license redistribution recommendations

### Analysis Type Options

**NoProjects Analysis:**
```powershell
.\Get-LicenseOptimizationReport.ps1 -CsvFilePath "data.csv" -AnalysisType "NoProjects"
```
- Focuses only on users with licenses but no project assignments
- Immediate cost-saving opportunities

**MinimalProjects Analysis:**
```powershell
.\Get-LicenseOptimizationReport.ps1 -CsvFilePath "data.csv" -AnalysisType "MinimalProjects" -MaxProjectsForMinimal 3
```
- Identifies users with expensive licenses but limited project work
- Adjustable threshold for "minimal" projects

**LicenseOptimization Analysis:**
```powershell
.\Get-LicenseOptimizationReport.ps1 -CsvFilePath "data.csv" -AnalysisType "LicenseOptimization" -HighValueLicensesOnly
```
- Comprehensive analysis of license utilization patterns
- Option to focus only on expensive licenses

**All Analysis (Recommended):**
```powershell
.\Get-LicenseOptimizationReport.ps1 -CsvFilePath "data.csv" -AnalysisType "All"
```
- Complete analysis including all optimization types
- Comprehensive reporting with priority rankings

## API Endpoints Used

The script uses the following Azure DevOps REST API endpoints:

| API | Purpose | Version |
|---|---|---|
| `/_apis/userentitlements` | Get users and license information | 7.0 |
| `/_apis/projects` | List all projects | 7.0 |
| `/_apis/projects/{id}/teams` | Get teams in projects | 7.0 |
| `/_apis/projects/{id}/teams/{id}/members` | Get team members | 7.0 |

## Rate Limiting

Azure DevOps has rate limiting in place:
- The script includes automatic error handling
- Implements proper retry logic for transient failures
- Uses efficient API calls to minimize requests

## Security Considerations

- 🔒 Never hardcode PAT tokens in scripts
- 🔒 Use environment variables or secure prompt for tokens
- 🔒 Regularly rotate PAT tokens
- 🔒 Monitor PAT token usage in Azure DevOps
- 🔒 Use least-privilege permissions

## Support

For issues or questions:
1. Check the troubleshooting section above
2. Review Azure DevOps REST API documentation
3. Verify PAT token permissions and expiration

## Version History

- **v2.1**: Latest version with large organization support and comprehensive user analysis
  - ✅ **Project-Based Collection**: New `-UseProjectBased` parameter bypasses entitlements API completely
  - ✅ **User Analysis**: `-ShowUsersWithoutProjects` identifies users with no project assignments  
  - ✅ **Separate Export**: `-ExportUsersWithoutProjects` creates dedicated CSV for users without projects
  - ✅ **Multiple API Methods**: Enhanced fallback strategies for maximum user coverage
  - ✅ **Large Org Support**: Specifically designed for organizations with 500+ users
  - ✅ **Real-World Tested**: Validated with organizations containing 1,000+ users
  - ✅ **Comprehensive Reporting**: Detailed logging and progress reporting for large datasets

- **v2.0**: Enhanced version with major improvements
  - ✅ **Retry Logic**: Automatic retry with exponential backoff for API failures
  - ✅ **Rate Limiting**: Handles Azure DevOps rate limiting gracefully
  - ✅ **Progress Reporting**: Visual progress bars for long operations
  - ✅ **Enhanced Logging**: Timestamped logging with severity levels and optional file output
  - ✅ **Null Safety**: Robust handling of missing or invalid user data
  - ✅ **Memory Security**: Automatic cleanup of sensitive data
  - ✅ **Parameter Validation**: Enhanced input validation with helpful error messages
  - ✅ **Improved Timestamps**: More precise timestamps in filenames (includes time)

- **v1.0**: Initial release with basic user and project reporting