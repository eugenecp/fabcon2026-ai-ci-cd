<#
.SYNOPSIS
    Update Fabric Variable Libraries and Semantic Model connections for environment-specific deployments
    
.DESCRIPTION
    This script processes Fabric Variable Libraries and Semantic Models, updating them with
    environment-specific configuration. It performs three main operations:
    
    1. Variable Library Updates:
       - Reads base variable definitions
       - Queries the target workspace for actual artifact IDs
       - Matches variables to artifacts (e.g., LakehouseId → LH_NYC_Taxi)
       - Sets DeployedVersionId to the build version
       - Removes valueSets folders and clears settings.json
    
    2. Semantic Model Connection Updates:
       - Finds all semantic model artifacts
       - Updates OneLake connection strings in expressions.tmdl
       - Points connections to the current workspace and lakehouse
    
    3. Git Integration:
       - Commits all changes to Git
       - Syncs the workspace using UpdateFromGit API with PreferRemote policy
    
    Variable matching strategy:
    - Variables ending in "Id" are matched to workspace artifacts
    - Variable names like "LakehouseId" match artifact names starting with "LH_"
    - Variable names like "NotebookId" or "SomeNotebookId" match artifacts starting with "NB_"
    - Values are set to the actual artifact GUID from the workspace
    
.PARAMETER WorkspaceName
    The Fabric workspace name where artifacts will be deployed (will be resolved to workspace ID)
    
.PARAMETER Environment
    The environment name (CI, DEV, QA, PROD) for the value set
    
.PARAMETER SourcePath
    Path to the repository containing variable library files (default: current directory)
    
.PARAMETER TenantId
    Azure AD tenant ID for authentication
    
.PARAMETER ClientId
    Service principal client ID for Fabric API authentication
    
.PARAMETER ClientSecret
    Service principal client secret for Fabric API authentication

.PARAMETER BranchName
    Git branch name to push changes to (optional, defaults to current branch)
    
.PARAMETER BuildVersion
    Build version to set in DeployedVersionId variable (format: YYYYMMDD.buildId)
    
.PARAMETER DryRun
    If specified, shows what value sets would be created without making changes
    
.EXAMPLE
    .\substitute-variable-libraries.ps1 -WorkspaceName "FDT NYC Taxi - DEV" -Environment "DEV" -TenantId "tenant-id" -ClientId "client-id" -ClientSecret "secret" -BranchName "release/dev/20260314.31" -BuildVersion "20260314.31"
    
.EXAMPLE
    .\substitute-variable-libraries.ps1 -WorkspaceName "FDT NYC Taxi - CI" -Environment "CI" -DryRun
#>

param(
    [Parameter(Mandatory=$true)]
    [string]$WorkspaceName,
    
    [Parameter(Mandatory=$true)]
    [ValidateSet('CI', 'DEV', 'QA', 'PROD')]
    [string]$Environment,
    
    [Parameter(Mandatory=$false)]
    [string]$SourcePath = ".",
    
    [Parameter(Mandatory=$false)]
    [string]$TenantId = $env:AZURE_TENANT_ID,
    
    [Parameter(Mandatory=$false)]
    [string]$ClientId = $env:AZURE_CLIENT_ID,
    
    [Parameter(Mandatory=$false)]
    [string]$ClientSecret = $env:AZURE_CLIENT_SECRET,
    
    [Parameter(Mandatory=$false)]
    [string]$BranchName,
    
    [Parameter(Mandatory=$false)]
    [string]$BuildVersion,
    
    [Parameter(Mandatory=$false)]
    [switch]$DryRun
)

$ErrorActionPreference = "Stop"

# Fabric API base URL
$fabricApiBase = "https://api.fabric.microsoft.com/v1"

