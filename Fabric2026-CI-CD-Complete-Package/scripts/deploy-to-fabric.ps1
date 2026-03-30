<#
.SYNOPSIS
    Deploy artifacts to Microsoft Fabric workspace via Git Integration API.

.DESCRIPTION
    This script handles the end-to-end deployment process:
    - Authenticates with service principal
    - Initializes Git integration if not configured
    - Updates workspace Git connection to release branch
    - Triggers Git sync (UpdateFromGit)
    - Polls until deployment completes

.PARAMETER WorkspaceName
    Name of the Fabric workspace to deploy to

.PARAMETER BranchName
    Git branch name to deploy from (e.g., release/dev/20260314.31)

.PARAMETER EnvironmentDisplayName
    Display name for the environment (e.g., "DEV", "QA", "PROD")

.PARAMETER LakehouseName
    Name of the lakehouse in the workspace

.EXAMPLE
    .\deploy-to-fabric.ps1 `
        -WorkspaceName "FDT NYC Taxi - DEV" `
        -BranchName "release/dev/20260314.31" `
        -EnvironmentDisplayName "DEV" `
        -LakehouseName "LH_NYC_Taxi"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$WorkspaceName,
    
    [Parameter(Mandatory=$true)]
    [string]$BranchName,
    
    [Parameter(Mandatory=$true)]
    [string]$EnvironmentDisplayName,
    
    [Parameter(Mandatory=$true)]
    [string]$LakehouseName,
    
    [Parameter(Mandatory=$false)]
    [string]$BuildVersion
)

$ErrorActionPreference = "Stop"

Write-Host "##[section]Deploying to Fabric $EnvironmentDisplayName Workspace"
Write-Host "Workspace Name: $WorkspaceName"
Write-Host "Lakehouse Name: $LakehouseName"
Write-Host "Build Version: $BuildVersion"
Write-Host "Release Branch: $BranchName"
Write-Host ""

# ============================================================================
# Fabric Git Integration API
# Reference: https://learn.microsoft.com/en-us/fabric/cicd/git-integration/git-automation
# ============================================================================

# Step 1: Authenticate with service principal using Azure PowerShell
Write-Host "##[section]Authenticating with Fabric API using service principal..."

$tenantId = $env:AZURE_TENANT_ID
$clientId = $env:AZURE_CLIENT_ID
$clientSecret = $env:AZURE_CLIENT_SECRET

if (-not $tenantId -or -not $clientId -or -not $clientSecret) {
    $errorMessage = @"
Service principal credentials not configured in Fabric-Shared-Auth variable group.
Required variables:
  - AZURE_TENANT_ID
  - AZURE_CLIENT_ID
  - AZURE_CLIENT_SECRET

Create the variable group in Azure DevOps: Pipelines > Library > + Variable group
"@
    throw $errorMessage
}

Write-Host "Connecting to Azure with service principal..."
Write-Host "  Tenant ID: $tenantId"
Write-Host "  Client ID: $clientId"

try {
    # Convert client secret to secure string
    $secureSecret = ConvertTo-SecureString -String $clientSecret -AsPlainText -Force
    $credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $clientId, $secureSecret
    
    # Login to Azure using service principal
    Connect-AzAccount -ServicePrincipal -TenantId $tenantId -Credential $credential -ErrorAction Stop | Out-Null
    Write-Host "✓ Connected to Azure successfully"
    
    # Get Fabric API access token
    Write-Host "Requesting Fabric API access token..."
    $resourceUrl = "https://api.fabric.microsoft.com"
    $secureFabricToken = (Get-AzAccessToken -AsSecureString -ResourceUrl $resourceUrl -ErrorAction Stop).Token
    
    # Convert secure string to plain text for Authorization header
    $ssPtr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureFabricToken)
    try {
        $fabricToken = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($ssPtr)
    } finally {
        [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ssPtr)
    }
    
    Write-Host "✓ Fabric API access token obtained successfully"
    
} catch {
    Write-Error "Failed to authenticate: $($_.Exception.Message)"
    if ($_.ErrorDetails.Message) {
        Write-Error "Details: $($_.ErrorDetails.Message)"
    }
    throw "Authentication failed. Verify service principal credentials and permissions."
}

# Set headers for Fabric API calls
$headers = @{
    "Authorization" = "Bearer $fabricToken"
    "Content-Type" = "application/json"
}

# Step 2: Get workspace ID by name
Write-Host "Resolving workspace ID for: $WorkspaceName"
$workspacesUrl = "https://api.fabric.microsoft.com/v1/workspaces"

