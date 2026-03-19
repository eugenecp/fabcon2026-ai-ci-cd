# PowerShell Automation Scripts Overview

This document describes the PowerShell scripts used for CI/CD automation in Microsoft Fabric projects.

## Scripts Summary

| Script | Purpose | Used By |
|--------|---------|---------|
| `validate-artifacts.ps1` | Validates all Fabric artifacts against enterprise principles | CI Pipeline |
| `generate-validation-report.ps1` | Creates markdown report from validation results | CI Pipeline |
| `post-pr-comment.ps1` | Posts validation results as PR comment | CI Pipeline |
| `deploy-to-fabric.ps1` | Deploys artifacts to Fabric workspace via Git sync | CD Pipeline |
| `substitute-variable-libraries.ps1` | Replaces placeholders with actual artifact IDs | CD Pipeline |
| `sync-workspace-from-git.ps1` | Triggers Fabric workspace Git sync | CD Pipeline |

## Core Scripts

### validate-artifacts.ps1

**Purpose:** Orchestrates validation of all Fabric artifacts

**Parameters:**
- `-OutputPath` (required): Path to write JSON results
- `-ArtifactPath` (optional): Specific artifact folder to validate

**Output:**
```json
{
  "timestamp": "2026-03-16T10:30:00Z",
  "results": [
    {
      "artifact": "NB_2000_SILVER_Transform.Notebook",
      "principle": "Make It Secure",
      "severity": "Error",
      "message": "Hardcoded credential detected at line 45",
      "file": "notebook-content.py",
      "line": 45
    }
  ],
  "summary": {
    "total": 25,
    "passed": 22,
    "warnings": 2,
    "errors": 1
  }
}
```

**Usage:**
```powershell
.\scripts\validate-artifacts.ps1 -OutputPath "results.json"
```

**Validators Called:**
- `NotebookValidator.ps1` - Validates notebooks
- `LakehouseValidator.ps1` - Validates lakehouses  
- `PipelineValidator.ps1` - Validates data pipelines
- `SemanticModelValidator.ps1` - Validates TMDL semantic models

---

### generate-validation-report.ps1

**Purpose:** Converts JSON validation results to markdown report

**Parameters:**
- `-ResultsPath` (required): Path to validation JSON results
- `-OutputPath` (required): Path to write markdown report

**Output:** Markdown report grouped by enterprise principle

**Usage:**
```powershell
.\scripts\generate-validation-report.ps1 `
    -ResultsPath "results.json" `
    -OutputPath "report.md"
```

**Report Format:**
```markdown
# Artifact Validation Results

## Summary
- ✅ Passed: 22 checks
- ⚠️ Warnings: 2 checks
- ❌ Failed: 1 check

## ❌ Principle 2: Make It Secure

### NB_2000_SILVER_Transform.Notebook
- **Error**: Hardcoded credential at line 45
```

---

### post-pr-comment.ps1

**Purpose:** Posts validation report as Azure DevOps PR comment

**Parameters:**
- `-ResultsPath` (required): Path to validation JSON
- `-PullRequestId` (required): PR number
- `-RepositoryId` (required): Repository GUID
- `-ProjectId` (required): Project GUID
- `-OrganizationUri` (required): Azure DevOps URL

**Environment Variables:**
- `SYSTEM_ACCESSTOKEN`: Azure DevOps authentication token

**Usage:**
```powershell
$env:SYSTEM_ACCESSTOKEN = $accessToken

.\scripts\post-pr-comment.ps1 `
    -ResultsPath "results.json" `
    -PullRequestId 7514 `
    -RepositoryId "12345678-1234-1234-1234-123456789abc" `
    -ProjectId "87654321-4321-4321-4321-cba987654321" `
    -OrganizationUri "https://dev.azure.com/yourorg/"
```

**Behavior:**
- Creates new thread if first comment
- Updates existing thread if validations already posted
- Sets thread status: **active** (failed) or **closed** (passed)

---

### deploy-to-fabric.ps1

**Purpose:** Deploys artifacts to Fabric workspace via Git integration

**Parameters:**
- `-WorkspaceName` (required): Target Fabric workspace name
- `-BranchName` (required): Git branch to deploy from
- `-TenantId` (required): Azure AD tenant ID
- `-ClientId` (required): Service principal client ID
- `-ClientSecret` (required): Service principal secret

**Steps:**
1. Authenticate with Fabric API
2. Get workspace ID by name
3. Initialize Git connection (if not exists)
4. Update Git connection to specified branch
5. Trigger UpdateFromGit sync
6. Poll for completion

**Usage:**
```powershell
.\scripts\deploy-to-fabric.ps1 `
    -WorkspaceName "Your-Workspace-DEV" `
    -BranchName "release/dev/20260314.31.7514" `
    -TenantId $env:AZURE_TENANT_ID `
    -ClientId $env:AZURE_CLIENT_ID `
    -ClientSecret $env:AZURE_CLIENT_SECRET
```

