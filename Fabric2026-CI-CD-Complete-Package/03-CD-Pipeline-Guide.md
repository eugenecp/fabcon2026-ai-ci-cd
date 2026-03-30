# Continuous Deployment Pipeline Guide

**Version:** 1.0  
**Last Updated:** March 2026

## Overview

This CD pipeline implements Git-integrated deployment for Microsoft Fabric workspaces with automatic version tracking, environment-specific release branches, and approval gates.

## Key Features

- **Build Version Tracking**: Date-based versions (e.g., `20260314.31.7514`)
- **Environment Branches**: Unique release branch per deployment
- **Variable Substitution**: Auto-replace artifact IDs for each environment
- **Approval Gates**: Controlled promotion CI → DEV → QA → PROD
- **Complete Audit Trail**: Git history shows all deployments
- **Easy Rollback**: Checkout any previous release branch

## Deployment Architecture

```
main branch (development)
      ↓
  Build & Version
  (20260314.31.7514)
      ↓
┌─────────────────────────────────────┐
│  CI Environment (auto-deploy)       │
│  Branch: release/ci/20260314.31.751 │
│  Approval: None                      │
└──────────────┬──────────────────────┘
               ↓ (manual approval)
┌─────────────────────────────────────┐
│  DEV Environment                     │
│  Branch: release/dev/20260314.31.75 │
│  Approval: DEV Team Lead             │
└──────────────┬──────────────────────┘
               ↓ (manual approval)
┌─────────────────────────────────────┐
│  QA Environment                      │
│  Branch: release/qa/20260314.31.751 │
│  Approval: QA Manager                │
└──────────────┬──────────────────────┘
               ↓ (manual approval)
┌─────────────────────────────────────┐
│  PROD Environment                    │
│  Branch: release/prod/20260314.31.7 │
│  Approval: Product Owner & Release   │
│  Release Notes: Auto-generated       │
└─────────────────────────────────────┘
```

## Using the Deployment Template

The CD pipeline uses a reusable template (`templates/deploy-stage.yml`) to deploy to multiple environments with consistent logic. This template is included in the package.

**Benefits:**
- ✅ **DRY Principle** - Define deployment once, use everywhere  
- ✅ **Consistency** - Same process across CI, DEV, QA, PROD  
- ✅ **Easy Updates** - Change once, affects all environments  
- ✅ **Parameterized** - Customize per environment  

**Template Parameters:**
```yaml
- template: templates/deploy-stage.yml
  parameters:
    environmentName: 'DEV'              # Short name
    environmentDisplayName: 'Development'
    azureDevOpsEnvironment: 'Fabric-DEV'
    variableGroup: 'Fabric-Workspace-DEV'
    deployBranchPrefix: 'release/dev'
    dependsOn: ['Build', 'DeployCI']
    cleanValueSets: true                # Clean before deploy
```

See `templates/README.md` in the package for detailed parameter documentation.

## Build Version Format

Every deployment gets a unique version number:

- **Format**: `YYYYMMDD.Rev.PRNumber`
- **Example**: `20260314.31.7514`
  - `20260314` = March 14, 2026
  - `31` = 31st build of the day
  - `7514` = PR #7514 that triggered the build

For direct commits (no PR): `YYYYMMDD.Rev` (e.g., `20260314.31`)

## Setup Guide

### Prerequisites

1. **Four Fabric Workspaces**
   - Workspace for CI environment
   - Workspace for DEV environment
   - Workspace for QA environment
   - Workspace for PROD environment

2. **Service Principal**
   - Azure AD app registration
   - Fabric API permissions
   - Contributor/Admin access to all workspaces

3. **Azure DevOps**
   - Repository with Fabric artifacts
   - Permissions to create pipelines and environments
   - Permissions to create variable groups

### Step 1: Create Service Principal

```powershell
# Create service principal
az ad sp create-for-rbac --name "fabric-cd-pipeline" --role Contributor

# Note the output:
# appId: YOUR_CLIENT_ID
# password: YOUR_CLIENT_SECRET
# tenant: YOUR_TENANT_ID
```

**Configure API Permissions:**

1. Go to Azure Portal → **App registrations**
2. Find your app → **API permissions**
3. Add **Power BI Service** permissions:
   - `Workspace.Read.All`
   - `Workspace.ReadWrite.All`
   - `Workspace.GitUpdate.All`
   - `Workspace.GitCommit.All`
