---
name: create-pr
description: 'Create Azure DevOps Pull Request with AI-generated title and description. Use for creating PRs, submitting code for review, linking work items, generating PR descriptions from git changes.'
argument-hint: 'Optional: target branch (defaults to main)'
---

# Create Azure DevOps Pull Request

Automates pull request creation in Azure DevOps with AI-generated title and description based on git changes. Automatically links work items based on branch naming convention.

> **✨ Updated March 2026**: Added critical MCP tool parameter requirements, 4000-character description limit, and real-world example from PR #7501. See [MCP Tool Parameter Requirements](#mcp-tool-parameter-requirements) for exact specifications.

## When to Use

- Creating a new pull request from current branch
- Need AI-generated PR title and description
- Want automatic work item linking
- Ready to submit code for review

## Branch Naming Convention

This skill expects branches to follow the pattern:
```
<type>/<workItemId>[-_]<description>
```

Examples:
- `feature/12345_add-validation-logic`
- `feature/12345-add-validation-logic`
- `bugfix/67890_fix-null-reference`

The work item ID will be automatically extracted and linked to the PR. Both underscores and hyphens are supported as separators.

## Prerequisites

- Current branch must be different from target branch (default: main)
- Azure DevOps MCP server configured in `.vscode/mcp.json`
- Azure DevOps Personal Access Token set in environment variable `AZURE_DEVOPS_PAT`
- Git repository initialized with remote configured
- Repository must exist in Azure DevOps project
- **MCP tools must be loaded first**: Use `tool_search_tool_regex` to load deferred MCP tools before calling them

## Procedure

The skill performs these steps:

### 1. Validate Environment

- Verify git repository exists
- Confirm current branch differs from target
- Extract work item ID from branch name

### 2. Analyze Changes

- Compare current branch to target branch (e.g., origin/main)
- Collect file changes, additions, deletions
- Generate diff summary

### 3. Generate PR Content

Uses AI to create:
- **Title**: Concise summary of changes (< 100 characters)
- **Description**: Detailed explanation including:
  - What changed and why
  - Key modifications
  - Related work items
  - Testing notes (if applicable)
  - **Maximum 4000 characters** (Azure DevOps limit)

### 4. Check for Existing PR

Uses `mcp_ado_repo_list_pull_requests_by_repo_or_project` to verify:
- Search for PRs from the source branch (returns active PRs by default)
- **Do not specify status parameter** - it's not supported
- If existing PR found:
  - Display PR ID, title, and URL
  - Stop and inform user to update existing PR or close it first
- If no existing PR found, proceed to creation

### 5. Create Pull Request

Uses `mcp_ado_repo_create_pull_request` with parameters:
- **title**: AI-generated PR title (< 100 characters)
- **description**: Markdown-formatted PR description (< 4000 characters max)
- **sourceRefName**: Full ref name (e.g., `refs/heads/feature/123_my-feature`)
- **targetRefName**: Target branch ref (e.g., `refs/heads/main`)
- **repositoryId**: Repository GUID from Azure DevOps
- **isDraft**: Boolean for draft status
- **workItems**: Work item ID extracted from branch name (string format)

**Important**: Do NOT include `project` parameter - only `repositoryId` is required for repository identification.

## Azure DevOps MCP Integration

This skill uses the Azure DevOps MCP server to interact with Azure DevOps instead of direct REST API calls. The MCP server provides:

- **Interactive Setup**: Prompts for organization name on first use
- **Simplified Authentication**: Single PAT environment variable
- **Type-Safe Operations**: Validated inputs and outputs
- **Better Error Handling**: Contextual error messages
- **Rate Limiting**: Automatic retry and throttling

### MCP Configuration

The skill requires the Azure DevOps MCP server to be configured in `.vscode/mcp.json`:

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

**Environment Variable Required:**
```powershell
$env:AZURE_DEVOPS_PAT = "your-personal-access-token"
```

On first use, VS Code will prompt you to enter your Azure DevOps organization name (the name from your URL: `https://dev.azure.com/{org-name}`).

### MCP Tools Used

This skill uses the following Azure DevOps MCP tools:
- `mcp_ado_repo_list_pull_requests_by_repo_or_project`: Check for existing PRs from source branch
- `mcp_ado_repo_create_pull_request`: Create new pull requests
- `mcp_ado_repo_get_repo_by_name_or_id`: Get repository information
- `mcp_ado_wit_get_work_item`: Validate work item existence (optional)