#------------------------------------------------------------------
# Function: Get-FabricAccessToken
#------------------------------------------------------------------
function Get-FabricAccessToken {
    param(
        [string]$TenantId,
        [string]$ClientId,
        [string]$ClientSecret
    )
    
    if (-not $TenantId -or -not $ClientId -or -not $ClientSecret) {
        Write-Warning "Service principal credentials not provided. Attempting to use Azure CLI authentication..."
        
        # Try Azure CLI
        $token = az account get-access-token --resource "https://api.fabric.microsoft.com" --query accessToken -o tsv 2>$null
        if ($LASTEXITCODE -eq 0 -and $token) {
            return $token
        }
        
        throw "Authentication failed. Provide service principal credentials or authenticate with 'az login'"
    }
    
    # Get token using service principal
    $tokenUrl = "https://login.microsoftonline.com/$TenantId/oauth2/v2.0/token"
    $body = @{
        client_id     = $ClientId
        client_secret = $ClientSecret
        scope         = "https://api.fabric.microsoft.com/.default"
        grant_type    = "client_credentials"
    }
    
    $response = Invoke-RestMethod -Uri $tokenUrl -Method Post -Body $body -ContentType "application/x-www-form-urlencoded"
    return $response.access_token
}

#------------------------------------------------------------------
# Function: Get-FabricWorkspaces
#------------------------------------------------------------------
function Get-FabricWorkspaces {
    param(
        [string]$AccessToken
    )
    
    $headers = @{
        "Authorization" = "Bearer $AccessToken"
        "Content-Type"  = "application/json"
    }
    
    $url = "$fabricApiBase/workspaces"
    
    try {
        $response = Invoke-RestMethod -Uri $url -Method Get -Headers $headers
        return $response.value
    } catch {
        Write-Warning "Failed to retrieve workspaces: $_"
        return @()
    }
}

#------------------------------------------------------------------
# Function: Get-FabricWorkspaceIdByName
#------------------------------------------------------------------
function Get-FabricWorkspaceIdByName {
    param(
        [string]$WorkspaceName,
        [string]$AccessToken
    )
    
    $workspaces = Get-FabricWorkspaces -AccessToken $AccessToken
    
    # Try exact match first
    $workspace = $workspaces | Where-Object { $_.displayName -eq $WorkspaceName }
    
    if ($workspace) {
        return $workspace.id
    }
    
    # Try case-insensitive match
    $workspace = $workspaces | Where-Object { $_.displayName -ieq $WorkspaceName }
    
    if ($workspace) {
        Write-Warning "Found case-insensitive match for workspace '$WorkspaceName': $($workspace.displayName)"
        return $workspace.id
    }
    
    return $null
}

#------------------------------------------------------------------
# Function: Get-FabricWorkspaceItems
#------------------------------------------------------------------
function Get-FabricWorkspaceItems {
    param(
        [string]$WorkspaceId,
        [string]$AccessToken
    )
    
    $headers = @{
        "Authorization" = "Bearer $AccessToken"
        "Content-Type"  = "application/json"
    }
    
    $url = "$fabricApiBase/workspaces/$WorkspaceId/items"
    
    try {
        $response = Invoke-RestMethod -Uri $url -Method Get -Headers $headers
        return $response.value
    } catch {
        Write-Warning "Failed to retrieve workspace items: $_"
        return @()
    }
}

#------------------------------------------------------------------
# Function: Find-ArtifactIdByPattern
#------------------------------------------------------------------
function Find-ArtifactIdByPattern {
    param(
        [string]$VariableName,
        [array]$WorkspaceItems
    )
    
    # Strategy: Match variable names like "LakehouseId", "TransformNotebookId" to artifact names
    # Examples:
    #   LakehouseId → LH_* (any lakehouse)
    #   TransformMedallionLayersNotebookId → NB_Transform_Medallion_Layers
    #   PipelineId → PL_* (any pipeline)
    
    # Extract artifact type hint from variable name
    $artifactType = $null
    $namePattern = $null
    
    if ($VariableName -match '^(?<name>.+?)(?:Notebook)?Id$') {
        $baseName = $matches['name']
        
        # Check for specific artifact type hints
        if ($baseName -match 'Lakehouse') {
            $artifactType = 'Lakehouse'
            $namePattern = 'LH_*'
        }
        elseif ($baseName -match 'Notebook' -or $VariableName -match 'NotebookId$') {
            $artifactType = 'Notebook'
            # Try to extract specific notebook name
            if ($baseName -ne 'Notebook') {
                # Convert PascalCase to snake_case pattern
                $namePattern = "NB_*$baseName*"
            } else {
                $namePattern = 'NB_*'
            }
        }
        elseif ($baseName -match 'Pipeline') {
            $artifactType = 'DataPipeline'
            $namePattern = 'PL_*'
        }
        elseif ($baseName -match 'Environment') {
            $artifactType = 'Environment'
            $namePattern = 'ENV_*'
        }
    }
    
    # If we couldn't determine a pattern, skip this variable
    if (-not $namePattern) {
        return $null
    }
    
    # Filter by artifact type and name pattern
    $matchedItems = $WorkspaceItems | Where-Object {
        ($null -eq $artifactType -or $_.type -eq $artifactType) -and
        ($_.displayName -like $namePattern)
    }
    
    if ($matchedItems.Count -eq 1) {
        return $matchedItems[0].id
    }
    elseif ($matchedItems.Count -gt 1) {
        Write-Warning "Multiple artifacts match variable '$VariableName' (pattern: $namePattern)"
        foreach ($item in $matchedItems) {
            Write-Warning "  - $($item.type): $($item.displayName)"
        }
        return $null
    }
    
    return $null
}