try {
    $workspacesResponse = Invoke-RestMethod -Uri $workspacesUrl -Headers $headers -Method Get -ErrorAction Stop
    $workspaces = $workspacesResponse.value
    
    if (-not $workspaces -or $workspaces.Count -eq 0) {
        $errorMsg = @"
No workspaces found. The service principal does not have access to any Fabric workspaces.

To fix this issue:
1. Open Fabric workspace '$WorkspaceName' in browser
2. Click Workspace settings (gear icon) > Manage access
3. Click 'Add people or groups'
4. Search for service principal by Client ID: $($env:AZURE_CLIENT_ID)
5. Assign 'Member' or 'Admin' role
6. Click 'Add'

Repeat for each environment workspace (CI, DEV, QA, PROD).
See documentation: docs/cd-pipeline-setup.md section 4
"@
        throw $errorMsg
    }
    
    Write-Host "✓ Found $($workspaces.Count) accessible workspace(s)"
    
} catch {
    if ($_.Exception.Response.StatusCode -eq 'Unauthorized') {
        $errorMsg = @"
Unauthorized: Service principal cannot access Fabric workspaces.

The service principal authenticated successfully with Azure, but does not have permission to access Fabric resources.

To fix this issue:
1. Open Fabric workspace '$WorkspaceName' in browser
2. Click Workspace settings (gear icon) > Manage access  
3. Click 'Add people or groups'
4. Search for service principal by Client ID: $($env:AZURE_CLIENT_ID)
5. Assign 'Member' or 'Admin' role
6. Click 'Add'

Repeat for each environment workspace (CI, DEV, QA, PROD).

See documentation: docs/cd-pipeline-setup.md section 4 - Grant Fabric Workspace Permissions
"@
        throw $errorMsg
    }
    throw
}

$workspace = $workspaces | Where-Object { $_.displayName -eq $WorkspaceName }

if (-not $workspace) {
    $availableWorkspaces = $workspaces | Select-Object -ExpandProperty displayName
    $errorMsg = @"
Workspace not found: $WorkspaceName

Service principal has access to these workspaces:
$($availableWorkspaces -join "`n  - ")

Please check:
1. Workspace name is correct in variable group: Fabric-Workspace-CI
2. Service principal has been added to workspace '$WorkspaceName'
"@
    throw $errorMsg
}

$workspaceId = $workspace.id
Write-Host "✓ Workspace ID: $workspaceId"
Write-Host ""

# Initialize sync tracking flag
$syncCompleted = $false

# Step 3: Check and initialize Git integration if needed
Write-Host "##[section]Checking Git integration status..."
$gitStatusUrl = "https://api.fabric.microsoft.com/v1/workspaces/$workspaceId/git/status"
$gitConfigured = $false

