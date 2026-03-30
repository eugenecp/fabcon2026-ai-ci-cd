# Quick Start Guide: AI-Powered CI/CD for Microsoft Fabric

**Time to Complete:** 15-30 minutes  
**Prerequisites:** Azure DevOps, Microsoft Fabric workspace, VS Code with GitHub Copilot

## 🎯 What You'll Build

By following this guide, you'll set up:
- ✅ Automated artifact validation on every pull request
- ✅ AI-powered code review with GitHub Copilot
- ✅ Git-integrated deployment with approval gates
- ✅ Enterprise-ready development workflow

## 📋 Before You Start

**Required:**
- Azure DevOps organization and project
- Microsoft Fabric workspace (Dev/Test environment)
- Git repository connected to Azure DevOps
- Service Principal with Fabric workspace access
- Azure DevOps Personal Access Token (PAT)
- VS Code with GitHub Copilot extension

**Nice to Have:**
- Multiple Fabric workspaces (CI, DEV, QA, PROD)
- Azure Key Vault for secret management
- Dedicated approval groups

## 🚀 Step 1: Set Up Repository Structure (5 minutes)

Create the following structure in your repository:

```
your-fabric-project/
├── .github/
│   ├── copilot-instructions.md      # AI coding guidelines
│   └── skills/
│       ├── create-pr/SKILL.md       # PR creation skill
│       └── review-pr/SKILL.md       # PR review skill
│
├── azure-pipelines.yml               # CI pipeline
├── azure-pipelines-cd.yml            # CD pipeline (optional)
│
├── scripts/
│   ├── validate-artifacts.ps1        # Validation script
│   ├── generate-validation-report.ps1
│   ├── post-pr-comment.ps1
│   └── validators/                   # Validator modules
│       ├── NotebookValidator.ps1
│       ├── LakehouseValidator.ps1
│       └── PipelineValidator.ps1
│
├── docs/
│   └── (your documentation)
│
└── (your Fabric artifacts)
    ├── *.Notebook/
    ├── *.Lakehouse/
    ├── *.DataPipeline/
    └── *.SemanticModel/
```

**Copy from this package:**
- Pipeline YAML files → repository root
- Scripts → `scripts/` folder
- Copilot skills → `.github/skills/`
- Enterprise principles → `.github/copilot-instructions.md`

## 🚀 Step 2: Configure Azure DevOps Pipeline (5 minutes)

### 2.1 Create Service Principal

```powershell
# Create service principal for Fabric API access
az ad sp create-for-rbac --name "fabric-deployment-sp" --role Contributor

# Note the output:
# appId: YOUR_CLIENT_ID
# password: YOUR_CLIENT_SECRET  
# tenant: YOUR_TENANT_ID
```

### 2.2 Grant Fabric Workspace Access

1. Go to your Fabric workspace
2. Click **Workspace settings** → **Manage access**
3. Add service principal with **Contributor** or **Admin** role

### 2.3 Create Variable Group

In Azure DevOps:
1. Go to **Pipelines** → **Library**
2. Click **+ Variable group**
3. Name: `Fabric-Workspace-CI`
4. Add variables:
   - `WorkspaceName`: Your workspace name
   - `TenantId`: Your tenant ID
   - `ClientId`: Service principal app ID
   - `ClientSecret`: Service principal password (**make secret**)
5. Click **Save**

### 2.4 Create Azure DevOps Pipeline

1. Go to **Pipelines** → **Pipelines**
2. Click **New pipeline**
3. Select **Azure Repos Git** → Choose your repository
4. Select **Existing Azure Pipelines YAML file**
5. Path: `/azure-pipelines.yml`
6. Click **Continue** → **Save**

## 🚀 Step 3: Configure GitHub Copilot Skills (5 minutes)

### 3.1 Install MCP Tools

In VS Code, create `.vscode/mcp.json`:

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

### 3.2 Set Environment Variable

```powershell
# Set PAT as environment variable
$env:AZURE_DEVOPS_PAT = "your-pat-token-here"

# Or add to your PowerShell profile for persistence
Add-Content $PROFILE "`n`$env:AZURE_DEVOPS_PAT = 'your-pat-token-here'"
```

