<#
.SYNOPSIS
    Sync Fabric workspace to pull updated variable libraries from Git.

.DESCRIPTION
    Triggers UpdateFromGit API call to sync workspace with Git repository
    after variable library updates have been committed. Polls until sync completes.

.PARAMETER WorkspaceName
    Name of the Fabric workspace to sync

.EXAMPLE
    .\sync-workspace-from-git.ps1 -WorkspaceName "FDT NYC Taxi - DEV"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory=$true)]
    [string]$WorkspaceName
)

$ErrorActionPreference = "Stop"

Write-Host "##[section]Syncing workspace to pull updated variable libraries"

# Get Fabric access token using service principal
$tenantId = $env:AZURE_TENANT_ID
$clientId = $env:AZURE_CLIENT_ID
$clientSecret = $env:AZURE_CLIENT_SECRET

if (-not $tenantId -or -not $clientId -or -not $clientSecret) {
    throw "Service principal credentials not found in environment variables"
}

# Authenticate with Azure PowerShell
$secureSecret = ConvertTo-SecureString -String $clientSecret -AsPlainText -Force
$credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $clientId, $secureSecret

Connect-AzAccount -ServicePrincipal -TenantId $tenantId -Credential $credential -ErrorAction Stop | Out-Null

# Get Fabric API access token
$resourceUrl = "https://api.fabric.microsoft.com"
$secureFabricToken = (Get-AzAccessToken -AsSecureString -ResourceUrl $resourceUrl -ErrorAction Stop).Token

# Convert secure string to plain text
$ssPtr = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureFabricToken)
try {
    $token = [System.Runtime.InteropServices.Marshal]::PtrToStringBSTR($ssPtr)
} finally {
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($ssPtr)
}

$headers = @{
    "Authorization" = "Bearer $token"
    "Content-Type" = "application/json"
}

# Get workspace ID
Write-Host "Resolving workspace ID for: $WorkspaceName"
$workspacesUrl = "https://api.fabric.microsoft.com/v1/workspaces"
$workspaces = (Invoke-RestMethod -Uri $workspacesUrl -Headers $headers -Method Get).value
$workspace = $workspaces | Where-Object { $_.displayName -eq $WorkspaceName }

if (-not $workspace) {
    throw "Workspace not found: $WorkspaceName"
}

$workspaceId = $workspace.id
Write-Host "✓ Workspace ID: $workspaceId"

# Get current Git status to retrieve remote commit hash
Write-Host "Getting current Git status..."
$statusUrl = "https://api.fabric.microsoft.com/v1/workspaces/$workspaceId/git/status"
$gitStatus = Invoke-RestMethod -Uri $statusUrl -Headers $headers -Method Get

$remoteCommitHash = $gitStatus.remoteCommitHash
$workspaceHead = $gitStatus.workspaceHead

if (-not $remoteCommitHash) {
    throw "Could not get remote commit hash from Git status. Workspace may not be connected to Git."
}

Write-Host "  Remote commit: $remoteCommitHash"
Write-Host "  Workspace head: $workspaceHead"

# Trigger Git sync
Write-Host "Triggering UpdateFromGit to sync variable libraries..."
$updateFromGitUrl = "https://api.fabric.microsoft.com/v1/workspaces/$workspaceId/git/updateFromGit"
$syncBody = @{
    remoteCommitHash = $remoteCommitHash
    conflictResolution = @{
        conflictResolutionType = "Workspace"
        conflictResolutionPolicy = "PreferRemote"
    }
    options = @{
        allowOverrideItems = $true
    }
    workspaceHead = $workspaceHead
} | ConvertTo-Json -Depth 10

Invoke-RestMethod -Uri $updateFromGitUrl -Headers $headers -Method Post -Body $syncBody | Out-Null
Write-Host "✓ Sync initiated"

# Poll for completion
Write-Host "Waiting for sync to complete..."
$maxAttempts = 30
$attempt = 0
$completed = $false

while ($attempt -lt $maxAttempts -and -not $completed) {
    Start-Sleep -Seconds 5
    $attempt++
    
    $statusUrl = "https://api.fabric.microsoft.com/v1/workspaces/$workspaceId/git/status"
    $status = Invoke-RestMethod -Uri $statusUrl -Headers $headers -Method Get
    
    if ($status.workspaceHead -and $status.changes.Count -eq 0) {
        $completed = $true
        Write-Host "✓ Variable libraries synced successfully"
    } else {
        Write-Host "  [$attempt/$maxAttempts] Sync in progress..."
    }
}

if (-not $completed) {
    Write-Warning "Sync did not complete within expected time. Variable libraries may still be syncing."
}

Write-Host "✓ Workspace sync completed"
