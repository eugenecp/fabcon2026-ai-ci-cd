# Continuous Integration Pipeline Guide

**Version:** 1.0  
**Last Updated:** March 2026

## Overview

This CI pipeline automatically validates all Fabric artifacts against the 5 enterprise-ready principles on every pull request. It provides immediate feedback through PR comments, helping maintain code quality and preventing issues from reaching production.

## Pipeline Architecture

```
┌─────────────────────────────────────────────────────┐
│              Pull Request Created                    │
└────────────────┬────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────┐
│         CI Pipeline Triggered Automatically          │
├─────────────────────────────────────────────────────┤
│                                                       │
│  Stage 1: Environment Setup                          │
│   ├─ Install Python 3.11                             │
│   ├─ Install Node.js 18                              │
│   └─ Install dependencies                            │
│                                                       │
│  Stage 2: Validate Artifacts                         │
│   ├─ Validate Notebooks                              │
│   │   • Syntax check                                 │
│   │   • Security scan                                │
│   │   • Naming compliance                            │
│   │                                                   │
│   ├─ Validate Lakehouses                             │
│   │   • Metadata structure                           │
│   │   • Naming compliance                            │
│   │                                                   │
│   ├─ Validate Pipelines                              │
│   │   • JSON structure                               │
│   │   • Activity configuration                       │
│   │   • Error handling                               │
│   │                                                   │
│   ├─ Validate Semantic Models                        │
│   │   • TMDL parsing                                 │
│   │   • Best Practice Analyzer                       │
│   │   • DAX validation                               │
│   │                                                   │
│   └─ Validate Transformations (if applicable)        │
│       • YAML structure                               │
│       • DBML schema validation                       │
│                                                       │
│  Stage 3: Security Scanning                          │
│   ├─ Scan for hardcoded credentials                  │
│   ├─ Check for API keys/tokens                       │
│   └─ SQL injection detection                         │
│                                                       │
│  Stage 4: Generate Report                            │
│   ├─ Compile validation results                      │
│   ├─ Group by enterprise principle                   │
│   └─ Generate markdown report                        │
│                                                       │
│  Stage 5: Post PR Comment                            │
│   ├─ Post results as PR comment                      │
│   ├─ Create thread for violations                    │
│   └─ Close thread if all pass                        │
│                                                       │
└─────────────────────────────────────────────────────┘
                 │
                 ▼
┌─────────────────────────────────────────────────────┐
│            ✅ Build Status: Success                  │
│            ❌ Build Status: Failed                    │
└─────────────────────────────────────────────────────┘
```

## What Gets Validated

### Principle 1: Make It Work
- ✅ Valid file structure and syntax
- ✅ Required files present (metadata, content, .platform)
- ✅ JSON/Python/TMDL parsing successful
- ✅ No obvious logic errors

### Principle 2: Make It Secure
- ✅ No hardcoded credentials or API keys
- ✅ No exposed connection strings
- ✅ No SQL injection vulnerabilities
- ✅ Proper use of environment variables

### Principle 3: Make It Scale
- ✅ Incremental loading patterns detected
- ✅ Partition strategies present
- ✅ No full table scans without filters
- ✅ Optimization commands included

### Principle 4: Make It Maintainable
- ✅ Naming convention compliance
- ✅ Documentation present
- ✅ Code structure organized
- ✅ Meaningful commit messages

### Principle 5: Delight Stakeholders
- ✅ Error handling implemented
- ✅ Logging present
- ✅ Data quality checks included
- ✅ Business context in comments

## Pipeline YAML Structure

```yaml
name: fdt-nyc-taxi-ci_$(Date:yyyyMMdd)$(Rev:.r)

trigger:
  branches:
    include:
    - main

pr:
  branches:
    include:
    - main

pool:
  vmImage: 'windows-latest'

variables:
  - name: pythonVersion
    value: '3.11'

stages:
- stage: Validate
  displayName: 'Validate Fabric Artifacts'
  jobs:
  - job: ValidateArtifacts
    steps:
    
    # Setup environment
    - task: UsePythonVersion@0
    - task: NodeTool@0
    
    # Install dependencies
    - task: PowerShell@2
      displayName: 'Install Dependencies'
    
    # Validate artifacts
    - task: PowerShell@2
      displayName: 'Validate All Artifacts'
      inputs:
        filePath: 'scripts/validate-artifacts.ps1'
    
    # Generate report
    - task: PowerShell@2
      displayName: 'Generate Validation Report'
      inputs:
        filePath: 'scripts/generate-validation-report.ps1'
    
    # Post PR comment
    - task: PowerShell@2
      displayName: 'Post PR Comment'
      condition: eq(variables['Build.Reason'], 'PullRequest')
      inputs:
        filePath: 'scripts/post-pr-comment.ps1'
      env:
        SYSTEM_ACCESSTOKEN: $(System.AccessToken)
```

## Setting Up the Pipeline

### Prerequisites

1. **Azure DevOps Project**
   - Active Azure DevOps organization
   - Project with Git repository
   - Build service permissions configured