#------------------------------------------------------------------
# Function: Process-VariableLibrary
#------------------------------------------------------------------
function Process-VariableLibrary {
    param(
        [string]$VariableLibraryPath,
        [array]$WorkspaceItems,
        [string]$Environment,
        [string]$BuildVersion,
        [bool]$DryRun
    )
    
    Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    Write-Host "Processing: $VariableLibraryPath"
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    
    $variablesPath = Join-Path $VariableLibraryPath "variables.json"
    
    if (-not (Test-Path $variablesPath)) {
        Write-Warning "variables.json not found in $VariableLibraryPath"
        return
    }
    
    # Clean up any existing valueSets folder - we only use base variables.json with environment-specific values
    $valueSetsPath = Join-Path $VariableLibraryPath "valueSets"
    if (Test-Path $valueSetsPath) {
        Write-Host "`nRemoving valueSets folder (using base variables.json only)..."
        if (-not $DryRun) {
            Remove-Item -Path $valueSetsPath -Recurse -Force
            Write-Host "  ✓ valueSets folder removed" -ForegroundColor Green
        } else {
            Write-Host "  [DRY RUN] Would remove valueSets folder" -ForegroundColor Yellow
        }
    }
    
    # Clean up settings.json - remove valueSetsOrder array
    $settingsPath = Join-Path $VariableLibraryPath "settings.json"
    if (Test-Path $settingsPath) {
        try {
            $settingsContent = Get-Content $settingsPath -Raw | ConvertFrom-Json
            
            # Check if valueSetsOrder exists and has values
            if ($settingsContent.valueSetsOrder -and $settingsContent.valueSetsOrder.Count -gt 0) {
                Write-Host "Clearing valueSetsOrder from settings.json..."
                if (-not $DryRun) {
                    # Clear the valueSetsOrder array
                    $settingsContent.valueSetsOrder = @()
                    
                    # Save updated settings.json
                    $updatedSettings = $settingsContent | ConvertTo-Json -Depth 10
                    Set-Content -Path $settingsPath -Value $updatedSettings -Encoding UTF8
                    Write-Host "  ✓ valueSetsOrder cleared in settings.json" -ForegroundColor Green
                } else {
                    Write-Host "  [DRY RUN] Would clear valueSetsOrder in settings.json" -ForegroundColor Yellow
                }
            }
        } catch {
            Write-Warning "Failed to update settings.json: $_"
        }
    }
    
    # Read variables.json
    $variablesContent = Get-Content $variablesPath -Raw
    $variablesJson = $variablesContent | ConvertFrom-Json
    
    $substitutionsMade = 0
    $substitutionsDetails = @()
    
    # Build a lookup map of *Name variables for efficient matching
    $nameVariables = @{}
    foreach ($variable in $variablesJson.variables) {
        if ($variable.name -match '^(?<base>.+)Name$' -and -not [string]::IsNullOrEmpty($variable.value)) {
            $baseName = $matches['base']
            $nameVariables[$baseName] = $variable.value
        }
    }
    
    # Process each variable
    foreach ($variable in $variablesJson.variables) {
        $varName = $variable.name
        $varValue = $variable.value
        
        # Special handling for DeployedVersionId
        if ($varName -eq "DeployedVersionId" -and $BuildVersion) {
            Write-Host "`nVariable: $varName"
            Write-Host "  Current Value: $(if ($varValue) { $varValue } else { '<empty>' })"
            Write-Host "  ✓ Setting to build version: $BuildVersion" -ForegroundColor Green
            
            if (-not $DryRun) {
                $variable.value = $BuildVersion
                $substitutionsMade++
                $substitutionsDetails += [PSCustomObject]@{
                    Variable = $varName
                    ArtifactName = "Build Version"
                    ArtifactType = "Version"
                    ArtifactId = $BuildVersion
                }
            } else {
                Write-Host "  [DRY RUN] Would update to: $BuildVersion" -ForegroundColor Yellow
            }
            continue
        }
        
        # Only process variables ending in "Id" with empty or missing values
        if ($varName -match '^(?<base>.+)Id$' -and ([string]::IsNullOrEmpty($varValue) -or $varValue -eq "")) {
            $baseName = $matches['base']
            Write-Host "`nVariable: $varName"
            Write-Host "  Current Value: <empty>"
            
            $artifactId = $null
            $artifactName = $null
            $artifact = $null
            
            # Determine expected artifact type from variable name
            $expectedType = $null
            if ($baseName -match 'Lakehouse') {
                $expectedType = 'Lakehouse'
            } elseif ($baseName -match 'Notebook') {
                $expectedType = 'Notebook'
            } elseif ($baseName -match 'Pipeline') {
                $expectedType = 'DataPipeline'
            } elseif ($baseName -match 'Environment') {
                $expectedType = 'Environment'
            } elseif ($baseName -match 'Warehouse') {
                $expectedType = 'Warehouse'
            } elseif ($baseName -match 'Dataflow') {
                $expectedType = 'Dataflow'
            }
            
            # Strategy 1: Check if there's a corresponding *Name variable
            if ($nameVariables.ContainsKey($baseName)) {
                $targetName = $nameVariables[$baseName]
                Write-Host "  Looking for artifact named: $targetName" -ForegroundColor Cyan
                if ($expectedType) {
                    Write-Host "  Expected type: $expectedType" -ForegroundColor Cyan
                }
                
                # Find artifact by exact name match and type (if specified)
                if ($expectedType) {
                    $artifact = $WorkspaceItems | Where-Object { 
                        $_.displayName -eq $targetName -and $_.type -eq $expectedType 
                    }
                } else {
                    $artifact = $WorkspaceItems | Where-Object { $_.displayName -eq $targetName }
                }
                
                if ($artifact) {
                    $artifactId = $artifact.id
                    $artifactName = $artifact.displayName
                    Write-Host "  ✓ Found artifact: $artifactName" -ForegroundColor Green
                    Write-Host "  ✓ Type: $($artifact.type)" -ForegroundColor Green
                } else {
                    if ($expectedType) {
                        Write-Warning "  ✗ Artifact not found: $targetName (type: $expectedType)"
                    } else {
                        Write-Warning "  ✗ Artifact not found: $targetName"
                    }
                }
            }
            
            # Strategy 2: Fall back to pattern matching if no name variable exists
            if (-not $artifactId) {
                Write-Host "  Using pattern matching..." -ForegroundColor Cyan
                $artifactId = Find-ArtifactIdByPattern -VariableName $varName -WorkspaceItems $WorkspaceItems
                
                if ($artifactId) {
                    $artifact = $WorkspaceItems | Where-Object { $_.id -eq $artifactId }
                    $artifactName = if ($artifact) { $artifact.displayName } else { "Unknown" }
                    Write-Host "  ✓ Matched to: $artifactName" -ForegroundColor Green
                }
            }
            
            # Apply substitution if artifact was found
            if ($artifactId) {
                Write-Host "  ✓ Artifact ID: $artifactId" -ForegroundColor Green
                
                if (-not $DryRun) {
                    # Update the value directly
                    $variable.value = $artifactId
                    $substitutionsMade++
                    $substitutionsDetails += [PSCustomObject]@{
                        Variable = $varName
                        ArtifactName = $artifactName
                        ArtifactType = if ($artifact) { $artifact.type } else { "Unknown" }
                        ArtifactId = $artifactId
                    }
                } else {
                    Write-Host "  [DRY RUN] Would update to: $artifactId" -ForegroundColor Yellow
                }
            } else {
                Write-Warning "  ✗ No matching artifact found for: $varName"
            }
        }
    }
    
    # Save updated variables.json
    if ($substitutionsMade -gt 0 -and -not $DryRun) {
        $updatedJson = $variablesJson | ConvertTo-Json -Depth 10
        Set-Content -Path $variablesPath -Value $updatedJson -Encoding UTF8
        Write-Host "`n✓ Updated variables.json with $substitutionsMade substitution(s)" -ForegroundColor Green
        
        # Display summary table
        if ($substitutionsDetails.Count -gt 0) {
            Write-Host "`nSubstitution Summary:" -ForegroundColor Cyan
            $substitutionsDetails | Format-Table -Property Variable, ArtifactName, ArtifactType -AutoSize | Out-String | Write-Host
        }
    } elseif ($DryRun) {
        Write-Host "`n[DRY RUN] Would have made $substitutionsMade substitution(s)" -ForegroundColor Yellow
    } else {
        Write-Host "`nNo substitutions needed" -ForegroundColor Gray
    }
    
    return $substitutionsMade
}

