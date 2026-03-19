# Post Validation Report as PR Comment
# Posts markdown report to Azure DevOps Pull Request

param(
    [Parameter(Mandatory=$true)]
    [string]$ReportPath,
    
    [Parameter(Mandatory=$true)]
    [string]$ResultsPath,
    
    [Parameter(Mandatory=$false)]
    [string]$TransformationResultsPath,
    
    [Parameter(Mandatory=$false)]
    [string]$BpaResultsPath,
    
    [Parameter(Mandatory=$false)]
    [string]$PylintResultsPath,
    
    [Parameter(Mandatory=$true)]
    [string]$Organization,
    
    [Parameter(Mandatory=$true)]
    [string]$Project,
    
    [Parameter(Mandatory=$true)]
    [string]$RepositoryId,
    
    [Parameter(Mandatory=$true)]
    [string]$PullRequestId,
    
    [Parameter(Mandatory=$true)]
    [string]$AccessToken
)

function Get-ConciseReport {
    param(
        [string]$FullReport,
        [string]$BuildId,
        [object]$ValidationResults
    )
    
    # Extract summary section and validation results
    $lines = $FullReport -split "`n"
    $conciseLines = @()
    $inSummary = $true
    $captureDetails = $false
    $lastWasSection = $false
    
    foreach ($line in $lines) {
        # Always capture title and summary
        if ($inSummary) {
            $conciseLines += $line
            
            # Check if we're past the summary table
            if ($line -match "^\|\s+⚠️ Warnings" -or $line -match "^---$") {
                # Continue for a few more lines after the table
                continue
            }
            
            # When we hit a section header after summary, stop summary mode
            if ($line -match "^## " -and $conciseLines.Count -gt 10) {
                $inSummary = $false
                
                # Add blank line before sections
                $conciseLines += ""
                
                # Check if this section has errors/warnings
                if ($line -match "❌|⚠️") {
                    $captureDetails = $true
                    $conciseLines += $line
                    $lastWasSection = $true
                } elseif ($line -match "^## ✅") {
                    # Section passed - just show the header
                    $conciseLines += $line
                    $captureDetails = $false
                    $lastWasSection = $true
                } else {
                    $captureDetails = $false
                }
            }
        }
        # Handle section headers
        elseif ($line -match "^## ") {
            # Check if this is an artifact line (has backticks)
            if ($line -match "^## .+ ``") {
                # This is an individual artifact, skip header processing
                break
            }
            
            # Add blank line between sections if needed
            if (-not $lastWasSection) {
                $conciseLines += ""
            }
            
            # Security section should always show details (even when all pass)
            if ($line -match "^## .+ Security Scan Results") {
                $captureDetails = $true
                $conciseLines += $line
                $lastWasSection = $true
            }
            # Check if this section has errors/warnings
            elseif ($line -match "❌|⚠️") {
                $captureDetails = $true
                $conciseLines += $line
                $lastWasSection = $true
            } elseif ($line -match "^## ✅") {
                # Section passed - just show the header
                $conciseLines += $line
                $captureDetails = $false
                $lastWasSection = $true
            } else {
                $captureDetails = $false
            }
        }
        # Capture details only for sections with issues
        elseif ($captureDetails) {
            # Stop capturing artifact details (too verbose)
            if ($line -match "^### 📋") {
                # Skip detailed validations for individual artifacts
                $captureDetails = $false
                $lastWasSection = $false
            } elseif ($line -match "^## ") {
                # Hit next section
                $lastWasSection = $false
            } else {
                $conciseLines += $line
                $lastWasSection = $false
            }
        }
    }
    
    # Add artifact type summaries
    if ($ValidationResults.Artifacts -and $ValidationResults.Artifacts.Count -gt 0) {
        $conciseLines += ""
        
        # Group artifacts by type
        $artifactsByType = $ValidationResults.Artifacts | Group-Object -Property Type
        
        foreach ($typeGroup in $artifactsByType) {
            $typeName = $typeGroup.Name
            $artifacts = $typeGroup.Group
            $totalCount = $artifacts.Count
            $passedCount = ($artifacts | Where-Object { $_.Status -eq "Passed" }).Count
            $failedCount = ($artifacts | Where-Object { $_.Status -eq "Failed" }).Count
            $warningCount = $totalCount - $passedCount - $failedCount
            
            # Determine status icon
            $icon = if ($failedCount -gt 0) { "❌" } elseif ($warningCount -gt 0) { "⚠️" } else { "✅" }
            
            $conciseLines += "## $icon ${typeName} Validations"
            $conciseLines += ""
            $conciseLines += "**Checked:** $totalCount | ✅ Passed: $passedCount | ❌ Failed: $failedCount"
            
            # Show failed/warning artifacts
            if ($failedCount -gt 0 -or $warningCount -gt 0) {
                $conciseLines += ""
                foreach ($artifact in $artifacts) {
                    if ($artifact.Status -ne "Passed") {
                        $artifactIcon = if ($artifact.Status -eq "Failed") { "❌" } else { "⚠️" }
                        $conciseLines += "- $artifactIcon ``$($artifact.Name)``"
                    }
                }
            }
            
            $conciseLines += ""
        }
    }
    
    # Add link to full report
    $encodedProject = [System.Uri]::EscapeDataString($Project)
    $conciseLines += ""
    $conciseLines += "---"
    $conciseLines += ""
    $conciseLines += "📄 **[View Full Validation Report]($(${Organization}.TrimEnd('/'))/$(${encodedProject})/_build/results?buildId=$BuildId&view=artifacts)** in build artifacts: ``validation-results/validation-report.md``"
    $conciseLines += ""
    
    return ($conciseLines -join "`n")
}