### MCP Tool Parameter Requirements

**Critical: These tools have specific parameter constraints that will cause errors if not followed.**

#### `mcp_ado_repo_get_repo_by_name_or_id`
✅ **Required parameters:**
- `project` (string): Project name (e.g., "FDT - NYC Taxi")
- `repositoryNameOrId` (string): Repository name or GUID

#### `mcp_ado_repo_list_pull_requests_by_repo_or_project`
✅ **Supported parameters:**
- `project` (string): Project name
- `repositoryId` (string): Repository GUID
- `sourceRefName` (string): Source branch ref (e.g., "refs/heads/feature/123_branch")

❌ **Do NOT include:**
- `status` parameter - causes "must be equal to one of the allowed values" error
- The tool returns active PRs by default

#### `mcp_ado_repo_create_pull_request`
✅ **Required parameters:**
- `title` (string): Max 100 characters recommended
- `description` (string): **Max 4000 characters** (API limit)
- `sourceRefName` (string): Full ref (e.g., "refs/heads/feature/123_branch")
- `targetRefName` (string): Full ref (e.g., "refs/heads/main")
- `repositoryId` (string): Repository GUID
- `isDraft` (boolean): true/false
- `workItems` (string): Work item ID in string format (e.g., "23385")

❌ **Do NOT include:**
- `project` parameter - causes "must NOT have additional properties" error
- The `repositoryId` alone is sufficient for identification

### Implementation Notes

**The skill uses MCP tools directly.** When invoked through GitHub Copilot:

1. **Load MCP tools first**: Use `tool_search_tool_regex` with pattern `mcp_ado_repo` to load deferred tools
2. Uses `git` commands to gather branch and change information
3. Uses AI to generate title and description from changes (keep under 4000 chars)
4. Calls `mcp_ado_repo_get_repo_by_name_or_id` to get repository GUID
5. Calls `mcp_ado_repo_list_pull_requests_by_repo_or_project` to check for duplicates
6. Calls `mcp_ado_repo_create_pull_request` to create PR with work item linking

**Critical MCP Tool Requirements**:
- `mcp_ado_repo_create_pull_request` requires `repositoryId` only (no `project` parameter)
- `mcp_ado_repo_list_pull_requests_by_repo_or_project` should not include `status` parameter
- `workItems` parameter accepts string format (e.g., "23385")
- Description must be under 4000 characters

## Usage Examples

### Basic Usage (Interactive)

When invoked, the skill will:
1. Prompt for Azure DevOps organization and project (if not configured)
2. Gather git changes automatically
3. Use AI to generate title and description
4. Create the PR

### With Parameters

You can provide specific details:
- Target branch: `create a PR targeting the develop branch`
- Custom description: `create a PR with additional context about...`

### Real-World Example: PR #7501 (March 2026)

**Input:**  
"create a pull request for this work" (from branch `feature/23385-create-data-pipelines-to-execute-transformations`)

**AI-Generated Title:**  
"Implement FDT-Powered Medallion Layer Transformations with CDC Support"

**AI-Generated Description:**
```markdown
## Summary

Implements comprehensive FDT-powered Bronze→Silver→Gold transformations 
with Change Data Capture (CDC) support for the NYC Taxi analytics platform.

## Changes Made

### 🏗️ Core Infrastructure
- ✅ Added fabricdatatransformer JAR to environment
- ✅ Created NB_Transform_Medallion_Layers (Scala) for FDT execution
...

### 📊 Transformations (15 YAML Files)
**Bronze → Silver (7):** Green/Yellow trip data, payment type, rate code...
**Silver → Gold (8):** Date dimension, 6 business dimensions, fact_taxi_trip
...

**78 files changed:** 11,449 insertions, 4,119 deletions
```

**Result:**  
PR #7501 created successfully with work item #23385 automatically linked

**Exact MCP Tool Calls:**