#------------------------------------------------------------------
# Main Script
#------------------------------------------------------------------

Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
Write-Host "  FABRIC VARIABLE LIBRARY SUBSTITUTION"
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
Write-Host ""
Write-Host "Workspace Name: $WorkspaceName"
Write-Host "Environment: $Environment"
Write-Host "Source Path: $SourcePath"
Write-Host "Dry Run: $DryRun"
Write-Host ""

# Authenticate
Write-Host "Authenticating to Fabric API..." -NoNewline
try {
    $accessToken = Get-FabricAccessToken -TenantId $TenantId -ClientId $ClientId -ClientSecret $ClientSecret
    Write-Host " ✓" -ForegroundColor Green
} catch {
    Write-Host " ✗" -ForegroundColor Red
    Write-Error "Authentication failed: $_"
    exit 1
}

# Resolve workspace name to ID
Write-Host "Resolving workspace name to ID..." -NoNewline
$workspaceId = Get-FabricWorkspaceIdByName -WorkspaceName $WorkspaceName -AccessToken $accessToken

if (-not $workspaceId) {
    Write-Host " ✗" -ForegroundColor Red
    Write-Error "Workspace '$WorkspaceName' not found. Please verify the workspace name."
    exit 1
}
Write-Host " ✓" -ForegroundColor Green
Write-Host "  Workspace ID: $workspaceId"