4. Click **"Grant admin consent"**

**Enable at Tenant Level:**

1. Go to Fabric Admin Portal → **Tenant settings**
2. Enable **"Service principals can use Fabric APIs"**
3. Apply to your service principal or organization

**Grant Workspace Access:**

For each workspace (CI, DEV, QA, PROD):
1. Open workspace → **Workspace settings** → **Manage access**
2. Add service principal with **Admin** role

### Step 2: Create Azure DevOps Environments

Create four environments with approval policies:

**Fabric-CI**
1. Go to **Pipelines** → **Environments**
2. Click **New environment**
3. Name: `Fabric-CI`
4. Type: None
5. **No approvals** (auto-deploy)

**Fabric-DEV**
1. Create environment: `Fabric-DEV`
2. Go to **Approvals and checks**
3. Add **Approvals**
4. Approvers: DEV Team Lead
5. Instructions: "Review changes in CI workspace before approval"

**Fabric-QA**
1. Create environment: `Fabric-QA`
2. Add **Approvals**
3. Approvers: QA Manager, Release Manager
4. Instructions: "Validate in DEV workspace. Verify test results."

**Fabric-PROD**
1. Create environment: `Fabric-PROD`
2. Add **Approvals**
3. Approvers: Product Owner, Release Manager, Security Lead
4. Require all specified approvers
5. Instructions: "Final validation in QA. Review release notes."

### Step 3: Create Variable Groups

Create five variable groups:

**Fabric-Shared-Auth** (shared credentials)
- `AZURE_TENANT_ID`: Your tenant ID
- `AZURE_CLIENT_ID`: Service principal ID
- `AZURE_CLIENT_SECRET`: Service principal secret (**SECRET**)

**Fabric-Workspace-CI**
- `WorkspaceName`: `Your-Workspace-CI`
- `LakehouseName`: `LH_NYC_Taxi`

**Fabric-Workspace-DEV**
- `WorkspaceName`: `Your-Workspace-DEV`
- `LakehouseName`: `LH_NYC_Taxi`

**Fabric-Workspace-QA**
- `WorkspaceName`: `Your-Workspace-QA`
- `LakehouseName`: `LH_NYC_Taxi`

**Fabric-Workspace-PROD**
- `WorkspaceName`: `Your-Workspace-PROD`
- `LakehouseName`: `LH_NYC_Taxi`

**Grant pipeline permissions:**
1. For each variable group, go to **Pipeline permissions**
2. Authorize your CD pipeline

### Step 4: Create CD Pipeline

1. Go to **Pipelines** → **Create Pipeline**
2. Select **Azure Repos Git** → your repository
3. Select **Existing YAML file**
4. Path: `/azure-pipelines-cd.yml`
5. Click **Continue** → **Save**

### Step 5: Initialize Git Integration (First Time)

Before first deployment, Git integration must be configured:

**Option A: Automatic (Recommended)**
- Pipeline will auto-configure if service principal has Admin role
- No manual steps needed
- Works for fresh workspaces

**Option B: Manual (If Issues)**

For each workspace:
1. Open workspace in Fabric
2. Go to **Workspace settings** → **Git integration**
3. Click **Connect**
4. Select **Azure DevOps**
5. Organization: `YOUR_ORGANIZATION`
6. Project: `YOUR_PROJECT`
7. Repository: `YOUR_REPOSITORY`
8. Branch: (will be updated by pipeline)
9. Folder: `/` (root)
10. Click **Connect and sync**

## How Variable Substitution Works

Variable libraries contain placeholder values that get replaced with actual artifact IDs for each environment.

**Example - VL_NYC_Taxi Variable Library:**

**Source Control (`variables.json`):**
```json
{
  "LakehouseId": "",
  "NotebookId": "",
  "PipelineId": ""
}
```

**After Deployment to DEV:**
```json
{
  "LakehouseId": "12345678-1234-1234-1234-123456789abc",
  "NotebookId": "87654321-4321-4321-4321-cba987654321",
  "PipelineId": "abcdef12-3456-7890-abcd-ef1234567890"
}
```

**How It Works:**

