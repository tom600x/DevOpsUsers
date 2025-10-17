# GitHub Copilot Instructions for DevOps Users Project

## Project Overview
This project contains PowerShell scripts to extract and report on Azure DevOps Services users, their project assignments, and license levels. The primary goal is to generate CSV reports for organizational user management and license tracking.

## Key Components
- **Get-DevOpsUsers.ps1**: Main PowerShell script that connects to Azure DevOps REST API
- **README.md**: Comprehensive setup and usage documentation
- **Output**: Timestamped CSV files with user data

## Technical Context
- **Platform**: Azure DevOps Services (cloud)
- **Authentication**: Personal Access Token (PAT)
- **API**: Azure DevOps REST API v7.0+
- **Output Format**: CSV with columns: User Name, Email, Project Names, License Level
- **Execution**: Single organization, one-time script runs

## Code Patterns to Follow
- Use `Invoke-RestMethod` for API calls
- Implement proper error handling with try-catch blocks
- Use PowerShell parameter validation
- Include verbose logging for troubleshooting
- Follow PowerShell naming conventions (PascalCase for functions, camelCase for variables)

## Security Considerations
- PAT tokens should be passed as parameters, never hardcoded
- Use SecureString for sensitive data when possible
- Validate input parameters to prevent injection attacks
- Include warnings about PAT token permissions in documentation

## API Endpoints Used
- User entitlements: `GET https://vsaex.dev.azure.com/{organization}/_apis/userentitlements`
- Projects: `GET https://dev.azure.com/{organization}/_apis/projects`
- Project team members: `GET https://dev.azure.com/{organization}/_apis/projects/{projectId}/teams/{teamId}/members`

## Expected File Structure
```
DevOpsUsers/
├── .github/
│   └── copilot-instructions.md
├── Get-DevOpsUsers.ps1
├── README.md
└── output/ (created by script)
    └── devops-users-YYYY-MM-DD.csv
```

## Common Issues to Address
- Handle paginated API responses
- Manage rate limiting
- Process users with multiple project assignments
- Handle missing or null license information
- Provide clear error messages for common authentication issues