# GitHub Copilot Skills for Azure DevOps

This folder contains GitHub Copilot skills that automate pull request creation and code review in Azure DevOps.

## What Are Skills?

Skills are specialized Copilot capabilities that can be invoked using `@workspace /skill-name` in VS Code Copilot Chat. They provide:

- **Domain Expertise**: Deep knowledge of specific tasks
- **Automation**: Multi-step workflows executed automatically
- **Consistency**: Same process every time
- **Integration**: Connect with external systems (Azure DevOps, APIs)

## Available Skills

### 1. create-pr

**Purpose:** Automate Azure DevOps pull request creation with AI-generated descriptions

**Usage:**
```
@workspace /create-pr
```

**What It Does:**
1. Analyzes your committed changes
2. Generates PR title and description
3. Extracts work item ID from branch name
4. Creates PR in Azure DevOps
5. Links work item automatically

**Requirements:**
- Branch naming: `feature/12345_description`
- Azure DevOps MCP server configured
- Personal Access Token set

**Example Output:**
```
✅ Pull Request Created!

PR #7514: Add Data Validation for Taxi Trips
Link: https://dev.azure.com/yourorg/yourproject/_git/yourrepo/pullrequest/7514

Work item #12345 automatically linked.
```

---

### 2. review-pr

**Purpose:** AI-powered code review against enterprise-ready principles

**Usage:**
```
@workspace /review-pr
```

**What It Does:**
1. Analyzes all changed files
2. Evaluates against 5 enterprise principles
3. Identifies security issues
4. Suggests improvements
5. Provides actionable feedback

**Requirements:**
- Git repository with commits
- Changes compared to main branch
- `.github/copilot-instructions.md` present

**Example Output:**
```
# Code Review Results

✅ Principle 1: Make It Work - PASS
⚠️ Principle 2: Make It Secure - WARNING

Security Issue Found:
- Line 120: SQL injection risk
- Recommendation: Use parameterized queries

Overall: Ready for merge after addressing security warning
```

## Installation

### Step 1: Copy Skill Folders

Copy the entire skill folders from the package to your repository:

**From Package:**
```
shareable-package/
└── skills/
    ├── create-pr/          (3 files)
    └── review-pr/          (7 files)
```

**To Your Repository:**
```
YourRepository/
└── .github/
    └── skills/
        ├── create-pr/      (copy entire folder)
        │   ├── SKILL.md
        │   ├── README.md
        │   └── SETUP.md
        │
        └── review-pr/      (copy entire folder)
            ├── SKILL.md
            ├── README.md
            ├── SETUP.md
            ├── test-skill.ps1
            └── scripts/
                ├── analyze-artifacts.ps1
                ├── compare-branches.ps1
                └── get-file-context.ps1
```

**PowerShell Command:**
```powershell
# From the shareable-package directory
Copy-Item -Path ".\skills\*" -Destination "C:\YourRepo\.github\skills\" -Recurse -Force
```

### Step 2: Configure MCP Server

Create `.vscode/mcp.json`:

```json
{
  "mcpServers": {
    "ado": {
      "command": "npx",
      "args": [
        "-y",
        "@modelcontextprotocol/server-azure-devops"
      ],
      "env": {
        "AZURE_DEVOPS_ORG": "https://dev.azure.com/YOUR_ORGANIZATION",
        "AZURE_DEVOPS_PROJECT": "YOUR_PROJECT",
        "AZURE_DEVOPS_PAT": "${AZURE_DEVOPS_PAT}"
      }
    }
  }
}
```

### Step 3: Set Environment Variable

**Windows PowerShell:**
```powershell
$env:AZURE_DEVOPS_PAT = "your-pat-token-here"
```

**Linux/Mac:**
```bash
export AZURE_DEVOPS_PAT="your-pat-token-here"
```

### Step 4: Verify Installation

In VS Code Copilot Chat:
```
@workspace /help
```

You should see `create-pr` and `review-pr` listed.

## Usage Examples

### Creating a Pull Request

**Scenario:** You've finished a feature and want to create a PR.

```bash
# 1. Ensure you're on a feature branch
git checkout -b feature/12345_add-validation

# 2. Make changes and commit
git add .
git commit -m "Add data validation logic"
git push origin feature/12345_add-validation

# 3. In VS Code Copilot Chat:
@workspace /create-pr
```

**Copilot will:**
- Generate title: "Add Data Validation Logic for Taxi Trips"
- Generate description with summary, changes, testing notes
- Link work item #12345
- Create PR in Azure DevOps

---

### Reviewing Code Changes

**Scenario:** You want AI feedback before human review.

```bash
# 1. Commit all changes
git add .
git commit -m "Implement validation"

# 2. In VS Code Copilot Chat:
@workspace /review-pr
```

**Copilot will:**
- Analyze changes in all modified files
- Check against 5 enterprise principles
- Report security issues
- Suggest improvements
- Provide overall assessment