1. Pipeline queries Fabric API for workspace artifacts
2. Finds artifact by name (e.g., `LH_NYC_Taxi`)
3. Gets artifact GUID
4. Updates variable value in `variables.json`
5. Any existing `valueSets/` folder is removed
6. Commits to release branch
7. Workspace syncs from release branch

**Benefits:**
- No hardcoded GUIDs in source control
- Environment-specific artifact references
- Automatic ID resolution per workspace
- Clean, maintainable configuration

## Understanding the Deployment Flow

### Trigger: Merge to Main

When PR merges to `main`:

1. **Build Stage**
   - Creates build version: `20260314.31.7514`
   - Stores in pipeline variable
   - Available to all deployment stages

2. **CI Deployment** (automatic)
   - Creates branch: `release/ci/20260314.31.7514`
   - Substitutes variables for CI workspace
   - Updates Git connection to release branch
   - Syncs workspace from Git
   - No approval needed

3. **DEV Deployment** (approval required)
   - Waits for approval from DEV Team Lead
   - Creates branch: `release/dev/20260314.31.7514`
   - Substitutes variables for DEV workspace
   - Updates Git connection
   - Syncs workspace

4. **QA Deployment** (approval required)
   - Waits for approval from QA Manager
   - Creates branch: `release/qa/20260314.31.7514`
   - Substitutes variables for QA workspace
   - Updates Git connection
   - Syncs workspace

5. **PROD Deployment** (approval required)
   - Waits for approval from Product Owner
   - Creates branch: `release/prod/20260314.31.7514`
   - Substitutes variables for PROD workspace
   - Updates Git connection
   - Syncs workspace
   - Generates release notes

### Approval Process

When an environment needs approval:

1. **Notification Sent**
   - Approvers receive email/Teams notification
   - Notification includes build info and changes

2. **Review in Azure DevOps**
   - Approvers go to pipeline run
   - Click **Review** button
   - See changes and previous deployments

3. **Review in Fabric Workspace**
   - Check previous environment (e.g., review DEV before approving QA)
   - Validate data pipelines ran successfully
   - Verify reports render correctly

4. **Approve or Reject**
   - **Approve**: Deployment proceeds
   - **Reject**: Deployment stops, comment required
   - **Reassign**: Send to different approver

## Rollback Procedure

If issues are detected after deployment, rollback to a previous version:

### Option 1: Quick Rollback (Update Branch)

Update workspace Git connection to previous release branch:

```powershell
# Set variables
$workspaceName = "Your-Workspace-PROD"
$previousVersion = "20260313.15.7493"  # Previous good version
$releaseBranch = "release/prod/$previousVersion"

# PowerShell script (can be run manually or via pipeline)
.\scripts\deploy-to-fabric.ps1 `
    -WorkspaceName $workspaceName `
    -BranchName $releaseBranch `
    -TenantId $env:AZURE_TENANT_ID `
    -ClientId $env:AZURE_CLIENT_ID `
    -ClientSecret $env:AZURE_CLIENT_SECRET
```

### Option 2: Re-run Previous Pipeline

1. Go to **Pipelines** → **Runs**
2. Find the previous successful run (e.g., build #7493)
3. Click **Run new**
4. Select stages to re-run (e.g., PROD only)
5. Approve and deploy

### Option 3: Hotfix Branch

For critical issues requiring code changes:

```bash
# Create hotfix branch from last good release
git checkout release/prod/20260313.15.7493
git checkout -b hotfix/critical-issue

# Make fixes
# ... edit files ...
git commit -m "Hotfix: Fix critical issue"

# Push and create PR
git push origin hotfix/critical-issue
# Create PR in Azure DevOps targeting main

# After PR approval, merge to main
# CD pipeline will create new release branches
```

## Monitoring Deployments

### Pipeline Dashboard

1. Go to **Pipelines** → **Runs**
2. View recent deployments
3. Check status of each environment:
   - **Succeeded**: Deployed successfully
   - **Waiting**: Pending approval
   - **Failed**: Error occurred (check logs)

### Git Branch History

```bash
# List all release branches
git branch -r | grep release/

# View releases for specific environment
git branch -r | grep release/prod/