try {
    $gitStatus = Invoke-RestMethod -Uri $gitStatusUrl -Headers $headers -Method Get -ErrorAction Stop
    $gitConfigured = $true
    
    # Try to get branch name from different possible locations in the response
    $currentBranch = $gitStatus.gitProviderDetails.gitBranchName
    if ([string]::IsNullOrEmpty($currentBranch)) {
        $currentBranch = $gitStatus.gitProviderDetails.branchName
    }
    
    # If branch name is still empty, treat it as disconnected/needs reconnection
    if ([string]::IsNullOrEmpty($currentBranch)) {
        Write-Host "✓ Git integration configured but no active branch"
        Write-Host "  Previous branch was disconnected or deleted"
        Write-Host "  Will connect to branch: $BranchName"
        $currentBranch = ""  # Set to empty string for comparison in Step 5
    } else {
        Write-Host "✓ Git integration already configured"
        Write-Host "  Current branch: $currentBranch"
        
        # Check if we need to switch branches
        if ($currentBranch -ne $BranchName) {
            Write-Host "  Need to switch from '$currentBranch' to '$BranchName'"
        } else {
            Write-Host "  Already on target branch"
        }
    }
} catch {
    $errorMessage = $_.ErrorDetails.Message
    $needsInitializeOnly = $false
    
    # Parse error to determine if workspace is connected but not initialized
    if ($errorMessage) {
        try {
            $errorJson = $errorMessage | ConvertFrom-Json
            if ($errorJson.errorCode -eq "WorkspaceGitConnectionNotInitialized") {
                Write-Host "⚠ Git connection exists but is not initialized"
                Write-Host "  Disconnecting and reconnecting to ensure proper initialization..."
                
                # Disconnect from Git to reset state and allow branch switch
                $disconnectUrl = "https://api.fabric.microsoft.com/v1/workspaces/$workspaceId/git/disconnect"
                try {
                    Invoke-RestMethod -Uri $disconnectUrl -Headers $headers -Method Post -ContentType "application/json" -ErrorAction Stop
                    Write-Host "  ✓ Disconnected successfully"
                    Start-Sleep -Seconds 5
                } catch {
                    Write-Warning "  Failed to disconnect: $($_.Exception.Message)"
                    Write-Host "  Continuing with reconnection attempt..."
                }
                
                # Continue with full connect flow to reconnect to target branch
                $needsInitializeOnly = $false
            }
        } catch {
            # Not JSON, continue with full initialization
        }
    }
    
    if (-not $needsInitializeOnly) {
        Write-Host "⚠ Git integration not configured - initializing with service principal..."
    
    # Get Azure DevOps details from environment variables (set by pipeline)
    $collectionUri = $env:SYSTEM_COLLECTIONURI
    if (-not $collectionUri) {
        throw "SYSTEM_COLLECTIONURI environment variable not set"
    }
    $orgUrl = $collectionUri.TrimEnd('/')
    $orgName = $orgUrl.Split('/')[-1]
    
    $projectName = $env:SYSTEM_TEAMPROJECT
    if (-not $projectName) {
        throw "SYSTEM_TEAMPROJECT environment variable not set"
    }
    
    $repoName = $env:BUILD_REPOSITORY_NAME
    if (-not $repoName) {
        throw "BUILD_REPOSITORY_NAME environment variable not set"
    }
    
    Write-Host "Azure DevOps Details:"
    Write-Host "  Organization: $orgName"
    Write-Host "  Project: $projectName"
    Write-Host "  Repository: $repoName"
    Write-Host ""
    
    # Step 3a: Get or create Git provider credentials connection
    Write-Host "Getting or creating Git provider credentials connection..."
    $connectionsUrl = "https://api.fabric.microsoft.com/v1/connections"
    $connectionName = "AzureDevOps-$orgName-$projectName-SP"
    
    # URL encode project and repo names (spaces become %20)
    $projectNameEncoded = [uri]::EscapeDataString($projectName)
    $repoNameEncoded = [uri]::EscapeDataString($repoName)
    $repoUrl = "$orgUrl/$projectNameEncoded/_git/$repoNameEncoded"
    
    Write-Host "Repository URL: $repoUrl"
    
    try {
        # List existing connections
        $connections = (Invoke-RestMethod -Uri $connectionsUrl -Headers $headers -Method Get).value
        $connection = $connections | Where-Object { 
            $_.displayName -eq $connectionName -and 
            $_.connectivityType -eq "ShareableCloud" -and
            $_.connectionDetails.type -eq "AzureDevOpsSourceControl"
        }
        
        if ($connection) {
            Write-Host "✓ Found existing connection: $connectionName"
            $connectionId = $connection.id
        } else {
            Write-Host "Creating new Git provider credentials connection..."
            
            # Create new connection with service principal credentials
            # Reference: https://learn.microsoft.com/en-us/fabric/cicd/git-integration/git-automation?tabs=service-principal%2CADO#get-or-create-git-provider-credentials-connection
            $createConnectionUrl = "https://api.fabric.microsoft.com/v1/connections"
            $newConnectionBody = @{
                displayName = $connectionName
                connectivityType = "ShareableCloud"
                connectionDetails = @{
                    type = "AzureDevOpsSourceControl"
                    creationMethod = "AzureDevOpsSourceControl.Contents"
                    parameters = @(
                        @{
                            dataType = "Text"
                            name = "url"
                            value = $repoUrl
                        }
                    )
                }
                credentialDetails = @{
                    credentials = @{
                        credentialType = "ServicePrincipal"
                        tenantId = $tenantId
                        servicePrincipalClientId = $clientId
                        servicePrincipalSecret = $clientSecret
                    }
                }
            } | ConvertTo-Json -Depth 10
            
            try {
                Write-Host "Request body:"
                Write-Host $newConnectionBody
                
                $newConnection = Invoke-RestMethod -Uri $createConnectionUrl -Headers $headers -Method Post -Body $newConnectionBody -ContentType "application/json"
                $connectionId = $newConnection.id
                Write-Host "✓ Created new connection: $connectionName (ID: $connectionId)"
            } catch {
                # Log detailed error information
                Write-Warning "Connection creation failed: $($_.Exception.Message)"
                if ($_.ErrorDetails.Message) {
                    Write-Warning "API Response: $($_.ErrorDetails.Message)"
                }
                
                # If creation fails, connection might already exist (race condition)
                # Retry fetching the list to find it
                Write-Warning "Checking if connection already exists..."
                Start-Sleep -Seconds 2
                
                $connections = (Invoke-RestMethod -Uri $connectionsUrl -Headers $headers -Method Get).value
                $connection = $connections | Where-Object { 
                    $_.displayName -eq $connectionName -and 
                    $_.connectivityType -eq "ShareableCloud" -and
                    $_.connectionDetails.type -eq "AzureDevOpsSourceControl"
                }
                
                if ($connection) {
                    Write-Host "✓ Found existing connection after retry: $connectionName"
                    $connectionId = $connection.id
                } else {
                    # Connection doesn't exist and creation failed - this is a real error
                    throw
                }
            }
        }
    } catch {
        Write-Error "Failed to get/create Git provider credentials connection: $($_.Exception.Message)"
        if ($_.ErrorDetails.Message) {
            Write-Error "Response: $($_.ErrorDetails.Message)"
        }
        throw "Could not create Git provider credentials connection"
    }
    
    # Step 3b: Connect workspace to Git using ConfiguredConnection
    Write-Host "Connecting workspace to Git repository..."
    Write-Host "  Using connection ID: $connectionId"
    $connectUrl = "https://api.fabric.microsoft.com/v1/workspaces/$workspaceId/git/connect"
    
    $connectBody = @{
        gitProviderDetails = @{
            gitProviderType = "AzureDevOps"
            organizationName = $orgName
            projectName = $projectName
            repositoryName = $repoName
            branchName = $BranchName
            directoryName = "/"
        }
        myGitCredentials = @{
            source = "ConfiguredConnection"
            connectionId = $connectionId
        }
    } | ConvertTo-Json -Depth 10
    
    Write-Host "Connect request body:"
    Write-Host $connectBody
    
    try {
        $connectResponse = Invoke-WebRequest -Uri $connectUrl -Headers $headers -Method Post -Body $connectBody -ContentType "application/json" -ErrorAction Stop
        Write-Host "✓ Git integration connected successfully"
        
        # Check if connect operation is asynchronous
        $operationId = $connectResponse.Headers['x-ms-operation-id']
        if ($operationId) {
            if ($operationId -is [array]) { $operationId = $operationId[0] }
            Write-Host "  Waiting for connect operation to complete: $operationId"
            
            $retryAfterHeader = $connectResponse.Headers['Retry-After']
            if ($retryAfterHeader -is [array]) { $retryAfterHeader = $retryAfterHeader[0] }
            $retryAfter = if ($retryAfterHeader) { [int]$retryAfterHeader } else { 5 }
            if ($retryAfter -eq 0) { $retryAfter = 5 }
            
            $getOperationUrl = "https://api.fabric.microsoft.com/v1/operations/$operationId"
            
            do {
                Start-Sleep -Seconds $retryAfter
                $operationState = Invoke-RestMethod -Uri $getOperationUrl -Headers $headers -Method Get
                Write-Host "  Connect Status: $($operationState.Status)"
            } while($operationState.Status -in @("NotStarted", "Running"))
            
            if ($operationState.Status -eq "Succeeded") {
                Write-Host "  ✓ Connect operation completed"
            } else {
                throw "Connect operation failed with status: $($operationState.Status)"
            }
        } else {
            # No operation ID, wait and verify connection is ready
            Write-Host "  Waiting for connection to stabilize..."
            Start-Sleep -Seconds 10
            
            # Verify connection status before proceeding
            Write-Host "  Verifying connection status..."
            $maxRetries = 6
            $retryCount = 0
            $connectionReady = $false
            
            while ($retryCount -lt $maxRetries -and -not $connectionReady) {
                try {
                    $verifyStatus = Invoke-RestMethod -Uri $gitStatusUrl -Headers $headers -Method Get -ErrorAction Stop
                    if ($verifyStatus.gitProviderDetails.gitBranchName -eq $BranchName) {
                        $connectionReady = $true
                        Write-Host "  ✓ Connection verified and ready"
                    } else {
                        Write-Host "  Connection not ready yet, retrying... ($($retryCount + 1)/$maxRetries)"
                        Start-Sleep -Seconds 5
                        $retryCount++
                    }
                } catch {
                    $retryCount++
                    if ($retryCount -lt $maxRetries) {
                        Write-Host "  Connection status check failed, retrying... ($retryCount/$maxRetries)"
                        Start-Sleep -Seconds 5
                    }
                }
            }
            
            if (-not $connectionReady) {
                Write-Warning "Connection may not be fully ready, but proceeding with initialization..."
            }
        }
        
    } catch {
        # Check if error is 409 Conflict (workspace already connected)
        if ($_.Exception.Message -like "*409*" -or $_.Exception.Message -like "*Conflict*") {
            Write-Host "⊘ Workspace is already connected to Git (409 Conflict)"
            Write-Host "  Proceeding to initialize existing connection..."
            # Continue to initialization step below
        } else {
            Write-Error "Failed to connect Git integration: $($_.Exception.Message)"
            if ($_.ErrorDetails.Message) {
                Write-Error "API Response: $($_.ErrorDetails.Message)"
            }
            
            # Provide troubleshooting guidance for common errors
            if ($_.Exception.Message -like "*403*" -or $_.Exception.Message -like "*Forbidden*") {
                Write-Host ""
                Write-Host "##[warning]403 Forbidden - Possible causes:"
                Write-Host "1. Service principal needs Admin (not just Member) role on workspace '$WorkspaceName'"
                Write-Host "2. Service principal may not have 'Workspace.GitUpdate.All' API permission"
                Write-Host "3. Another user/principal may have already configured Git integration"
                Write-Host ""
                Write-Host "To fix:"
                Write-Host "- Go to workspace settings and add service principal as Admin"
                Write-Host "- OR manually configure Git integration in the workspace first"
            }
            
            throw "Could not connect Git integration for workspace: $WorkspaceName"
        }
    }
    
    # After connecting, initialize the connection
    Write-Host "Initializing Git connection..."
    $initializeConnectionUrl = "https://api.fabric.microsoft.com/v1/workspaces/$workspaceId/git/initializeConnection"
    
    # Specify initialization strategy for deployment: PreferRemote (use Git as source of truth)
    # Valid values: None, PreferRemote, PreferWorkspace
    $initializeBody = @{
        initializationStrategy = "PreferRemote"
    } | ConvertTo-Json
    
    try {
        Write-Host "  Calling initializeConnection API with PreferRemote strategy..."
        $initializeResponse = Invoke-RestMethod -Uri $initializeConnectionUrl -Headers $headers -Method Post -Body $initializeBody -ContentType "application/json" -ErrorAction Stop
        Write-Host "  ✓ Initialize call succeeded"
        
        # Check if sync is required
        if ($initializeResponse.RequiredAction -eq "UpdateFromGit") {
            Write-Host "Performing initial sync from Git..."
            $updateFromGitUrl = "https://api.fabric.microsoft.com/v1/workspaces/$workspaceId/git/updateFromGit"
            
            # For deployment, allow overriding items and prefer remote (Git) content
            $initialSyncBody = @{
                remoteCommitHash = $initializeResponse.RemoteCommitHash
                workspaceHead = $initializeResponse.WorkspaceHead
                conflictResolution = @{
                    conflictResolutionType = "Workspace"
                    conflictResolutionPolicy = "PreferRemote"
                }
                options = @{
                    allowOverrideItems = $true
                }
            } | ConvertTo-Json -Depth 10
            
            $updateResponse = Invoke-WebRequest -Uri $updateFromGitUrl -Headers $headers -Method Post -Body $initialSyncBody -ContentType "application/json"
            
            # Poll for completion
            $operationId = $updateResponse.Headers['x-ms-operation-id']
            if ($operationId -is [array]) { $operationId = $operationId[0] }
            
            $retryAfterHeader = $updateResponse.Headers['Retry-After']
            if ($retryAfterHeader -is [array]) { $retryAfterHeader = $retryAfterHeader[0] }
            $retryAfter = if ($retryAfterHeader) { [int]$retryAfterHeader } else { 5 }
            if ($retryAfter -eq 0) { $retryAfter = 5 }
            
            Write-Host "  Polling sync operation: $operationId"
            $getOperationUrl = "https://api.fabric.microsoft.com/v1/operations/$operationId"
            
            do {
                Start-Sleep -Seconds $retryAfter
                $operationState = Invoke-RestMethod -Uri $getOperationUrl -Headers $headers -Method Get
                Write-Host "    Status: $($operationState.Status)"
            } while($operationState.Status -in @("NotStarted", "Running"))
            
            if ($operationState.Status -eq "Succeeded") {
                Write-Host "  ✓ Initial sync completed successfully"
                $gitConfigured = $true
                $syncCompleted = $true  # Mark sync as complete to skip later sync
            } else {
                throw "Initial sync failed with status: $($operationState.Status)"
            }
        } else {
            Write-Host "✓ No sync required (RequiredAction: $($initializeResponse.RequiredAction))"
            $gitConfigured = $true
            $syncCompleted = $true  # Mark sync as complete to skip later sync
        }
        
    } catch {
        Write-Host "##[error]Failed to initialize connection: $($_.Exception.Message)"
        if ($_.ErrorDetails.Message) {
            Write-Host "##[error]API Response: $($_.ErrorDetails.Message)"
            
            # Try to parse error details
            try {
                $errorDetails = $_.ErrorDetails.Message | ConvertFrom-Json
                if ($errorDetails.errorCode) {
                    Write-Host "##[error]Error Code: $($errorDetails.errorCode)"
                }
                if ($errorDetails.message) {
                    Write-Host "##[error]Error Message: $($errorDetails.message)"
                }
            } catch {
                # Error details not JSON
            }
        }
        
        # Check connection status for diagnostics
        try {
            Write-Host "Checking connection status for diagnostics..."
            $diagStatus = Invoke-RestMethod -Uri $gitStatusUrl -Headers $headers -Method Get -ErrorAction SilentlyContinue
            Write-Host "Current branch: $($diagStatus.gitProviderDetails.gitBranchName)"
            Write-Host "Connection state: $($diagStatus | ConvertTo-Json -Depth 3)"
        } catch {
            Write-Host "Could not retrieve connection status for diagnostics"
        }
        
        throw "Could not initialize Git connection for workspace: $WorkspaceName (HTTP 400 - Bad Request)`nThis may indicate the workspace is not fully ready after connection. Retry the deployment or check workspace Git settings."
    }
    } # End of if (-not $needsInitializeOnly)
}