# Get workspace items
Write-Host "Retrieving workspace artifacts..." -NoNewline
$workspaceItems = Get-FabricWorkspaceItems -WorkspaceId $workspaceId -AccessToken $accessToken
Write-Host " ✓ ($($workspaceItems.Count) items)" -ForegroundColor Green

if ($workspaceItems.Count -eq 0) {
    Write-Warning "No items found in workspace. Variable substitution may fail."
}

# Find all variable library folders
$variableLibraries = Get-ChildItem -Path $SourcePath -Filter "*.VariableLibrary" -Directory -Recurse

if ($variableLibraries.Count -eq 0) {
    Write-Warning "No variable library folders (*.VariableLibrary) found in $SourcePath"
    exit 0
}

Write-Host "`nFound $($variableLibraries.Count) variable library folder(s)"

# Process each variable library
$totalSubstitutions = 0
foreach ($varLib in $variableLibraries) {
    $count = Process-VariableLibrary -VariableLibraryPath $varLib.FullName -WorkspaceItems $workspaceItems -Environment $Environment -BuildVersion $BuildVersion -DryRun $DryRun
    $totalSubstitutions += $count
}

# Update Semantic Model Connections
Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
Write-Host "  UPDATING SEMANTIC MODEL CONNECTIONS"
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
Write-Host ""

# Find all semantic model folders
$semanticModels = Get-ChildItem -Path $SourcePath -Filter "*.SemanticModel" -Directory -Recurse