```python
# Step 1: Load MCP tools (REQUIRED - tools are deferred)
tool_search_tool_regex(pattern="mcp_ado_repo")

# Step 2: Get repository information
mcp_ado_repo_get_repo_by_name_or_id(
    project="FDT - NYC Taxi",
    repositoryNameOrId="FDT - NYC Taxi"
)
# Returns: {"id": "6cb32941-21e2-4218-bd85-7c763742c084", ...}

# Step 3: Check for existing PRs
mcp_ado_repo_list_pull_requests_by_repo_or_project(
    project="FDT - NYC Taxi",
    repositoryId="6cb32941-21e2-4218-bd85-7c763742c084",
    sourceRefName="refs/heads/feature/23385-create-data-pipelines-to-execute-transformations"
    # Do NOT include 'status' parameter - not supported
)
# Returns: [] (no existing PRs)

# Step 4: Create the PR
mcp_ado_repo_create_pull_request(
    title="Implement FDT-Powered Medallion Layer Transformations with CDC Support",
    description="## Summary\n\nImplements comprehensive...",  # < 4000 chars
    sourceRefName="refs/heads/feature/23385-create-data-pipelines-to-execute-transformations",
    targetRefName="refs/heads/main",
    repositoryId="6cb32941-21e2-4218-bd85-7c763742c084",
    isDraft=False,
    workItems="23385"
    # Do NOT include 'project' parameter - causes error
)
# Returns: {"pullRequestId": 7501, "status": 1, ...}
```

**Key Takeaways:**
- Description kept under 4000 characters by using concise formatting
- Work item ID extracted from branch name (23385) and linked automatically
- No `project` parameter needed in `create_pull_request` call
- No `status` parameter in `list_pull_requests` call

### Configuration via Environment

Set the Personal Access Token environment variable:
```powershell
$env:AZURE_DEVOPS_PAT = "your-personal-access-token"
```

**Notes**:
- The MCP server will interactively prompt for organization name on first use
- Project and repository information is automatically detected from git remote
- No additional environment variables or VS Code settings required

## AI-Generated PR Template

The AI will generate descriptions following this structure:

```markdown
## Summary
Brief overview of changes

## Changes Made
- Key change 1
- Key change 2
- Key change 3

## Related Work Items
- #{workItemId}

## Testing
Testing approach and results (if applicable)

## Notes
Any additional context or considerations
```

## Error Handling

Common issues and solutions:

| Error | Cause | Solution |
|-------|-------|----------|
| "Not a git repository" | No .git folder | Run `git init` |
| "Invalid branch name" | Branch doesn't match pattern | Rename branch to `type/####_description` |
| "No changes detected" | Branch is up to date | Make changes before creating PR |
| "PR already exists" | Active PR from source branch | View existing PR, update it, or close it first |
| "Authentication failed" | Invalid or missing PAT | Check AZURE_DEVOPS_PAT environment variable |
| "Work item not found" | Invalid work item ID | Verify work item exists |
| **"must NOT have additional properties"** | Including unsupported parameter in `create_pull_request` | Remove `project` parameter - only use `repositoryId` |
| **"must NOT have more than 4000 characters"** | PR description too long | Reduce description length, use concise formatting |
| **"must be equal to one of the allowed values"** | Invalid enum value for `status` parameter | Remove `status` parameter from `list_pull_requests` call |
| **Tool not found/deferred** | MCP tool not loaded | Call `tool_search_tool_regex` first to load deferred tools |

## Security Notes

- Personal Access Token (PAT) should have:
  - `Code (Read & Write)` permission
  - `Work Items (Read)` permission
- Never commit PAT to source control
- Use environment variables or VS Code secure storage
- PAT should have appropriate expiration (90 days recommended)

## Advanced Usage

### Custom Reviewers

The skill can be configured to automatically add reviewers based on:
- Changed files (CODEOWNERS pattern)
- Work item type
- Branch type

### PR Templates

Create a `.github/PULL_REQUEST_TEMPLATE.md` file to customize the default PR description structure.

### Draft PRs

To create a draft PR (for work in progress):
```
create a draft PR for this work
```

## Limitations

- Maximum description length: **4000 characters** (enforced by Azure DevOps API)
- Requires Azure DevOps (does not support GitHub)
- Branch must exist on remote before creating PR
- Cannot create PRs for protected branches without proper permissions
- MCP tools must be loaded via `tool_search_tool_regex` before use (deferred tools)

## Related

- [Azure DevOps REST API Documentation](https://learn.microsoft.com/rest/api/azure/devops/git/pull-requests)
- [Git Best Practices](../../copilot-instructions.md#git-integration)
- [Branch Naming Conventions](../../copilot-instructions.md#naming-conventions)
