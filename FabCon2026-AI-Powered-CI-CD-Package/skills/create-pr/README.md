# Create Pull Request Skill

Automates Azure DevOps pull request creation with AI-generated title and description.

## Quick Start

### 1. Install Azure DevOps MCP Server (One-time setup)

The skill uses the Azure DevOps MCP server for GitHub Copilot integration.

```powershell
# Install Node.js (if not already installed)
# Download from: https://nodejs.org/

# Verify installation
node --version
npm --version

# The MCP server (@azure-devops/mcp)
# will be automatically downloaded when needed via npx
```

### 2. Configure MCP Server

Create or verify `.vscode/mcp.json` in your project:

```json
{
  "inputs": [
    {
      "id": "ado_org",
      "type": "promptString",
      "description": "Azure DevOps organization name (e.g. 'contoso')"
    }
  ],
  "servers": {
    "ado": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@azure-devops/mcp", "${input:ado_org}"]
    }
  }
}
```

### 3. Set Personal Access Token

```powershell
# Set Azure DevOps PAT
$env:AZURE_DEVOPS_PAT = "your-personal-access-token"
```

Or add to your PowerShell profile (`$PROFILE`):
```powershell
# Azure DevOps Configuration
$env:AZURE_DEVOPS_PAT = "your-personal-access-token"
# Store PAT securely - consider using SecretManagement module
```

**Note**: On first use, VS Code will prompt you to enter your Azure DevOps organization name.

### 4. Verify MCP Configuration

Restart VS Code, then check MCP server status:
- Open GitHub Copilot Chat
- Type: `@workspace what MCP servers are available?`

### 5. Create Feature Branch

Follow the naming convention:
```bash
git checkout -b feature/12345_add-validation-logic
# or
git checkout -b bugfix/67890_fix-null-reference
```

Pattern: `<type>/<workItemId>_<description>`

### 6. Make Changes and Commit

```bash
git add .
git commit -m "Add validation logic"
git push origin feature/12345_add-validation-logic
```

### 7. Invoke the Skill

In GitHub Copilot Chat:
```
/create-pr
```

Or with specific target:
```
create a PR targeting develop branch
```

## How It Works

1. **Analyze**: Examines git diff between your branch and target
2. **Generate**: AI creates meaningful title and description
3. **Link**: Automatically links work item from branch name
4. **Create**: Submits PR via Azure DevOps MCP tools

## Features

✅ **Azure DevOps MCP Integration**: Native GitHub Copilot MCP server support  
✅ **AI-Generated Content**: Smart PR title and description based on changes  
✅ **Automatic Work Item Linking**: Extracts and links from branch name  
✅ **Flexible Targeting**: Supports custom target branches  
✅ **Draft PR Support**: Create work-in-progress PRs  
✅ **Smart Error Handling**: Contextual troubleshooting guidance  
✅ **Character Limits**: Respects 3000 character description limit  

## Configuration Options

### Environment Variable

The Azure DevOps MCP server requires one environment variable:

| Variable | Required | Description |
|----------|----------|-------------|
| `AZURE_DEVOPS_PAT` | Yes | Personal Access Token for authentication |

### MCP Configuration File

MCP server settings are in `.vscode/mcp.json`:

```json
{
  "inputs": [
    {
      "id": "ado_org",
      "type": "promptString",
      "description": "Azure DevOps organization name (e.g. 'contoso')"
    }
  ],
  "servers": {
    "ado": {
      "type": "stdio",
      "command": "npx",
      "args": ["-y", "@azure-devops/mcp", "${input:ado_org}"]
    }
  }
}
```

**How It Works:**
- On first use, VS Code prompts for your organization name
- Enter just the organization name (e.g., `contoso` from `https://dev.azure.com/contoso`)
- The organization name is cached for future use
- PAT is read from the `AZURE_DEVOPS_PAT` environment variable

## Personal Access Token (PAT)

### Required Permissions
The Azure DevOps MCP server needs a PAT with:
- ✅ **Code**: Read & Write
- ✅ **Work Items**: Read
- ✅ **Project and Team**: Read (for repository access)

### Create PAT
1. Go to: `https://dev.azure.com/{org}/_usersSettings/tokens`
2. Click "New Token"
3. Set name: "GitHub Copilot MCP Server"
4. Select scopes:
   - **Code**: Read & Write
   - **Work Items**: Read
   - **Project and Team**: Read
5. Set expiration (90 days recommended)
6. Copy token and store securely

### Set Environment Variable

**PowerShell** (current session):
```powershell
$env:AZURE_DEVOPS_PAT = "your-personal-access-token"
```

**PowerShell Profile** (persistent):
```powershell
# Open profile
notepad $PROFILE

# Add this line:
$env:AZURE_DEVOPS_PAT = "your-token-here"
```

### Secure Storage

**Option 1: Environment Variable** (simplest)
```powershell
$env:AZURE_DEVOPS_PAT = "your-token"
```