if (-not $gitConfigured) {
    throw "Git integration could not be configured for workspace: $WorkspaceName"
}
Write-Host ""

# Step 4: Verify target branch exists
Write-Host "Verifying branch exists: $BranchName"
git fetch origin $BranchName
$branchExists = git rev-parse --verify "origin/$BranchName" 2>$null

if (-not $branchExists) {
    Write-Error "Branch not found: $BranchName"
    throw "Release branch must be created before deployment. Expected branch: $BranchName"
}
Write-Host "✓ Branch verified: $BranchName"
Write-Host ""

# Step 5: Switch to target branch if needed (skip if just connected in Step 3)
if ($syncCompleted) {
    Write-Host "Already connected and synced to target branch - skipping branch switch"
} else {
    $gitStatusUrl = "https://api.fabric.microsoft.com/v1/workspaces/$workspaceId/git/status"
    $gitStatus = Invoke-RestMethod -Uri $gitStatusUrl -Headers $headers -Method Get
    $currentBranch = $gitStatus.gitProviderDetails.gitBranchName

if ($currentBranch -ne $BranchName) {
    if ([string]::IsNullOrEmpty($currentBranch)) {
        Write-Host "Connecting to branch '$BranchName' (no previous branch active)..."
    } else {
        Write-Host "Switching from branch '$currentBranch' to '$BranchName'..."
    }
    
    # Disconnect from current Git connection
    Write-Host "  Disconnecting from Git..."
    $disconnectUrl = "https://api.fabric.microsoft.com/v1/workspaces/$workspaceId/git/disconnect"
    try {
        Invoke-RestMethod -Uri $disconnectUrl -Headers $headers -Method Post -ContentType "application/json"
        Write-Host "  ✓ Disconnected"
        Start-Sleep -Seconds 3
    } catch {
        Write-Warning "Failed to disconnect: $($_.Exception.Message)"
    }
    
    # Reconnect to new branch
    Write-Host "  Reconnecting to branch '$BranchName'..."
    
    # Get Azure DevOps details
    $collectionUri = $env:SYSTEM_COLLECTIONURI
    $orgUrl = $collectionUri.TrimEnd('/')
    $orgName = $orgUrl.Split('/')[-1]
    $projectName = $env:SYSTEM_TEAMPROJECT
    $repoName = $env:BUILD_REPOSITORY_NAME
    
    # Get existing connection
    $connectionsUrl = "https://api.fabric.microsoft.com/v1/connections"
    $connectionName = "AzureDevOps-$orgName-$projectName-SP"
    $connections = (Invoke-RestMethod -Uri $connectionsUrl -Headers $headers -Method Get).value
    $connection = $connections | Where-Object { 
        $_.displayName -eq $connectionName -and 
        $_.connectivityType -eq "ShareableCloud" -and
        $_.connectionDetails.type -eq "AzureDevOpsSourceControl"
    }
    
    if (-not $connection) {
        throw "Git provider credentials connection not found: $connectionName"
    }
    
    $connectionId = $connection.id
    
    # Reconnect with new branch
    $connectUrl = "https://api.fabric.microsoft.com/v1/workspaces/$workspaceId/git/connect"
    $connectBody = @{
        gitProviderDetails = @{
            gitProviderType = "AzureDevOps"
            organizationName = $orgName
            projectName = $projectName
            repositoryName = $repoName
            branchName = $BranchName
            directoryName = "/"
        }
        myGitCredentials = @{
            source = "ConfiguredConnection"
            connectionId = $connectionId
        }
    } | ConvertTo-Json -Depth 10
    
    Invoke-RestMethod -Uri $connectUrl -Headers $headers -Method Post -Body $connectBody -ContentType "application/json"
    Write-Host "  ✓ Reconnected to branch '$BranchName'"
    
    # Wait for connection to establish
    Start-Sleep -Seconds 5
    
    # Initialize the connection after reconnecting
    Write-Host "  Initializing connection..."
    $initializeConnectionUrl = "https://api.fabric.microsoft.com/v1/workspaces/$workspaceId/git/initializeConnection"
    $initializeBody = @{
        initializationStrategy = "PreferRemote"
    } | ConvertTo-Json
    
    try {
        $initResponse = Invoke-RestMethod -Uri $initializeConnectionUrl -Headers $headers -Method Post -Body $initializeBody -ContentType "application/json" -ErrorAction Stop
        
        # Check if sync is required (it should be after branch switch)
        if ($initResponse.RequiredAction -eq "UpdateFromGit") {
            Write-Host "  Performing sync from new branch..."
            $updateFromGitUrl = "https://api.fabric.microsoft.com/v1/workspaces/$workspaceId/git/updateFromGit"
            
            $syncBody = @{
                remoteCommitHash = $initResponse.RemoteCommitHash
                workspaceHead = $initResponse.WorkspaceHead
                conflictResolution = @{
                    conflictResolutionType = "Workspace"
                    conflictResolutionPolicy = "PreferRemote"
                }
                options = @{
                    allowOverrideItems = $true
                }
            } | ConvertTo-Json -Depth 10
            
            $syncResponse = Invoke-WebRequest -Uri $updateFromGitUrl -Headers $headers -Method Post -Body $syncBody -ContentType "application/json"
            
            # Poll for completion
            $operationId = $syncResponse.Headers['x-ms-operation-id']
            if ($operationId -is [array]) { $operationId = $operationId[0] }
            
            $retryAfterHeader = $syncResponse.Headers['Retry-After']
            if ($retryAfterHeader -is [array]) { $retryAfterHeader = $retryAfterHeader[0] }
            $retryAfter = if ($retryAfterHeader) { [int]$retryAfterHeader } else { 5 }
            if ($retryAfter -eq 0) { $retryAfter = 5 }
            
            $getOperationUrl = "https://api.fabric.microsoft.com/v1/operations/$operationId"
            
            do {
                Start-Sleep -Seconds $retryAfter
                $operationState = Invoke-RestMethod -Uri $getOperationUrl -Headers $headers -Method Get
                Write-Host "    Sync status: $($operationState.Status)"
            } while($operationState.Status -in @("NotStarted", "Running"))
            
            if ($operationState.Status -eq "Succeeded") {
                Write-Host "  ✓ Branch switch sync completed"
                $syncCompleted = $true  # Mark sync as complete to skip later sync
            } else {
                throw "Branch switch sync failed with status: $($operationState.Status)"
            }
        } else {
            Write-Host "  ✓ No sync required"
            $syncCompleted = $true  # Mark sync as complete to skip later sync
        }
        
        Write-Host "  ✓ Initialization completed"
    } catch {
        Write-Error "Failed to initialize after branch switch: $($_.Exception.Message)"
        if ($_.ErrorDetails.Message) {
            Write-Error "API Response: $($_.ErrorDetails.Message)"
        }
        throw "Could not initialize connection after switching to branch: $BranchName"
    }
    
    if ([string]::IsNullOrEmpty($currentBranch)) {
        Write-Host "✓ Connected to branch: $BranchName"
    } else {
        Write-Host "✓ Switched to branch: $BranchName"
    }
} else {
    Write-Host "Already on target branch: $BranchName"
    $syncCompleted = $false  # Need to perform sync since we didn't switch
}
} # End of Step 5 branch switching check
Write-Host ""