**Output:**
```
Authenticating with Fabric API...
Found workspace: Your-Workspace-DEV (12345678-...)
Updating Git connection to branch: release/dev/20260314.31.7514
Triggering Git sync (UpdateFromGit)...
Sync in progress... (polling every 10 seconds)
Sync completed successfully!
```

---

### substitute-variable-libraries.ps1

**Purpose:** Replaces placeholder values in variable libraries with actual artifact IDs

**Parameters:**
- `-WorkspaceName` (required): Fabric workspace name
- `-TenantId` (required): Azure AD tenant ID
- `-ClientId` (required): Service principal client ID
- `-ClientSecret` (required): Service principal secret
- `-VariableLibraryPattern` (optional): Pattern to match variable libraries (default: `VL_*`)

**Process:**
1. Finds all `*.VariableLibrary` folders
2. Reads `variables.json`
3. Queries Fabric API for artifact IDs by name
4. Replaces empty values with actual GUIDs
5. Removes any `valueSets/` folder
6. Writes updated `variables.json`

**Example:**

**Before (source control):**
```json
{
  "LakehouseId": "",
  "NotebookId": ""
}
```

**After (environment-specific):**
```json
{
  "LakehouseId": "12345678-1234-1234-1234-123456789abc",
  "NotebookId": "87654321-4321-4321-4321-cba987654321"
}
```

**Usage:**
```powershell
.\scripts\substitute-variable-libraries.ps1 `
    -WorkspaceName "Your-Workspace-PROD" `
    -TenantId $env:AZURE_TENANT_ID `
    -ClientId $env:AZURE_CLIENT_ID `
    -ClientSecret $env:AZURE_CLIENT_SECRET
```

---

### sync-workspace-from-git.ps1

**Purpose:** Triggers Fabric workspace Git sync operation

**Parameters:**
- `-WorkspaceId` (required): Workspace GUID
- `-TenantId` (required): Azure AD tenant ID
- `-ClientId` (required): Service principal client ID
- `-ClientSecret` (required): Service principal secret
- `-ConflictResolution` (optional): How to handle conflicts (default: `Workspace`)
- `-PollInterval` (optional): Seconds between status checks (default: 10)

**Usage:**
```powershell
.\scripts\sync-workspace-from-git.ps1 `
    -WorkspaceId "12345678-1234-1234-1234-123456789abc" `
    -TenantId $env:AZURE_TENANT_ID `
    -ClientId $env:AZURE_CLIENT_ID `
    -ClientSecret $env:AZURE_CLIENT_SECRET
```

**Output:**
```
Triggering UpdateFromGit for workspace 12345678-...
Sync operation started
Status: Running... (elapsed: 10s)
Status: Running... (elapsed: 20s)
Status: Succeeded (total time: 27s)
```

## Validator Modules

Located in `scripts/validators/` folder:

### NotebookValidator.ps1

**Validates:**
- Python syntax (using `ast` module)
- Security patterns (hardcoded credentials, API keys)
- Naming convention compliance
- Documentation presence (markdown cells)
- Code structure (imports, functions, main logic)

**Functions:**
- `Invoke-NotebookValidation` - Main entry point
- `Test-PythonSyntax` - Parse Python code
- `Test-SecurityPatterns` - Scan for credentials
- `Test-NamingConvention` - Check artifact name

---

### LakehouseValidator.ps1

**Validates:**
- Metadata file structure (lakehouse.metadata.json)
- Required properties present
- Naming convention compliance
- Shortcuts configuration

**Functions:**
- `Invoke-LakehouseValidation` - Main entry point
- `Test-MetadataStructure` - Validate JSON structure
- `Test-NamingConvention` - Check artifact name

---

### PipelineValidator.ps1

**Validates:**
- JSON structure (pipeline-content.json)
- Activity configuration
- Error handling activities
- Retry policies
- Naming convention compliance

**Functions:**
- `Invoke-PipelineValidation` - Main entry point
- `Test-PipelineStructure` - Validate JSON
- `Test-ErrorHandling` - Check for error activities
- `Test-RetryPolicies` - Verify retry logic

---

### SemanticModelValidator.ps1