**Option 2: PowerShell SecretManagement** (most secure)
```powershell
Install-Module Microsoft.PowerShell.SecretManagement
Register-SecretVault -Name Local -ModuleName Microsoft.PowerShell.SecretStore
Set-Secret -Name AZURE_DEVOPS_PAT -Secret "your-token"

# Retrieve in profile
$env:AZURE_DEVOPS_PAT = Get-Secret -Name AZURE_DEVOPS_PAT -AsPlainText
```

## Branch Naming Convention

### Supported Types
- `feature/` - New features
- `bugfix/` - Bug fixes
- `hotfix/` - Production hotfixes
- `release/` - Release branches

### Format
```
<type>/<workItemId>_<description>
```

### Examples
✅ `feature/12345_add-validation-logic`  
✅ `bugfix/67890_fix-null-reference`  
✅ `hotfix/11111_critical-security-fix`  
❌ `my-feature-branch` (no work item)  
❌ `feature-12345` (wrong format)  

## Usage Examples

### Basic PR Creation
In GitHub Copilot Chat:
```
/create-pr
```

The skill will:
1. Analyze changes between your branch and origin/main
2. Generate AI-powered PR title and description
3. Extract work item ID from branch name
4. Create PR using Azure DevOps MCP tools

### Target Different Branch
```
create a PR targeting the develop branch
```

### Draft PR
```
create a draft PR for review
```

### With Additional Context
```
create a PR with note that this depends on PR #123
```

## Troubleshooting

### "MCP server not available"
**Solution**: Restart VS Code after creating `mcp.json`
```powershell
# Verify Node.js is installed
node --version

# Check mcp.json exists
cat .vscode/mcp.json
```

### "Not a git repository"
**Solution**: Ensure you're in a git repository
```bash
git status
```

### "Invalid branch name"
**Solution**: Rename branch to follow convention
```bash
git branch -m feature/12345_your-description
```

### "No changes detected"
**Solution**: Ensure your branch has commits not in target
```bash
git log origin/main..HEAD
```

### "Authentication failed"
**Solution**: Verify PAT is valid and environment variable is set
```powershell
# Check environment variable
$env:AZURE_DEVOPS_PAT

# If empty, set it
$env:AZURE_DEVOPS_PAT = "your-token"

# Test PAT manually (optional)
$headers = @{Authorization = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$env:AZURE_DEVOPS_PAT"))}
Invoke-RestMethod -Uri "https://dev.azure.com/{org}/_apis/projects?api-version=7.1" -Headers $headers
```

### "Branch does not exist on remote"
**Solution**: Push branch to remote first
```bash
git push -u origin <branch-name>
```

## AI-Generated Description Format

The skill generates descriptions following this template:

```markdown
## Summary
[Concise overview of the changes]

## Changes Made
- [Key change 1]
- [Key change 2]
- [Key change 3]

## Related Work Items
- #[workItemId]

## Testing
[Testing approach and results]

## Notes
[Additional context or considerations]
```

## Integration with Validation Pipeline

This skill integrates seamlessly with the existing validation pipeline:
1. **Create PR**: Use `/create-pr` in GitHub Copilot Chat
2. **Auto-Validate**: Azure Pipelines automatically runs validation
3. **Review Results**: Validation results posted as PR comment
4. **Fix Issues**: Address any violations found
5. **Merge**: Complete PR when validation passes

## MCP Server Benefits

Using the Azure DevOps MCP server provides several advantages:

- **Simplified Auth**: Configure PAT once, use across all operations
- **Type Safety**: Validated parameters and responses
- **Better Errors**: Contextual error messages and suggestions
- **Auto-Retry**: Built-in retry logic for transient failures
- **Rate Limiting**: Automatic throttling to respect API limits
- **Caching**: Intelligent caching of repository and project data

## Advanced Usage

### Finding Available MCP Tools

To see all Azure DevOps operations available via MCP:
```
@workspace what Azure DevOps MCP tools are available?
```

### Custom Workflows

Combine create-pr with other Azure DevOps MCP operations:
- Create and link work items
- Add reviewers based on CODEOWNERS
- Set labels and tags
- Configure auto-complete policies

## Related Documentation

- [Azure DevOps MCP Server (Official GitHub Repo)](https://github.com/microsoft/azure-devops-mcp)
- [Azure DevOps MCP Server Announcement](https://devblogs.microsoft.com/devops/azure-devops-mcp-server-public-preview/)
- [GitHub Copilot Skills Documentation](https://code.visualstudio.com/docs/copilot/customization/agent-skills)
- [Model Context Protocol](https://modelcontextprotocol.io/)
- [Azure DevOps REST API](https://learn.microsoft.com/rest/api/azure/devops/git/pull-requests)
- [Project Guidelines](../../copilot-instructions.md)

## Support

For issues or questions:
1. Check [Troubleshooting](#troubleshooting) section above
2. Verify MCP server configuration in `.vscode/settings.json`
3. Review [Azure DevOps MCP Server documentation](https://devblogs.microsoft.com/devops/azure-devops-mcp-server-public-preview/)
4. Check [Azure DevOps REST API](https://learn.microsoft.com/rest/api/azure/devops/git/pull-requests) for API details
