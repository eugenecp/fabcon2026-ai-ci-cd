# Azure DevOps MCP Server Setup

Quick guide to configure the Azure DevOps MCP server for the create-pr skill.

## Prerequisites

1. **Node.js**: Required for running the MCP server via npx
   - Download: https://nodejs.org/ (LTS version recommended)
   - Verify: `node --version` (should be v18+ or v20+)

2. **Azure DevOps Personal Access Token (PAT)**
   - Create at: `https://dev.azure.com/{your-org}/_usersSettings/tokens`
   - Required scopes:
     - Code: Read & Write
     - Work Items: Read
     - Project and Team: Read

## Step-by-Step Setup

### 1. Set Environment Variables

Add to your PowerShell profile for persistence:

```powershell
# Open your PowerShell profile
notepad $PROFILE

# Add this line:
$env:AZURE_DEVOPS_PAT = "your-personal-access-token"
```

Or set temporarily for current session:
```powershell
$env:AZURE_DEVOPS_PAT = "your-personal-access-token"
```

### 2. Verify MCP Configuration

The MCP server is already configured in `.vscode/mcp.json`:

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

**Note**: This file is committed to the repository and shared with the team.

### 3. Restart VS Code

After setting environment variables, restart VS Code to load the MCP server:
- Close all VS Code windows
- Open VS Code fresh
- On first use, VS Code will prompt for your Azure DevOps organization name
- Enter just the organization name (e.g., `contoso` not the full URL)
- The MCP server will initialize automatically

### 4. Verify MCP Server is Running

Test in GitHub Copilot Chat:
```
@workspace list available MCP tools
```

Or test the skill directly:
```
/create-pr
```

## Troubleshooting

### MCP Server Not Loading

**Issue**: MCP server doesn't appear in Copilot

**Solutions**:
1. Verify Node.js is installed: `node --version`
2. Check environment variable is set: `$env:AZURE_DEVOPS_PAT`
3. Check mcp.json exists: `cat .vscode/mcp.json`
4. Restart VS Code completely
5. Check VS Code Output panel → "GitHub Copilot" for errors
6. Try installing the package manually: `npx -y @azure-devops/mcp --version`

### Authentication Errors

**Issue**: PAT authentication fails

**Solutions**:
1. Verify PAT hasn't expired: `https://dev.azure.com/{org}/_usersSettings/tokens`
2. Check PAT has correct scopes (Code: Read & Write, Work Items: Read)
3. Verify environment variable is set: `$env:AZURE_DEVOPS_PAT`
4. Test PAT manually:
   ```powershell
   $headers = @{Authorization = "Basic " + [Convert]::ToBase64String([Text.Encoding]::ASCII.GetBytes(":$env:AZURE_DEVOPS_PAT"))}
   Invoke-RestMethod -Uri "https://dev.azure.com/{your-org}/_apis/projects?api-version=7.1" -Headers $headers
   ```

### NPX Download Issues

**Issue**: Can't download MCP package

**Solutions**:
1. Check internet connection
2. Check corporate proxy settings
3. Configure npm proxy if needed:
   ```bash
   npm config set proxy http://proxy.company.com:8080
   npm config set https-proxy http://proxy.company.com:8080
   ```
4. Try pre-installing: `npm install -g @azure-devops/mcp`

## Testing the Skill

Run the test script to verify everything is configured:

```powershell
.\.github\skills\create-pr\test-skill.ps1
```

This will check:
- ✓ Git repository exists
- ✓ Branch naming convention
- ✓ Changes detected
- ✓ Environment variables set
- ✓ Ready to create PR

## Next Steps

Once configured:

1. Create a feature branch: `git checkout -b feature/12345_my-feature`
2. Make changes and commit
3. Push to remote: `git push origin feature/12345_my-feature`
4. Open GitHub Copilot Chat and type: `/create-pr`

## More Information

- [Azure DevOps MCP Server (Official GitHub Repo)](https://github.com/microsoft/azure-devops-mcp)
- [Azure DevOps MCP Server Announcement](https://devblogs.microsoft.com/devops/azure-devops-mcp-server-public-preview/)
- [Model Context Protocol Documentation](https://modelcontextprotocol.io/)
- [GitHub Copilot Skills Guide](https://code.visualstudio.com/docs/copilot/customization/agent-skills)
- [Create-PR Skill README](README.md)