**Validates:**
- TMDL structure and syntax
- Best Practice Analyzer (BPA) rules
- Documentation (/// comments)
- Naming convention compliance
- DAX measure quality

**Functions:**
- `Invoke-SemanticModelValidation` - Main entry point
- `Test-TMDLStructure` - Parse TMDL files
- `Invoke-BPAValidation` - Run BPA rules
- `Test-Documentation` - Check for descriptions

**Requires:**
- Node.js 18+
- `@microsoft/powerbi-modeling-best-practices-rules` npm package

---

## Helper Functions

### Common Patterns

**Fabric API Authentication:**
```powershell
function Get-FabricAccessToken {
    param(
        [string]$TenantId,
        [string]$ClientId,
        [string]$ClientSecret
    )
    
    $body = @{
        tenant = $TenantId
        client_id = $ClientId
        client_secret = $ClientSecret
        grant_type = "client_credentials"
        scope = "https://api.fabric.microsoft.com/.default"
    }
    
    $response = Invoke-RestMethod `
        -Uri "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token" `
        -Method Post `
        -Body $body
    
    return $response.access_token
}
```

**Fabric API Calls:**
```powershell
function Invoke-FabricAPI {
    param(
        [string]$Endpoint,
        [string]$Method = "GET",
        [string]$AccessToken,
        [object]$Body = $null
    )
    
    $headers = @{
        "Authorization" = "Bearer $AccessToken"
        "Content-Type" = "application/json"
    }
    
    $params = @{
        Uri = "https://api.fabric.microsoft.com/v1/$Endpoint"
        Method = $Method
        Headers = $headers
    }
    
    if ($Body) {
        $params.Body = ($Body | ConvertTo-Json -Depth 10)
    }
    
    return Invoke-RestMethod @params
}
```

**Error Handling:**
```powershell
try {
    # Attempt operation
    $result = Invoke-SomeOperation
} catch {
    Write-Host "##vso[task.logissue type=error]$($_.Exception.Message)"
    Write-Host "##vso[task.complete result=Failed;]"
    exit 1
}
```

## Customization Guide

### Adding a New Validator

1. **Create validator file:**
   ```powershell
   # scripts/validators/MyCustomValidator.ps1
   
   function Invoke-MyCustomValidation {
       param(
           [string]$ArtifactPath
       )
       
       $results = @()
       
       # Your validation logic here
       if (Test-MyCondition $ArtifactPath) {
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

2. **Register in validate-artifacts.ps1:**
   ```powershell
   # Import custom validator
   . "$PSScriptRoot/validators/MyCustomValidator.ps1"
   
   # Call during validation
   if ($artifactType -eq "*.CustomType") {
       $results += Invoke-MyCustomValidation -ArtifactPath $path
   }
   ```

### Adjusting Validation Rules

**Change severity:**
```powershell
# In validator, change from Error to Warning
$results += @{
    Severity = "Warning"  # Was: "Error"
    Message = "Consider adding documentation"
}
```

**Skip certain patterns:**
```powershell
# Skip temporary artifacts
if ($ArtifactName -match "^TEMP_") {
    Write-Host "Skipping temporary artifact"
    return @()
}
```

**Add organization-specific checks:**
```powershell
# Check for company-specific patterns
if ($content -notmatch "Copyright.*YourCompany") {
    $results += @{
        Principle = "Make It Maintainable"
        Severity = "Warning"
        Message = "Missing company copyright header"
    }
}
```

## Troubleshooting

### Common Issues

**Issue:** "Access token expired"
- **Cause:** Token lifetime (default: 1 hour)
- **Solution:** Refresh token before each API call

**Issue:** "Workspace not found"
- **Cause:** Service principal lacks workspace access
- **Solution:** Add service principal as Admin to workspace

**Issue:** "Git sync failed"
- **Cause:** Conflicts between workspace and Git
- **Solution:** Check `ConflictResolution` parameter, review workspace changes

**Issue:** "BPA validation hangs"
- **Cause:** Large semantic model or slow Node.js
- **Solution:** Run BPA only on changed models, increase timeout

### Debugging Tips

**Enable verbose logging:**
```powershell
$VerbosePreference = "Continue"
.\scripts\validate-artifacts.ps1 -OutputPath "results.json" -Verbose
```

**Test individual validators:**
```powershell
. .\scripts\validators\NotebookValidator.ps1
Invoke-NotebookValidation -ArtifactPath ".\NB_Test.Notebook"
```

**Inspect Fabric API responses:**
```powershell
$response = Invoke-FabricAPI -Endpoint "workspaces" -AccessToken $token
$response | ConvertTo-Json -Depth 10
```

## Best Practices

1. **Error Handling**
   - Always wrap API calls in try/catch
   - Log meaningful error messages
   - Exit with non-zero code on failure

2. **Logging**
   - Use `Write-Host` for pipeline logs
   - Use Azure DevOps logging commands for formatting
   - Log timestamps for long operations

3. **Security**
   - Never log secrets or access tokens
   - Use environment variables for credentials
   - Clear sensitive variables after use

4. **Performance**
   - Cache access tokens (valid for 1 hour)
   - Run validators in parallel where possible
   - Validate only changed artifacts in PR builds

5. **Maintainability**
   - Keep scripts modular (one purpose per script)
   - Use consistent parameter names
   - Document complex logic
   - Include usage examples

---

**Need Help?** Check individual script headers for detailed documentation and examples.