# Skip sync steps if already completed during branch switch or initial connection
if ($syncCompleted) {
    Write-Host "Sync already completed - skipping redundant sync operations"
    Write-Host ""
    
    # Publish Environment artifact before completing
    Write-Host "##[section]Publishing Environment..."
    Write-Host "Looking for Environment artifact in workspace..."

    # Get workspace items to find Environment artifact
    $workspaceItemsUrl = "https://api.fabric.microsoft.com/v1/workspaces/$workspaceId/items"
    $workspaceItems = (Invoke-RestMethod -Uri $workspaceItemsUrl -Headers $headers -Method Get).value

    # Find Environment artifact (e.g., ENV_NYC_Taxi)
    $environmentItem = $workspaceItems | Where-Object { $_.type -eq "Environment" }

    if ($environmentItem) {
        Write-Host "✓ Found Environment: $($environmentItem.displayName)"
        $environmentId = $environmentItem.id
        
        # Publish the Environment
        Write-Host "Publishing Environment to published state..."
        $publishUrl = "https://api.fabric.microsoft.com/v1/workspaces/$workspaceId/environments/$environmentId/staging/publish"
        
        try {
            # Call publish API with empty body
            $publishResponse = Invoke-WebRequest -Uri $publishUrl -Headers $headers -Method Post -Body "{}" -ContentType "application/json" -ErrorAction Stop
            
            # Check if it's a long-running operation
            $operationId = $publishResponse.Headers['x-ms-operation-id']
            if ($operationId -is [array]) { $operationId = $operationId[0] }
            
            if ($operationId) {
                Write-Host "  Environment publish initiated (Operation ID: $operationId)"
                
                # Poll for completion
                $retryAfterHeader = $publishResponse.Headers['Retry-After']
                if ($retryAfterHeader -is [array]) { $retryAfterHeader = $retryAfterHeader[0] }
                $retryAfter = if ($retryAfterHeader) { [int]$retryAfterHeader } else { 5 }
                if ($retryAfter -eq 0) { $retryAfter = 5 }
                
                $getOperationUrl = "https://api.fabric.microsoft.com/v1/operations/$operationId"
                $publishMaxAttempts = 60
                $publishAttempt = 0
                
                do {
                    Start-Sleep -Seconds $retryAfter
                    $publishAttempt++
                    $operationState = Invoke-RestMethod -Uri $getOperationUrl -Headers $headers -Method Get
                    Write-Host "  [$publishAttempt/$publishMaxAttempts] Publish status: $($operationState.Status)"
                } while($operationState.Status -in @("NotStarted", "Running") -and $publishAttempt -lt $publishMaxAttempts)
                
                if ($operationState.Status -eq "Succeeded") {
                    Write-Host "✓ Environment published successfully" -ForegroundColor Green
                } elseif ($publishAttempt -ge $publishMaxAttempts) {
                    Write-Warning "Environment publish operation timed out after $publishMaxAttempts attempts"
                    Write-Warning "Last status: $($operationState.Status)"
                    Write-Warning "Environment may still be publishing - check workspace manually"
                } else {
                    Write-Warning "Environment publish failed with status: $($operationState.Status)"
                    if ($operationState.error) {
                        Write-Warning "Error details: $($operationState.error | ConvertTo-Json -Depth 3)"
                    }
                }
            } else {
                Write-Host "✓ Environment published successfully (synchronous)" -ForegroundColor Green
            }
        } catch {
            Write-Host "##[error]Failed to publish Environment"
            Write-Host "##[error]Exception: $($_.Exception.Message)"
            if ($_.ErrorDetails.Message) {
                Write-Host "##[error]API Response: $($_.ErrorDetails.Message)"
                
                # Try to parse error details
                try {
                    $errorDetails = $_.ErrorDetails.Message | ConvertFrom-Json
                    if ($errorDetails.errorCode) {
                        Write-Host "##[error]Error Code: $($errorDetails.errorCode)"
                    }
                    if ($errorDetails.message) {
                        Write-Host "##[error]Error Message: $($errorDetails.message)"
                    }
                } catch {
                    # Error details not JSON
                }
            }
            Write-Warning "Continuing despite publish failure - Environment may need manual publish"
        }
    } else {
        Write-Host "⊘ No Environment artifact found in workspace - skipping publish"
    }
    Write-Host ""
    
    Write-Host "##[section]Deployment Complete"
    Write-Host "✓ Workspace '$WorkspaceName' successfully deployed from branch '$BranchName'"
    exit 0
}