if ($semanticModels.Count -eq 0) {
    Write-Host "No semantic model folders (*.SemanticModel) found in $SourcePath" -ForegroundColor Gray
} else {
    Write-Host "Found $($semanticModels.Count) semantic model folder(s)"
    
    # Get lakehouse artifact for connection update
    $lakehouse = $workspaceItems | Where-Object { $_.type -eq "Lakehouse" }
    
    if ($lakehouse) {
        $lakehouseId = $lakehouse.id
        $lakehouseName = $lakehouse.displayName
        Write-Host "Target Lakehouse: $lakehouseName ($lakehouseId)"
        Write-Host ""
        
        $semanticModelsUpdated = 0
        
        foreach ($smFolder in $semanticModels) {
            Write-Host "Processing: $($smFolder.Name)"
            
            # Check for expressions.tmdl file
            $expressionsPath = Join-Path $smFolder.FullName "definition\expressions.tmdl"
            
            if (Test-Path $expressionsPath) {
                try {
                    $expressionsContent = Get-Content $expressionsPath -Raw
                    
                    # Check if it contains a OneLake connection string
                    if ($expressionsContent -match 'https://onelake\.dfs\.fabric\.microsoft\.com/([a-f0-9-]+)/([a-f0-9-]+)') {
                        $oldWorkspaceId = $matches[1]
                        $oldLakehouseId = $matches[2]
                        
                        Write-Host "  Current connection:"
                        Write-Host "    Workspace ID: $oldWorkspaceId"
                        Write-Host "    Lakehouse ID: $oldLakehouseId"
                        
                        # Update the connection string
                        $updatedContent = $expressionsContent -replace `
                            'https://onelake\.dfs\.fabric\.microsoft\.com/[a-f0-9-]+/[a-f0-9-]+', `
                            "https://onelake.dfs.fabric.microsoft.com/$workspaceId/$lakehouseId"
                        
                        if ($updatedContent -ne $expressionsContent) {
                            Write-Host "  ✓ Updating connection to:"
                            Write-Host "    Workspace ID: $workspaceId"
                            Write-Host "    Lakehouse ID: $lakehouseId ($lakehouseName)"
                            
                            if (-not $DryRun) {
                                Set-Content -Path $expressionsPath -Value $updatedContent -Encoding UTF8 -NoNewline
                                $semanticModelsUpdated++
                                $totalSubstitutions++
                                Write-Host "  ✓ Connection updated" -ForegroundColor Green
                            } else {
                                Write-Host "  [DRY RUN] Would update connection" -ForegroundColor Yellow
                            }
                        } else {
                            Write-Host "  ⊘ Connection already up to date" -ForegroundColor Gray
                        }
                    } else {
                        Write-Host "  ⊘ No OneLake connection found in expressions.tmdl" -ForegroundColor Gray
                    }
                } catch {
                    Write-Warning "  ✗ Failed to process expressions.tmdl: $_"
                }
            } else {
                Write-Host "  ⊘ No expressions.tmdl file found" -ForegroundColor Gray
            }
            Write-Host ""
        }
        
        if ($semanticModelsUpdated -gt 0) {
            Write-Host "✓ Updated $semanticModelsUpdated semantic model connection(s)" -ForegroundColor Green
        } else {
            Write-Host "No semantic model connections needed updating" -ForegroundColor Gray
        }
    } else {
        Write-Warning "No Lakehouse found in workspace - cannot update semantic model connections"
    }
}

Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
Write-Host "  SUBSTITUTION COMPLETE"
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
Write-Host ""
Write-Host "Total substitutions made: $totalSubstitutions" -ForegroundColor $(if ($totalSubstitutions -gt 0) { "Green" } else { "Gray" })
Write-Host "Workspace: $WorkspaceName"
Write-Host "Environment: $Environment"

