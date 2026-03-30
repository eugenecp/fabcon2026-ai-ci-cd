# Azure Pipeline Templates

This directory contains reusable YAML templates for the CD pipeline.

## deploy-stage.yml

Reusable deployment stage template for deploying to Fabric workspaces across different environments (CI, DEV, QA, PROD).

### Parameters

| Parameter | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `environmentName` | string | Yes | - | Short environment name (CI, DEV, QA, PROD) used in stage/job names |
| `environmentDisplayName` | string | Yes | - | Display name for the environment shown in Azure DevOps |
| `azureDevOpsEnvironment` | string | Yes | - | Azure DevOps environment name for approval gates (e.g., 'Fabric-CI') |
| `variableGroup` | string | Yes | - | Azure DevOps variable group name (e.g., 'Fabric-Workspace-DEV') |
| `deployBranchPrefix` | string | Yes | - | Git branch prefix for release branches (e.g., 'release/dev') |
| `dependsOn` | object | No | ['Build'] | Array of stage names this stage depends on |
| `cleanValueSets` | boolean | No | true | Whether to clean Variable Library value sets before deployment |

### What It Does

1. **Create Release Branch**: Creates unique branch `{prefix}/{version}` from main
2. **Clean Value Sets** (optional): Removes existing Variable Library value sets
3. **Update Variable Library**: Substitutes artifact IDs using workspace-specific values
4. **Upload Transformation Files**: Uploads `/transformations` folder to lakehouse at `/Files/transformations/{version}/` path
5. **Deploy to Workspace**: Deploys artifacts to target Fabric workspace
6. **Create Release Notes** (PROD only): Generates deployment release notes

### Usage Example

```yaml
# Deploy to DEV environment
- template: templates/deploy-stage.yml
  parameters:
    environmentName: 'DEV'
    environmentDisplayName: 'DEV'
    azureDevOpsEnvironment: 'Fabric-DEV'
    variableGroup: 'Fabric-Workspace-DEV'
    deployBranchPrefix: 'release/dev'
    dependsOn: ['Build', 'DeployCI']
    cleanValueSets: true
```

### Expected Variable Group Contents

**Environment-Specific Groups:**

Each environment variable group (e.g., `Fabric-Workspace-DEV`) must contain:
- `WorkspaceName`: Microsoft Fabric workspace name (e.g., "FDT NYC Taxi - DEV")
- `LakehouseName`: Lakehouse name within the workspace (e.g., "LH_NYC_Taxi")

**Shared Authentication Group:**

The main pipeline also references `Fabric-Shared-Auth` variable group (optional) with:
- `AZURE_TENANT_ID`: Azure AD tenant ID for service principal authentication
- `AZURE_CLIENT_ID`: Service principal client ID
- `AZURE_CLIENT_SECRET`: Service principal client secret (Secret variable)

These credentials are used to authenticate with Fabric API for:
- Querying workspace artifacts for variable substitution
- Updating workspace Git connections to release branches
- Triggering Git sync operations

If not configured, the deployment will fallback to Azure CLI authentication.

### Conditional Logic

- **Value Sets Cleanup**: Only runs if `cleanValueSets: true`
- **Release Notes**: Only runs for PROD environment (`environmentName: 'PROD'`)

### Stage Dependencies

The template uses `stageDependencies` to access the build version:
```yaml
buildVersion: $[ stageDependencies.Build.CreateBuildVersion.outputs['VersionInfo.buildVersion'] ]
```

This requires:
1. A stage named 'Build' must exist and run before template stages
2. Build stage must have a job outputting 'buildVersion' variable

## Adding New Environments

To add a new environment (e.g., UAT):

1. Create Azure DevOps environment: `Fabric-UAT`
2. Create variable group: `Fabric-Workspace-UAT` with `WorkspaceName` and `LakehouseName`
3. Add template call to `azure-pipelines-cd.yml`:

```yaml
# UAT Environment
- template: templates/deploy-stage.yml
  parameters:
    environmentName: 'UAT'
    environmentDisplayName: 'UAT'
    azureDevOpsEnvironment: 'Fabric-UAT'
    variableGroup: 'Fabric-Workspace-UAT'
    deployBranchPrefix: 'release/uat'
    dependsOn: ['Build', 'DeployQA']  # Deploy after QA
    cleanValueSets: true
```

## Benefits of Template Approach

✅ **DRY Principle**: Deployment logic defined once, reused 4+ times  
✅ **Consistency**: All environments follow identical deployment process  
✅ **Maintainability**: Change deployment logic in one place  
✅ **Scalability**: Add new environments with ~10 lines of code  
✅ **Testability**: Template can be tested independently  
✅ **Readability**: Main pipeline shows high-level orchestration clearly