# Step 6: Get latest commit hash from target branch
Write-Host "Getting latest commit from branch: $BranchName"
$commitHash = git rev-parse "origin/$BranchName"
if (-not $commitHash) {
    Write-Error "Failed to get commit hash from branch: $BranchName"
    Write-Host "Attempting to fetch branch from remote..."
    git fetch origin $BranchName
    $commitHash = git rev-parse "origin/$BranchName"
}

if (-not $commitHash) {
    throw "Cannot find branch: $BranchName. Ensure the release branch was created before deployment."
}

Write-Host "✓ Latest commit: $commitHash"
Write-Host ""

# Step 6: Get current workspace head for sync
Write-Host "Getting current workspace Git status..."
$gitStatusUrl = "https://api.fabric.microsoft.com/v1/workspaces/$workspaceId/git/status"
try {
    $gitStatus = Invoke-RestMethod -Uri $gitStatusUrl -Headers $headers -Method Get
    $workspaceHead = $gitStatus.workspaceHead
    Write-Host "✓ Workspace head: $workspaceHead"
} catch {
    Write-Warning "Could not get workspace head: $($_.Exception.Message)"
    $workspaceHead = $null
}
Write-Host ""

# Step 7: Trigger Git sync from repository to workspace (Update From Git)
Write-Host "Syncing workspace from Git (Update From Git)..."
$updateFromGitUrl = "https://api.fabric.microsoft.com/v1/workspaces/$workspaceId/git/updateFromGit"
$syncBody = @{
    remoteCommitHash = $commitHash
    conflictResolution = @{
        conflictResolutionType = "Workspace"
        conflictResolutionPolicy = "PreferRemote"
    }
    options = @{
        allowOverrideItems = $true
    }
    workspaceHead = $workspaceHead
} | ConvertTo-Json -Depth 10