2. **Service Principal** (for deployment)
   - App registration in Azure AD
   - Client ID, Secret, Tenant ID
   - Fabric workspace Contributor access

3. **Personal Access Token** (PAT)
   - Code: Read & Write
   - Build: Read & Execute
   - Pull Request Threads: Read & Write
   - Expires in 90+ days

### Step 1: Configure Build Service Permissions

The build service needs permissions to comment on PRs:

1. Go to **Project Settings** → **Repositories** → **Security**
2. Find **[Project Name] Build Service**
3. Set these permissions to **Allow**:
   - Contribute
   - Contribute to pull requests
   - Create branch
   - Read

### Step 2: Add Scripts to Repository

Copy these scripts to your repository's `scripts/` folder:

```
scripts/
├── validate-artifacts.ps1              # Main validation orchestrator
├── generate-validation-report.ps1      # Report generator
├── post-pr-comment.ps1                # PR comment poster
└── validators/                         # Validation modules
    ├── NotebookValidator.ps1
    ├── LakehouseValidator.ps1
    ├── PipelineValidator.ps1
    └── SemanticModelValidator.ps1
```

### Step 3: Create Variable Group

1. Go to **Pipelines** → **Library**
2. Click **+ Variable group**
3. Name: `Fabric-Workspace-CI`
4. Add variables:

| Variable | Value | Secret? |
|----------|-------|---------|
| `WorkspaceName` | Your CI workspace name | No |
| `TenantId` | Azure AD tenant ID | No |
| `ClientId` | Service principal app ID | No |
| `ClientSecret` | Service principal password | **Yes** |
| `AZURE_DEVOPS_PAT` | Personal access token | **Yes** |

5. Click **Save**

### Step 4: Create the Pipeline

1. Go to **Pipelines** → **Pipelines**
2. Click **New pipeline**
3. Select **Azure Repos Git**
4. Choose your repository
5. Select **Existing Azure Pipelines YAML file**
6. Path: `/azure-pipelines.yml`
7. Click **Continue**

### Step 5: Configure Pipeline Permissions

1. Click **Edit** on your pipeline
2. Click **⋮** (more actions) → **Settings**
3. Go to **YAML** → **Triggers**
4. Enable **Pull request validation**
5. Under **Branch policies** for main:
   - Require **Build** validation
   - Select your CI pipeline

### Step 6: Test the Pipeline

Create a test PR:

```bash
# Create feature branch
git checkout -b feature/test-ci-pipeline

# Make a small change
echo "# Test CI" > test-ci.md
git add test-ci.md
git commit -m "Test: Validate CI pipeline setup"
git push origin feature/test-ci-pipeline

# Create PR in Azure DevOps
# Watch the CI pipeline run automatically
```

## Understanding Validation Results

### PR Comment Format

The pipeline posts a comment on your PR with results:

```markdown
## 🔍 Artifact Validation Results

**Build:** #12345  
**Date:** 2026-03-16 10:30:45  
**Status:** ⚠️ Issues Found

### Summary
- ✅ Passed: 12 checks
- ⚠️ Warnings: 3 checks
- ❌ Failed: 2 checks

### Artifacts Validated
- 📓 Notebooks: 5 files
- 🏠 Lakehouses: 2 files
- 🔄 Pipelines: 3 files
- 📊 Semantic Models: 1 file

---

## ❌ Principle 1: Make It Work

### NB_1000_BRONZE_Download_Data.Notebook
- ❌ **Syntax Error**: Invalid Python syntax at line 45
- ⚠️ **Warning**: Missing try-catch block for file operations

## ⚠️ Principle 2: Make It Secure

### NB_2000_SILVER_Transform.Notebook
- ⚠️ **Security**: Potential SQL injection in line 120
- ⚠️ **Best Practice**: Consider using environment variables for configuration

## ✅ Principle 3: Make It Scale
All checks passed!

## ✅ Principle 4: Make It Maintainable
All checks passed!

## ✅ Principle 5: Delight Stakeholders
All checks passed!

---

### 📝 Next Steps
1. Fix the syntax error in NB_1000_BRONZE_Download_Data
2. Address security warnings in NB_2000_SILVER_Transform
3. Update and re-run validation

---
*Automated validation powered by Azure DevOps Pipelines*
```

### Severity Levels

- **❌ Failed**: Must be fixed before merge
  - Syntax errors
  - Security vulnerabilities
  - Missing required files
  - Naming violations

- **⚠️ Warning**: Should be addressed
  - Missing documentation
  - Performance concerns
  - Code style issues
  - Best practice violations

- **✅ Passed**: Meets standards
  - All checks successful
  - No issues found

## Customizing Validation Rules

### Adding Custom Validators

Create a new validator in `scripts/validators/`:

```powershell
# CustomValidator.ps1
function Invoke-CustomValidation {
    param(
        [string]$ArtifactPath,
        [string]$ArtifactType
    )
    
    $results = @()
    
    # Your custom validation logic
    if (Test-CustomCondition $ArtifactPath) {
        $results += @{
            Principle = "Make It Work"
            Severity = "Error"
            Message = "Custom validation failed"
            File = $ArtifactPath
        }
    }
    
    return $results
}
```

