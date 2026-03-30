# Compare Branches - Get detailed diff between current branch and target
# Returns comprehensive information about changes for PR review

param(
    [string]$TargetBranch = "origin/main",
    [switch]$IncludeDiffs = $true
)

$ErrorActionPreference = "Stop"

try {
    # Ensure we're in a git repository
    $gitRoot = git rev-parse --show-toplevel 2>&1
    if ($LASTEXITCODE -ne 0) {
        throw "Not in a git repository"
    }

    # Get current branch
    $currentBranch = git rev-parse --abbrev-ref HEAD
    if ($LASTEXITCODE -ne 0) {
        throw "Failed to get current branch"
    }

    # Fetch latest from remote
    Write-Host "Fetching latest changes from remote..." -ForegroundColor Cyan
    git fetch origin 2>&1 | Out-Null

    # Verify target branch exists
    git rev-parse --verify "$TargetBranch" 2>&1 | Out-Null
    if ($LASTEXITCODE -ne 0) {
        throw "Target branch '$TargetBranch' does not exist"
    }

    # Get statistics
    $statsOutput = git diff --shortstat "$TargetBranch"
    $additions = 0
    $deletions = 0
    
    if ($statsOutput -match '(\d+)\s+insertion') {
        $additions = [int]$Matches[1]
    }
    if ($statsOutput -match '(\d+)\s+deletion') {
        $deletions = [int]$Matches[1]
    }

    # Get list of changed files
    $changedFiles = git diff --name-status "$TargetBranch" | ForEach-Object {
        if ($_ -match '^([AMDRC])\s+(.+)$') {
            $status = switch ($Matches[1]) {
                'A' { 'added' }
                'M' { 'modified' }
                'D' { 'deleted' }
                'R' { 'renamed' }
                'C' { 'copied' }
                default { 'unknown' }
            }
            
            $filePath = $Matches[2]
            $fileObj = [PSCustomObject]@{
                path = $filePath
                status = $status
                diff = $null
            }

            # Get diff for this file if requested and file wasn't deleted
            if ($IncludeDiffs -and $status -ne 'deleted') {
                $diff = git diff "$TargetBranch" -- $filePath
                if ($diff) {
                    $fileObj.diff = $diff -join "`n"
                }
            }

            $fileObj
        }
    }

    # Build result object
    $result = [PSCustomObject]@{
        currentBranch = $currentBranch
        targetBranch = $TargetBranch
        filesChanged = $changedFiles.Count
        additions = $additions
        deletions = $deletions
        files = @($changedFiles)
        timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
    }

    # Output as JSON
    $result | ConvertTo-Json -Depth 10

    Write-Host "`nComparison complete: $($changedFiles.Count) files changed, +$additions -$deletions" -ForegroundColor Green

} catch {
    Write-Error "Failed to compare branches: $_"
    exit 1
}