### 3.3 Verify Skills Are Loaded

In VS Code Copilot Chat:
```
@workspace /help
```

You should see:
- `create-pr` - Create Azure DevOps Pull Request
- `review-pr` - Review Pull Request changes

## 🚀 Step 4: Test Your Setup (10 minutes)

### 4.1 Create a Test Feature

```bash
# Create feature branch
git checkout -b feature/12345_test-ci-cd-setup

# Make a small change (e.g., update README)
echo "# Testing CI/CD" >> test.md
git add test.md
git commit -m "Test: Add test file for CI/CD validation"
git push origin feature/12345_test-ci-cd-setup
```

### 4.2 Create Pull Request with AI

In VS Code Copilot Chat:
```
@workspace /create-pr
```

Copilot will:
1. ✅ Analyze your git changes
2. ✅ Generate PR title and description
3. ✅ Link work item #12345 automatically
4. ✅ Create PR in Azure DevOps

### 4.3 Watch CI Pipeline Run

1. Go to Azure DevOps → **Pipelines**
2. Find your PR build
3. Watch validation steps execute:
   - ✅ Validate notebooks
   - ✅ Validate lakehouses
   - ✅ Validate pipelines
   - ✅ Check security
   - ✅ Post PR comments

### 4.4 Review with AI

After CI passes, in VS Code Copilot Chat:
```
@workspace /review-pr
```

Copilot will:
1. ✅ Analyze changes against 5 enterprise principles
2. ✅ Provide detailed feedback
3. ✅ Suggest improvements
4. ✅ Highlight security concerns

### 4.5 Complete the PR

1. Address any feedback from AI review
2. Get human approval
3. Complete the PR
4. Watch your changes merge to main

## ✅ Success Criteria

You've successfully set up AI-powered CI/CD when:

- ✅ PRs trigger automated validation
- ✅ Validation results appear as PR comments
- ✅ GitHub Copilot can create PRs with `/create-pr`
- ✅ GitHub Copilot can review PRs with `/review-pr`
- ✅ Builds pass with green checkmarks
- ✅ Changes deploy to Fabric workspace (if CD enabled)

## 🎓 What's Next?

### Immediate Actions
1. **Read the Enterprise Principles** (01-Enterprise-Ready-Principles.md)
2. **Understand Naming Conventions** (05-Naming-Conventions.md)
3. **Customize Validation Rules** for your artifacts
4. **Set Up Additional Environments** for CD pipeline

### Advanced Topics
1. **CD Pipeline Setup** (03-CD-Pipeline-Guide.md)
   - Multi-environment deployment
   - Approval gates
   - Release branches

2. **Semantic Model Validation**
   - TMDL format
   - Best Practice Analyzer
   - Automated DAX checks

3. **Custom Validators**
   - Add organization-specific rules
   - Integrate with other tools
   - Create custom PR checks

## 🆘 Troubleshooting

### Pipeline Fails to Run
- **Check:** Service connection configured correctly
- **Check:** Service principal has workspace access
- **Check:** Variable group linked to pipeline

### Copilot Skills Not Working
- **Check:** `.vscode/mcp.json` exists with ADO server
- **Check:** `AZURE_DEVOPS_PAT` environment variable set
- **Check:** PAT has Code (Read & Write) permissions

### PR Comments Not Posted
- **Check:** PAT has permissions for Pull Request Threads
- **Check:** Script `post-pr-comment.ps1` exists
- **Check:** Build service identity has "Contribute to pull requests" permission

### Validation Fails
- **Check:** Artifacts follow naming conventions
- **Check:** No hardcoded credentials in code
- **Check:** Required metadata files present
- **Check:** Scripts/validators folder exists

## 📚 Additional Resources

- **Full CI Pipeline Guide:** 02-CI-Pipeline-Guide.md
- **Full CD Pipeline Guide:** 03-CD-Pipeline-Guide.md
- **AI Code Review Details:** 04-AI-Code-Review-Guide.md
- **Naming Standards:** 05-Naming-Conventions.md

---

**🎉 Congratulations!** You now have an enterprise-ready development workflow for Microsoft Fabric. Start building amazing data solutions with confidence!
