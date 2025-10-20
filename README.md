# DevOps Users Export Tool

A PowerShell script to extract and report on Azure DevOps Services users, their project assignments, and license levels.

## Overview

This tool generates CSV reports containing:
- User names and email addresses
- Project assignments for each user
- License levels (Basic, Basic + Test Plans, Visual Studio Professional, etc.)
- Timestamped output files for tracking

## Prerequisites

### PowerShell Requirements
- **PowerShell 5.1** or **PowerShell 7+** (recommended)
- No additional PowerShell modules required (uses built-in `Invoke-RestMethod`)

### Azure DevOps Requirements
- Azure DevOps Services organization (cloud)
- Personal Access Token (PAT) with appropriate permissions

## Personal Access Token (PAT) Setup

### Required Permissions
Your PAT token must have the following permissions:

| Permission Area | Required Access Level | Purpose |
|---|---|---|
| **User Profile** | Read | Access user information and email addresses |
| **Project and Team** | Read | List projects and team memberships |
| **Member Entitlement Management** | Read | Access user license information and entitlements |

### Creating a PAT Token

1. **Navigate to Azure DevOps**
   - Go to your Azure DevOps organization: `https://dev.azure.com/YourOrganization`

2. **Access Personal Access Tokens**
   - Click on your profile picture (top right)
   - Select "Personal access tokens"

3. **Create New Token**
   - Click "New Token"
   - Provide a name (e.g., "DevOps Users Export")
   - Set expiration date
   - Select the required scopes:
     - ✅ **User Profile (Read)**
     - ✅ **Project and Team (Read)**
     - ✅ **Member Entitlement Management (Read)**

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

### With Verbose Logging
```powershell
.\Get-DevOpsUsers.ps1 -OrganizationUrl "https://dev.azure.com/YourOrganization" -PersonalAccessToken "your-pat-token-here" -Verbose
```

### Parameters

| Parameter | Required | Description | Example |
|---|---|---|---|
| `OrganizationUrl` | Yes | Full Azure DevOps organization URL | `https://dev.azure.com/contoso` |
| `PersonalAccessToken` | Yes | PAT token with required permissions | `abcd1234...` |
| `OutputPath` | No | Directory for output files (default: `.\output`) | `C:\Reports` |
| `LogPath` | No | Optional log file path for detailed logging | `C:\Logs\export.log` |
| `MaxRetries` | No | Maximum retry attempts for API calls (default: 3) | `5` |

## Output

### CSV File Format
The script generates a timestamped CSV file with the following columns:

| Column | Description | Example |
|---|---|---|
| User Name | Display name of the user | John Smith |
| Email | Email address | john.smith@contoso.com |
| Project Names | Semicolon-separated list of projects | ProjectA; ProjectB; ProjectC |
| License Level | Azure DevOps license type | Visual Studio Professional |

### Sample Output
```csv
User Name,Email,Project Names,License Level
John Smith,john.smith@contoso.com,"ProjectA; ProjectB",Visual Studio Professional
Jane Doe,jane.doe@contoso.com,"ProjectA; ProjectC","Basic + Test Plans"
Bob Johnson,bob.johnson@contoso.com,"No project assignments",Basic
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

**Error**: Large organizations timeout
- ✅ Script now includes automatic retry logic and progress reporting
- ✅ Use `-Verbose` flag to monitor detailed progress
- ✅ Consider using `-LogPath` to save detailed logs
- ✅ Increase `-MaxRetries` for unreliable networks

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