# Load report and results
$report = Get-Content $ReportPath -Raw
$results = Get-Content $ResultsPath | ConvertFrom-Json

# Get Build ID for artifact link
$buildId = $env:BUILD_BUILDID
if (-not $buildId) {
    Write-Warning "BUILD_BUILDID not found, using placeholder"
    $buildId = "0"
}

# Create concise version for PR comment
$conciseReport = Get-ConciseReport -FullReport $report -BuildId $buildId -ValidationResults $results

# Load transformation results to determine overall status
$hasTransformationFailures = $false
if ($TransformationResultsPath -and (Test-Path $TransformationResultsPath)) {
    try {
        $transformResults = Get-Content $TransformationResultsPath | ConvertFrom-Json
        $hasTransformationFailures = -not $transformResults.ValidationPassed
    } catch {
        Write-Warning "Could not load transformation validation results: $_"
    }
}

# Check BPA results for real failures (not just skipped models)
$hasBpaFailures = $false
if ($BpaResultsPath -and (Test-Path $BpaResultsPath)) {
    try {
        $bpaResults = Get-Content $BpaResultsPath | ConvertFrom-Json
        # Check if validation passed or if there are models with real errors (not just skipped)
        if (-not $bpaResults.ValidationPassed) {
            $hasBpaFailures = $true
        } else {
            # Check for models that failed to analyze for non-path-related reasons
            foreach ($model in $bpaResults.Models) {
                if (-not $model.Analyzed -and $model.Error -notmatch "path is null|path is empty|not exist in workspace|does not exist|Error accessing model path|Skipping") {
                    $hasBpaFailures = $true
                    break
                }
            }
        }
    } catch {
        Write-Warning "Could not load BPA results: $_"
    }
}

# Check pylint results for errors
$hasPylintErrors = $false
if ($PylintResultsPath -and (Test-Path $PylintResultsPath)) {
    try {
        $pylintResults = Get-Content $PylintResultsPath | ConvertFrom-Json
        $errorCount = ($pylintResults | Where-Object { $_.type -eq "error" }).Count
        if ($errorCount -gt 0) {
            $hasPylintErrors = $true
        }
    } catch {
        Write-Warning "Could not load pylint results: $_"
    }
}

# Azure DevOps REST API endpoint
$orgUrl = $Organization.TrimEnd('/')
$apiVersion = "7.1-preview.1"
$pullRequestThreadsUrl = "$orgUrl/$Project/_apis/git/repositories/$RepositoryId/pullRequests/$PullRequestId/threads?api-version=$apiVersion"

Write-Host "Posting validation report to PR #$PullRequestId..." -ForegroundColor Cyan
Write-Host "API URL: $pullRequestThreadsUrl" -ForegroundColor Gray