$syncResponse = Invoke-RestMethod -Uri $updateFromGitUrl -Headers $headers -Method Post -Body $syncBody -ContentType "application/json"
Write-Host "✓ Git sync initiated"
Write-Host ""

# Step 8: Poll sync status until complete
Write-Host "Waiting for deployment to complete..."
$maxAttempts = 60
$attempt = 0
$completed = $false

while ($attempt -lt $maxAttempts -and -not $completed) {
    Start-Sleep -Seconds 5
    $attempt++
    
    # Check workspace Git status
    $statusUrl = "https://api.fabric.microsoft.com/v1/workspaces/$workspaceId/git/status"
    $status = Invoke-RestMethod -Uri $statusUrl -Headers $headers -Method Get
    
    if ($status.workspaceHead -and $status.changes.Count -eq 0) {
        $completed = $true
        Write-Host "✓ Deployment completed successfully"
        Write-Host "  Commit: $($status.workspaceHead)"
    } else {
        Write-Host "  [$attempt/$maxAttempts] Deployment in progress..."
    }
}

if (-not $completed) {
    Write-Warning "Deployment did not complete within expected time. Check workspace manually."
}

Write-Host ""
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
Write-Host "✓ Git sync to $EnvironmentDisplayName completed"
Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
Write-Host ""