---

### Advanced: Custom Target Branch

**Create PR targeting `develop`:**
```
@workspace /create-pr develop
```

**Review against `develop`:**
```
@workspace /review-pr origin/develop
```

## Customization

### Modifying Skills

Edit the SKILL.md files to:

1. **Add Organization-Specific Checks**
   ```markdown
   ## Custom Validations
   
   - Check for company copyright headers
   - Validate data retention policies
   - Ensure compliance tagging
   ```

2. **Change PR Description Format**
   ```markdown
   ## PR Description Template
   
   **Jira Ticket:** PROJ-12345
   **Change Type:** Feature | Bugfix | Hotfix
   **Breaking Changes:** Yes | No
   ...
   ```

3. **Add Custom Validation Rules**
   ```markdown
   ## Review Checklist
   
   - [ ] Unit tests added
   - [ ] Integration tests pass
   - [ ] Documentation updated
   - [ ] Security scan passed
   ```

### Creating New Skills

**Template:**
```markdown
---
name: my-custom-skill
description: 'Brief description of what the skill does'
argument-hint: 'Optional: hints for arguments'
---

# My Custom Skill

## When to Use

- Describe scenarios where this skill is useful

## Prerequisites

- List requirements

## Procedure

The skill performs these steps:

### 1. Step One
- Detail what happens

### 2. Step Two
- More details

## Examples

Show usage examples

## Troubleshooting

Common issues and solutions
```

## Troubleshooting

### Skill Not Found

**Issue:** `@workspace /create-pr` shows "Unknown command"

**Solutions:**
1. Check `.github/skills/*/SKILL.md` files exist
2. Verify YAML frontmatter syntax:
   ```yaml
   ---
   name: create-pr
   description: 'Description here'
   ---
   ```
3. Reload VS Code window: `Ctrl+Shift+P` → "Reload Window"

### MCP Connection Failed

**Issue:** "Cannot connect to Azure DevOps MCP server"

**Solutions:**
1. Verify `.vscode/mcp.json` has correct format
2. Check `AZURE_DEVOPS_PAT` environment variable is set
3. Ensure PAT has correct scopes (Code Read & Write)
4. Install Node.js 18+: `node --version`

### PR Creation Fails

**Issue:** "Failed to create pull request"

**Solutions:**
1. Check branch naming: `type/12345_description`
2. Verify work item exists: `https://dev.azure.com/yourorg/yourproject/_workitems/edit/12345`
3. Ensure PAT has Pull Request permissions
4. Check that branch has changes vs. target

### Review Timeout

**Issue:** Review skill takes too long

**Solutions:**
1. Reduce number of changed files (split into smaller PRs)
2. Exclude large generated files from review
3. Check internet connection stability
4. Try again (GitHub Copilot service may be slow)

## Best Practices

### For Teams

1. **Standardize Branch Naming**
   - Enforce `type/workitem_description` pattern
   - Use Git hooks to validate before push

2. **Use Skills Consistently**
   - Require `/create-pr` for all PRs
   - Run `/review-pr` before requesting human review

3. **Share Customizations**
   - Document organization-specific customizations
   - Version control skill changes
   - Share learnings with team

4. **Measure Impact**
   - Track PRs created with skill
   - Monitor issues caught by AI review
   - Calculate time saved

### For Developers

1. **Run Review Early**
   - Don't wait until PR is created
   - Fix issues while context is fresh
   - Reduces human reviewer burden

2. **Act on Feedback**
   - Address high-priority items immediately
   - Document why you can't fix certain issues
   - Learn from repeated patterns

3. **Supplement, Don't Replace**
   - AI catches common issues
   - Humans review architecture and business logic
   - Both are valuable

## FAQ

**Q: Can I use these skills with GitHub instead of Azure DevOps?**  
A: Not directly. You'd need to modify the MCP configuration and skill logic to use GitHub APIs instead of Azure DevOps APIs.

**Q: Do skills send my code to OpenAI?**  
A: GitHub Copilot uses your code for context according to their privacy policy. Check your organization's GitHub Copilot settings.

**Q: Can I disable certain validations in review-pr?**  
A: Yes, modify the SKILL.md file to skip specific checks or change severity levels.

**Q: How do I update skills after installation?**  
A: Edit the SKILL.md files and reload VS Code window.

**Q: Can skills work offline?**  
A: No, they require internet connectivity to use GitHub Copilot service and Azure DevOps APIs.

## Additional Resources

- **GitHub Copilot Documentation**: https://code.visualstudio.com/docs/copilot/
- **Azure DevOps REST API**: https://learn.microsoft.com/rest/api/azure/devops/
- **MCP Servers**: https://github.com/modelcontextprotocol

---

**Ready to automate your workflow?** Install these skills and experience AI-powered development!