# Commit and push changes if substitutions were made (and not in dry run mode)
if ($totalSubstitutions -gt 0 -and -not $DryRun) {
    Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    Write-Host "  COMMITTING CHANGES TO GIT"
    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
    Write-Host ""
    
    # Configure Git identity for pipeline commits
    Write-Host "Configuring Git identity..." -NoNewline
    git config user.email "azure-pipelines@fabcon.com"
    git config user.name "Azure Pipelines"
    Write-Host " ✓" -ForegroundColor Green
    
    # Add all modified variable library files and deleted valueSets folders
    Write-Host "Staging variable library changes (variables.json, settings.json, deleted valueSets)..." -NoNewline
    $variableLibraries | ForEach-Object {
        # Stage variables.json
        $variablesFile = Join-Path $_.FullName "variables.json"
        if (Test-Path $variablesFile) {
            git add $variablesFile
        }
        
        # Stage settings.json
        $settingsFile = Join-Path $_.FullName "settings.json"
        if (Test-Path $settingsFile) {
            git add $settingsFile
        }
        
        # Stage deletion of valueSets folder if it was removed
        $valueSetsFolder = Join-Path $_.FullName "valueSets"
        if (-not (Test-Path $valueSetsFolder)) {
            # Check if it exists in Git index (to stage deletion)
            $gitLsFiles = git ls-files $valueSetsFolder 2>$null
            if ($gitLsFiles) {
                git rm -r --cached $valueSetsFolder 2>$null
            }
        }
    }
    Write-Host " ✓" -ForegroundColor Green
    
    # Stage semantic model connection updates
    if ($semanticModels -and $semanticModels.Count -gt 0) {
        Write-Host "Staging semantic model connection updates..." -NoNewline
        $semanticModels | ForEach-Object {
            $expressionsFile = Join-Path $_.FullName "definition\expressions.tmdl"
            if (Test-Path $expressionsFile) {
                git add $expressionsFile
            }
        }
        Write-Host " ✓" -ForegroundColor Green
    }
    
    # Check if there are changes to commit
    $gitStatus = git status --porcelain
    if ($gitStatus) {
        # Commit with descriptive message
        $commitMessage = "Update variable libraries and semantic model connections for $Environment environment"
        Write-Host "Committing changes..." -NoNewline
        git commit -m $commitMessage
        Write-Host " ✓" -ForegroundColor Green
        
        # Push to remote branch
        if ($BranchName) {
            Write-Host "Pushing to branch: $BranchName..." -NoNewline
            git push origin "HEAD:$BranchName"
            Write-Host " ✓" -ForegroundColor Green
        } else {
            Write-Host "Pushing to current branch..." -NoNewline
            git push
            Write-Host " ✓" -ForegroundColor Green
        }
        
        # Get the commit hash
        $commitHash = git rev-parse HEAD
        Write-Host "Commit: $commitHash" -ForegroundColor Cyan
        
        # Sync workspace from Git using UpdateFromGit API
        Write-Host "`n━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        Write-Host "  SYNCING WORKSPACE FROM GIT"
        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        Write-Host ""
        
        # Set up headers for Fabric API
        $headers = @{
            "Authorization" = "Bearer $accessToken"
            "Content-Type" = "application/json"
        }
        
        # Get workspace Git status BEFORE pushing to capture current workspace head
        Write-Host "Getting workspace Git status BEFORE sync..." -NoNewline
        $gitStatusUrl = "$fabricApiBase/workspaces/$workspaceId/git/status"
        try {
            $wsGitStatus = Invoke-RestMethod -Uri $gitStatusUrl -Headers $headers -Method Get -ErrorAction Stop
            $workspaceHead = $wsGitStatus.workspaceHead
            Write-Host " ✓" -ForegroundColor Green
            Write-Host "  Current workspace head: $workspaceHead"
        } catch {
            Write-Warning "Could not get workspace head: $($_.Exception.Message)"
            $workspaceHead = $null
        }
        
        # Wait briefly for remote to be updated after push
        Write-Host "Waiting for remote to be updated..." -NoNewline
        Start-Sleep -Seconds 3
        Write-Host " ✓" -ForegroundColor Green
        
        # Get UPDATED workspace Git status to capture new remote commit hash
        Write-Host "Getting updated Git status to verify remote commit..." -NoNewline
        try {
            $wsGitStatusUpdated = Invoke-RestMethod -Uri $gitStatusUrl -Headers $headers -Method Get -ErrorAction Stop
            $remoteCommitHash = $wsGitStatusUpdated.remoteCommitHash
            Write-Host " ✓" -ForegroundColor Green
            Write-Host "  New remote commit: $remoteCommitHash"
            
            # Verify it matches what we pushed
            if ($remoteCommitHash -ne $commitHash) {
                Write-Warning "Remote commit hash ($remoteCommitHash) doesn't match local commit ($commitHash)"
                Write-Host "  This may indicate a push conflict or delay. Using local commit hash."
                $remoteCommitHash = $commitHash
            }
        } catch {
            Write-Warning "Could not get updated remote commit: $($_.Exception.Message)"
            Write-Host "  Using local commit hash: $commitHash"
            $remoteCommitHash = $commitHash
        }
        
        # Call UpdateFromGit API to sync workspace from Git
        Write-Host "Triggering UpdateFromGit (prefer remote)..." -NoNewline
        $updateFromGitUrl = "$fabricApiBase/workspaces/$workspaceId/git/updateFromGit"
        
        $syncBody = @{
            remoteCommitHash = $remoteCommitHash
            conflictResolution = @{
                conflictResolutionType = "Workspace"
                conflictResolutionPolicy = "PreferRemote"
            }
            options = @{
                allowOverrideItems = $true
            }
        }
        
        # Include workspaceHead if available
        if ($workspaceHead) {
            $syncBody.workspaceHead = $workspaceHead
        }
        
        $syncBodyJson = $syncBody | ConvertTo-Json -Depth 10
        
        try {
            $syncResponse = Invoke-WebRequest -Uri $updateFromGitUrl -Headers $headers -Method Post -Body $syncBodyJson -ContentType "application/json" -ErrorAction Stop
            Write-Host " ✓" -ForegroundColor Green
            
            # Check if it's a long-running operation
            $operationId = $syncResponse.Headers['x-ms-operation-id']
            if ($operationId -is [array]) { $operationId = $operationId[0] }
            
            if ($operationId) {
                Write-Host "UpdateFromGit operation initiated: $operationId"
                
                # Get retry interval
                $retryAfterHeader = $syncResponse.Headers['Retry-After']
                if ($retryAfterHeader -is [array]) { $retryAfterHeader = $retryAfterHeader[0] }
                $retryAfter = if ($retryAfterHeader) { [int]$retryAfterHeader } else { 5 }
                if ($retryAfter -eq 0) { $retryAfter = 5 }
                
                # Poll for completion
                Write-Host "Polling sync operation status..."
                $getOperationUrl = "$fabricApiBase/operations/$operationId"
                $maxAttempts = 30
                $attempt = 0
                
                do {
                    Start-Sleep -Seconds $retryAfter
                    $attempt++
                    $operationState = Invoke-RestMethod -Uri $getOperationUrl -Headers $headers -Method Get
                    Write-Host "  [$attempt/$maxAttempts] Status: $($operationState.Status)"
                } while($operationState.Status -in @("NotStarted", "Running") -and $attempt -lt $maxAttempts)
                
                if ($operationState.Status -eq "Succeeded") {
                    Write-Host "✓ Workspace sync completed successfully" -ForegroundColor Green
                } else {
                    Write-Warning "Sync operation status: $($operationState.Status)"
                    if ($operationState.Error) {
                        Write-Warning "Error: $($operationState.Error | ConvertTo-Json -Depth 3)"
                    }
                }
            } else {
                Write-Host "✓ Workspace sync completed (no operation ID returned)" -ForegroundColor Green
            }
        } catch {
            Write-Host " ✗" -ForegroundColor Red
            Write-Warning "Failed to sync workspace from Git: $($_.Exception.Message)"
            if ($_.ErrorDetails.Message) {
                Write-Warning "API Response: $($_.ErrorDetails.Message)"
            }
            Write-Warning "Variable substitution was committed to Git, but workspace sync failed."
            Write-Warning "You may need to manually sync the workspace or check Git integration status."
        }
        
    } else {
        Write-Host "No changes to commit (files may not have changed)" -ForegroundColor Gray
    }
} elseif ($DryRun -and $totalSubstitutions -gt 0) {
    Write-Host "`n[DRY RUN] Would commit $totalSubstitutions substitution(s) and sync workspace from Git" -ForegroundColor Yellow
}