# Determine thread status based on ALL validation results
# Use numeric values: 1 = active (has issues), 4 = closed (all passed)
$overallHasViolations = $results.HasViolations -or $hasTransformationFailures -or $hasBpaFailures -or $hasPylintErrors
$threadStatus = if ($overallHasViolations) { 1 } else { 4 }

# Create comment thread (no custom properties needed - we search by content)
$commentBody = @{
    comments = @(
        @{
            parentCommentId = 0
            content = $conciseReport
            commentType = 1  # 1 = text, 2 = system
        }
    )
    status = $threadStatus
} | ConvertTo-Json -Depth 10

# Set up headers
$headers = @{
    "Authorization" = "Bearer $AccessToken"
    "Content-Type" = "application/json"
}

try {
    # First, check if there's an existing validation comment
    Write-Host "Checking for existing validation comments..." -ForegroundColor Yellow
    
    $existingThreads = Invoke-RestMethod -Uri $pullRequestThreadsUrl -Headers $headers -Method Get
    Write-Host "Found $($existingThreads.value.Count) existing threads" -ForegroundColor Gray
    
    # Find existing validation thread by searching for header text
    $validationThread = $null
    foreach ($thread in $existingThreads.value) {
        $firstComment = $thread.comments[0].content
        if ($firstComment -match "Fabric Artifact Validation Report") {
            $validationThread = $thread
            Write-Host "Found existing validation thread (ID: $($thread.id))" -ForegroundColor Green
            break
        }
    }
    
    if ($validationThread) {
        # Update existing comment content
        $updateCommentUrl = "$orgUrl/$Project/_apis/git/repositories/$RepositoryId/pullRequests/$PullRequestId/threads/$($validationThread.id)/comments/1?api-version=7.0"
        
        $commentUpdate = @{
            content = $conciseReport
        } | ConvertTo-Json
        
        Invoke-RestMethod -Uri $updateCommentUrl -Headers $headers -Method Patch -Body $commentUpdate | Out-Null
        Write-Host "✓ Updated existing validation comment" -ForegroundColor Green
        
        # Update thread status
        $updateThreadUrl = "$orgUrl/$Project/_apis/git/repositories/$RepositoryId/pullRequests/$PullRequestId/threads/$($validationThread.id)?api-version=7.0"
        
        $statusUpdate = @{
            status = $threadStatus
        } | ConvertTo-Json
        
        Invoke-RestMethod -Uri $updateThreadUrl -Headers $headers -Method Patch -Body $statusUpdate | Out-Null
        Write-Host "✓ Updated thread status to: $threadStatus" -ForegroundColor Cyan
        
    } else {
        Write-Host "No existing validation comment found, creating new thread..." -ForegroundColor Yellow
        
        # Create new thread
        $response = Invoke-RestMethod -Uri $pullRequestThreadsUrl -Headers $headers -Method Post -Body $commentBody
        Write-Host "✓ Created new PR comment thread (ID: $($response.id))" -ForegroundColor Green
    }
    
    # Set PR status
    if ($overallHasViolations) {
        $violationTypes = @()
        if ($results.HasViolations) { $violationTypes += "artifact violations" }
        if ($hasTransformationFailures) { $violationTypes += "transformation failures" }
        if ($hasBpaFailures) { $violationTypes += "BPA failures" }
        if ($hasPylintErrors) { $violationTypes += "pylint errors" }
        Write-Host "⚠️ Thread status set to 'active' (1) due to: $($violationTypes -join ', ')" -ForegroundColor Yellow
    } else {
        Write-Host "✅ Thread status set to 'closed' (4) - all validations passed" -ForegroundColor Green
    }
    
} catch {
    Write-Host "❌ Error posting PR comment: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Response: $($_.ErrorDetails.Message)" -ForegroundColor Red
    
    # If it's a permissions error, fail the build
    if ($_.ErrorDetails.Message -match "TF401027|PullRequestContribute") {
        Write-Host "❌ Build service lacks required permissions. Please grant 'PullRequestContribute' permission." -ForegroundColor Red
        exit 1
    }
    
    # For other errors, continue with a warning
    Write-Host "⚠️ Continuing despite PR comment error..." -ForegroundColor Yellow
}

Write-Host "`n✓ PR comment processing complete" -ForegroundColor Cyan