# Step 9: Publish Environment artifact
Write-Host "##[section]Publishing Environment..."
Write-Host "Looking for Environment artifact in workspace..."

# Get workspace items to find Environment artifact
$workspaceItemsUrl = "https://api.fabric.microsoft.com/v1/workspaces/$workspaceId/items"
$workspaceItems = (Invoke-RestMethod -Uri $workspaceItemsUrl -Headers $headers -Method Get).value

# Find Environment artifact (e.g., ENV_NYC_Taxi)
$environmentItem = $workspaceItems | Where-Object { $_.type -eq "Environment" }

if ($environmentItem) {
    Write-Host "✓ Found Environment: $($environmentItem.displayName)"
    $environmentId = $environmentItem.id
    
    # Publish the Environment
    Write-Host "Publishing Environment to published state..."
    $publishUrl = "https://api.fabric.microsoft.com/v1/workspaces/$workspaceId/environments/$environmentId/staging/publish"
    
    try {
        # Call publish API with empty body
        $publishResponse = Invoke-WebRequest -Uri $publishUrl -Headers $headers -Method Post -Body "{}" -ContentType "application/json" -ErrorAction Stop
        
        # Check if it's a long-running operation
        $operationId = $publishResponse.Headers['x-ms-operation-id']
        if ($operationId -is [array]) { $operationId = $operationId[0] }
        
        if ($operationId) {
            Write-Host "  Environment publish initiated (Operation ID: $operationId)"
            
            # Poll for completion
            $retryAfterHeader = $publishResponse.Headers['Retry-After']
            if ($retryAfterHeader -is [array]) { $retryAfterHeader = $retryAfterHeader[0] }
            $retryAfter = if ($retryAfterHeader) { [int]$retryAfterHeader } else { 5 }
            if ($retryAfter -eq 0) { $retryAfter = 5 }
            
            $getOperationUrl = "https://api.fabric.microsoft.com/v1/operations/$operationId"
            $publishMaxAttempts = 60
            $publishAttempt = 0
            
            do {
                Start-Sleep -Seconds $retryAfter
                $publishAttempt++
                $operationState = Invoke-RestMethod -Uri $getOperationUrl -Headers $headers -Method Get
                Write-Host "  [$publishAttempt/$publishMaxAttempts] Publish status: $($operationState.Status)"
            } while($operationState.Status -in @("NotStarted", "Running") -and $publishAttempt -lt $publishMaxAttempts)
            
            if ($operationState.Status -eq "Succeeded") {
                Write-Host "✓ Environment published successfully" -ForegroundColor Green
            } elseif ($publishAttempt -ge $publishMaxAttempts) {
                Write-Warning "Environment publish operation timed out after $publishMaxAttempts attempts"
                Write-Warning "Last status: $($operationState.Status)"
                Write-Warning "Environment may still be publishing - check workspace manually"
            } else {
                Write-Warning "Environment publish failed with status: $($operationState.Status)"
                if ($operationState.error) {
                    Write-Warning "Error details: $($operationState.error | ConvertTo-Json -Depth 3)"
                }
            }
        } else {
            Write-Host "✓ Environment published successfully (synchronous)" -ForegroundColor Green
        }
    } catch {
        Write-Host "##[error]Failed to publish Environment"
        Write-Host "##[error]Exception: $($_.Exception.Message)"
        if ($_.ErrorDetails.Message) {
            Write-Host "##[error]API Response: $($_.ErrorDetails.Message)"
            
            # Try to parse error details
            try {
                $errorDetails = $_.ErrorDetails.Message | ConvertFrom-Json
                if ($errorDetails.errorCode) {
                    Write-Host "##[error]Error Code: $($errorDetails.errorCode)"
                }
                if ($errorDetails.message) {
                    Write-Host "##[error]Error Message: $($errorDetails.message)"
                }
            } catch {
                # Error details not JSON
            }
        }
        Write-Warning "Continuing despite publish failure - Environment may need manual publish"
    }
} else {
    Write-Host "⊘ No Environment artifact found in workspace - skipping publish"
}
Write-Host ""