# See what's deployed in each environment
git log --oneline release/ci/20260314.31.7514
git log --oneline release/dev/20260314.31.7514
git log --oneline release/qa/20260314.31.7514
git log --oneline release/prod/20260313.15.7493
```

### Fabric Workspace Git Info

In each workspace:
1. Go to **Workspace settings** → **Git integration**
2. See currently connected branch
3. View last sync timestamp
4. Check for uncommitted changes

## Troubleshooting

### Deployment Fails: "Invalid Credentials"

**Cause:** Service principal not configured correctly

**Solution:**
1. Verify API permissions granted in Azure AD
2. Check secret hasn't expired
3. Ensure service principal added to workspace as Admin
4. Wait 5-10 minutes after permission changes

### Variable Substitution Fails

**Cause:** Artifact not found in workspace

**Solution:**
1. Check artifact name matches exactly (case-sensitive)
2. Verify artifact exists in workspace
3. Ensure service principal can query workspace items
4. Check variable library follows expected structure

### Git Sync Fails: "Branch Not Found"

**Cause:** Release branch not created

**Solution:**
1. Check Build stage completed successfully
2. Verify release branch created in Git
3. Ensure proper permissions for branch creation
4. Check Azure DevOps PAT has Code (Read & Write) scope

### Approval Timeout

**Cause:** Approvers didn't respond in time

**Solution:**
1. Pipeline run expired (default: 30 days)
2. Send reminder to approvers
3. Re-run pipeline stage after approval given
4. Consider adjusting timeout in environment settings

## Best Practices

### For Release Managers

1. **Schedule Production Deployments**
   - Deploy during business hours
   - Avoid deployments on Fridays
   - Plan maintenance windows

2. **Document Releases**
   - Use release notes feature
   - Include breaking changes
   - List new features and fixes

3. **Test Before Production**
   - Always validate in QA first
   - Run regression tests
   - Verify data quality

4. **Monitor After Deployment**
   - Watch pipeline runs for 1 hour
   - Check Fabric workspace logs
   - Validate critical reports

### For Development Teams

1. **Meaningful Commit Messages**
   - Include work item IDs
   - Describe changes clearly
   - Helps with release notes

2. **Small, Frequent Releases**
   - Deploy often to reduce risk
   - Easier to identify issues
   - Faster feedback

3. **Tag Important Releases**
   ```bash
   git tag -a v1.0.0 -m "Production release 1.0"
   git push --tags
   ```

### For Operations Teams

1. **Regular Secret Rotation**
   - Rotate service principal secrets quarterly
   - Update variable group with new secrets
   - Test after rotation

2. **Maintain Branch History**
   - Keep release branches for audit trail
   - Delete very old branches (>1 year)
   - Tag major releases

3. **Backup Production**
   - Regular workspace exports
   - Store release branches safely
   - Document rollback procedures

## Advanced Topics

### Multi-Region Deployments

Deploy to multiple regions:

```yaml
- stage: PROD_WEST
  dependsOn: QA
  jobs:
  - template: deploy-template.yml
    parameters:
      workspaceName: 'Your-Workspace-PROD-WEST'
      
- stage: PROD_EAST
  dependsOn: PROD_WEST
  jobs:
  - template: deploy-template.yml
    parameters:
      workspaceName: 'Your-Workspace-PROD-EAST'
```

### Canary Deployments

Deploy to small subset before full rollout:

```yaml
- stage: PROD_Canary
  jobs:
  - deployment: Deploy10Percent
    environment: Fabric-PROD-Canary
    
- stage: PROD_Full
  dependsOn: PROD_Canary
  condition: succeeded()
  jobs:
  - deployment: Deploy100Percent
    environment: Fabric-PROD
```

### Blue-Green Deployments

Maintain two production environments:

1. Deploy to "Blue" (inactive)
2. Test thoroughly
3. Switch traffic to "Blue"
4. "Green" becomes inactive (available for rollback)

## Next Steps

1. **Run Your First Deployment**
   - Merge a PR to main
   - Watch CI auto-deploy
   - Approve DEV deployment
   - Validate each environment

2. **Configure Monitoring**
   - Set up pipeline failure alerts
   - Add Fabric workspace monitoring
   - Create deployment dashboard

3. **Document Your Process**
   - Customize this guide for your team
   - Add organization-specific steps
   - Share with stakeholders

---

**🚀 Your CD pipeline is production-ready!** Every merge to main will trigger controlled, auditable deployments across all environments.