Register in `validate-artifacts.ps1`:

```powershell
# Import custom validator
. "$PSScriptRoot/validators/CustomValidator.ps1"

# Call during validation
$customResults = Invoke-CustomValidation -ArtifactPath $path -ArtifactType $type
$allResults += $customResults
```

### Adjusting Severity Levels

Edit individual validators to change severity:

```powershell
# Change from Error to Warning
$results += @{
    Principle = "Make It Maintainable"
    Severity = "Warning"  # Was: "Error"
    Message = "Missing documentation"
}
```

### Disabling Specific Checks

Add skip logic in validators:

```powershell
# Skip certain checks based on artifact name
if ($ArtifactName -match "^TEMP_") {
    Write-Host "Skipping validation for temporary artifact"
    return @()
}
```

## Troubleshooting

### Pipeline Not Triggering

**Issue:** PR created but pipeline doesn't run

**Solutions:**
1. Check `pr:` section in YAML includes correct branch
2. Verify **Build validation** policy set on main branch
3. Ensure pipeline has **Pull request validation** enabled

### Permission Errors

**Issue:** "TF401027: You need the Git 'Contribute' permission"

**Solutions:**
1. Grant build service permissions (see Step 1)
2. Check that repo is not requiring specific permissions
3. Verify service connection is valid

### PR Comment Not Posted

**Issue:** Validation runs but no comment appears

**Solutions:**
1. Check **Pull Request Threads** permission for PAT
2. Verify `SYSTEM_ACCESSTOKEN` passed to script
3. Check build service has "Contribute to pull requests"
4. Review post-pr-comment.ps1 error output

### Validation Fails on Valid Code

**Issue:** False positives in validation

**Solutions:**
1. Review validator logic for edge cases
2. Add exception patterns for known valid cases
3. Adjust regex patterns to be more specific
4. Lower severity from Error to Warning

### Performance Issues

**Issue:** Pipeline takes too long to run

**Solutions:**
1. Run validators in parallel where possible
2. Cache npm/pip packages
3. Skip validation for unchanged artifacts
4. Run heavy validations (BPA) only on changed files

## Best Practices

### For Development Teams

1. **Run Local Validation First**
   ```powershell
   .\scripts\validate-artifacts.ps1 -OutputPath "results.json"
   ```

2. **Fix Issues Before Pushing**
   - Address validation errors locally
   - Don't rely on CI to catch everything

3. **Review PR Comments Promptly**
   - CI feedback is immediate
   - Fix issues while context is fresh

4. **Update Validators With Team**
   - Discuss new rules before implementing
   - Share lessons learned

### For Pipeline Administrators

1. **Keep Dependencies Updated**
   - Python packages
   - Node.js modules
   - PowerShell modules

2. **Monitor Pipeline Performance**
   - Track build times
   - Optimize slow validators
   - Use parallel jobs when possible

3. **Review Validation Rules Regularly**
   - Remove obsolete checks
   - Add new patterns as needed
   - Adjust severity based on frequency

4. **Maintain Documentation**
   - Update validator README
   - Document custom rules
   - Share validation patterns

## Advanced Topics

### Multi-Stage Validation

Split validation into stages:

```yaml
stages:
- stage: FastChecks
  jobs:
  - job: Syntax
    steps:
    - script: validate-syntax.ps1

- stage: DeepValidation
  dependsOn: FastChecks
  jobs:
  - job: Security
    steps:
    - script: validate-security.ps1
  - job: Performance
    steps:
    - script: validate-performance.ps1
```

### Conditional Validation

Run certain checks only for specific changes:

```yaml
- task: PowerShell@2
  displayName: 'Validate Semantic Models'
  condition: |
    and(
      succeeded(),
      or(
        contains(variables['Build.SourceVersionMessage'], 'SemanticModel'),
        contains(variables['System.PullRequest.SourceBranch'], 'semantic-model')
      )
    )
```

### Integration with External Tools

Call external services:

```powershell
# Call external API for validation
$response = Invoke-RestMethod -Uri "https://api.example.com/validate" `
    -Method Post `
    -Body ($artifact | ConvertTo-Json) `
    -ContentType "application/json"

if ($response.isValid -eq $false) {
    $results += @{
        Severity = "Error"
        Message = $response.errorMessage
    }
}
```

## Next Steps

1. **Set up CD Pipeline** → See [03-CD-Pipeline-Guide.md](03-CD-Pipeline-Guide.md)
2. **Configure AI Code Review** → See [04-AI-Code-Review-Guide.md](04-AI-Code-Review-Guide.md)
3. **Learn Naming Conventions** → See [05-Naming-Conventions.md](05-Naming-Conventions.md)

---

**✅ Your CI pipeline is now enterprise-ready!** Every PR will be automatically validated, ensuring only high-quality code reaches production.
