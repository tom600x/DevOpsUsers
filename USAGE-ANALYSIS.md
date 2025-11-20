# Enhanced Usage Analysis (v2.0)

## Deep Usage Validation

The Get-LicenseOptimizationReport.ps1 script now includes **deep usage analysis** that validates actual Azure DevOps service usage before recommending license downgrades. This ensures that license optimization recommendations are based on real usage patterns, not just project assignments.

## Key Features

- **Smart Recommendations**: Only suggests license downgrades if premium features haven't been used
- **Usage Validation**: Examines actual service usage across multiple Azure DevOps features
- **Configurable Timeframe**: Look back 1-12 months for usage patterns (default: 3 months)
- **Detailed Reporting**: Shows exactly which features each user has utilized
- **Safe Recommendations**: Never recommends downgrades unless usage analysis confirms it's safe

## Analyzed Features

### Test Plans Usage
- Test case creation and management
- Test suite organization
- Test execution tracking

### Build/Release Usage
- Build pipeline creation and execution
- Release pipeline management
- Deployment history

### Package Management Usage
- NuGet/npm package publishing
- Package feed management
- Artifact versioning

### Analytics Usage
- Advanced reporting and queries
- Custom dashboards
- Data analysis

### Extensions Usage
- Marketplace extension installation
- Extension management
- Custom extension usage

### Visual Studio IDE Features
- Premium IDE feature usage
- Advanced debugging capabilities
- Enterprise-level tooling

## Required PAT Permissions

For the usage analysis to work properly, your Personal Access Token must have these permissions:

### Basic Permissions (existing scripts)
- **User Entitlements (Read)** - Access user license information
- **Project and Team (Read)** - Access project and team data

### Extended Permissions (usage analysis)
- **Build (Read)** - Check build pipeline usage
- **Release (Read)** - Check release pipeline usage
- **Test Management (Read)** - Check Test Plans usage
- **Analytics (Read)** - Check analytics and reporting usage
- **Packaging (Read)** - Check package management usage
- **Extensions (Read)** - Check extension usage

**Note**: In the Azure DevOps PAT creation UI, look for:
- Extensions: Select "Read" checkbox
- Extension Data: Select "Read" checkbox (if available)

## Usage Examples

### Basic Usage Analysis
```powershell
.\Get-LicenseOptimizationReport.ps1 -CsvFilePath "data.csv" -PerformUsageAnalysis -OrganizationUrl "https://dev.azure.com/YourOrg" -PersonalAccessToken "your-extended-pat"
```

### Extended Lookback Period
```powershell
.\Get-LicenseOptimizationReport.ps1 -CsvFilePath "data.csv" -PerformUsageAnalysis -OrganizationUrl "https://dev.azure.com/YourOrg" -PersonalAccessToken "your-extended-pat" -UsageAnalysisMonths 6
```

### Focused Analysis on High-Value Users
```powershell
.\Get-LicenseOptimizationReport.ps1 -CsvFilePath "data.csv" -PerformUsageAnalysis -OrganizationUrl "https://dev.azure.com/YourOrg" -PersonalAccessToken "your-extended-pat" -AnalysisType "MinimalProjects" -HighValueLicensesOnly
```

## Understanding Results

### Validation Status
- **VALIDATED**: Usage analysis was performed successfully
- **Manual Review Required**: Usage analysis failed or couldn't be performed

### Recommendation Types
- **VALIDATED: Downgrade to [License]**: Safe to downgrade based on usage patterns
- **VALIDATED: Current license justified by usage**: Current license is appropriate
- **Manual validation recommended**: Usage analysis couldn't be performed

### Usage Details Field
- **Used: [Features]**: Lists the premium features the user has actually used
- **No premium features used in last X months**: User hasn't used premium features
- **Usage analysis failed**: Error occurred during analysis

## Benefits

1. **Confident Recommendations**: Only suggest changes when backed by usage data
2. **Cost Savings**: Identify genuine over-licensing situations
3. **Risk Reduction**: Avoid downgrading users who actually need premium features
4. **Detailed Insights**: Understand how your organization uses Azure DevOps features
5. **Compliance**: Ensure users have appropriate access for their actual work patterns

## Limitations

- Requires extended PAT permissions
- Some usage data may not be available in all Azure DevOps configurations
- API rate limiting may affect large organizations
- Usage analysis adds processing time to the script execution

## Troubleshooting

### 401 Unauthorized Errors
- Verify your PAT token has all required permissions
- Check that the token hasn't expired
- Ensure the organization URL is correct
- **Important**: Some permission names in the UI may differ slightly (e.g., "Extensions" vs "Extension Management")
- Create a new PAT with full permissions if uncertain about current token scope

### Missing Usage Data
- Some APIs may not be available in all Azure DevOps editions
- Usage data retention policies may limit historical data
- Certain features may not have trackable usage patterns

### Performance Issues
- Large organizations may experience longer processing times
- API rate limiting may slow down usage analysis
- Consider using smaller batch sizes or limiting analysis scope