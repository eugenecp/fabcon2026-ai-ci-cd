# Test Review PR Skill
# Validates that the skill scripts work correctly

param(
    [string]$TargetBranch = "origin/main"
)

$ErrorActionPreference = "Stop"
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Testing Review PR Skill" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

$testsPassed = 0
$testsFailed = 0

# Test 1: Compare Branches Script
Write-Host "[Test 1] Testing compare-branches.ps1..." -ForegroundColor Yellow
try {
    $compareScript = Join-Path $scriptDir "scripts\compare-branches.ps1"
    
    if (-not (Test-Path $compareScript)) {
        throw "Script not found: $compareScript"
    }
    
    Write-Host "  Running compare-branches.ps1..." -ForegroundColor Gray
    $comparisonJson = & $compareScript -TargetBranch $TargetBranch
    
    if (-not $comparisonJson) {
        throw "No output from compare-branches.ps1"
    }
    
    $comparison = $comparisonJson | ConvertFrom-Json
    
    # Validate output structure
    if (-not $comparison.currentBranch) { throw "Missing currentBranch" }
    if (-not $comparison.targetBranch) { throw "Missing targetBranch" }
    if ($null -eq $comparison.filesChanged) { throw "Missing filesChanged" }
    
    Write-Host "  ✓ Branch comparison successful" -ForegroundColor Green
    Write-Host "    Current: $($comparison.currentBranch)" -ForegroundColor Gray
    Write-Host "    Target: $($comparison.targetBranch)" -ForegroundColor Gray
    Write-Host "    Files Changed: $($comparison.filesChanged)" -ForegroundColor Gray
    Write-Host "    Additions: +$($comparison.additions)" -ForegroundColor Gray
    Write-Host "    Deletions: -$($comparison.deletions)" -ForegroundColor Gray
    
    $testsPassed++
    
    # Test 2: Analyze Artifacts Script
    Write-Host "`n[Test 2] Testing analyze-artifacts.ps1..." -ForegroundColor Yellow
    try {
        $analyzeScript = Join-Path $scriptDir "scripts\analyze-artifacts.ps1"
        
        if (-not (Test-Path $analyzeScript)) {
            throw "Script not found: $analyzeScript"
        }
        
        Write-Host "  Running analyze-artifacts.ps1..." -ForegroundColor Gray
        $artifactsJson = & $analyzeScript -BranchComparisonJson ($comparison | ConvertTo-Json -Depth 10)
        
        if (-not $artifactsJson) {
            throw "No output from analyze-artifacts.ps1"
        }
        
        $artifacts = $artifactsJson | ConvertFrom-Json
        
        # Validate output structure
        if (-not $artifacts.summary) { throw "Missing summary" }
        if (-not $artifacts.artifacts) { throw "Missing artifacts" }
        
        Write-Host "  ✓ Artifact analysis successful" -ForegroundColor Green
        Write-Host "    Total Files: $($artifacts.summary.totalFiles)" -ForegroundColor Gray
        Write-Host "    Notebooks: $($artifacts.summary.notebooks)" -ForegroundColor Gray
        Write-Host "    Lakehouses: $($artifacts.summary.lakehouses)" -ForegroundColor Gray
        Write-Host "    Pipelines: $($artifacts.summary.pipelines)" -ForegroundColor Gray
        Write-Host "    Scripts: $($artifacts.summary.scripts)" -ForegroundColor Gray
        
        $testsPassed++
        
        # Test 3: Get File Context Script
        Write-Host "`n[Test 3] Testing get-file-context.ps1..." -ForegroundColor Yellow
        try {
            $contextScript = Join-Path $scriptDir "scripts\get-file-context.ps1"
            
            if (-not (Test-Path $contextScript)) {
                throw "Script not found: $contextScript"
            }
            
            # Find a test file (try the README or SKILL.md)
            $testFile = Join-Path $scriptDir "README.md"
            if (-not (Test-Path $testFile)) {
                $testFile = Join-Path $scriptDir "SKILL.md"
            }
            
            if (Test-Path $testFile) {
                Write-Host "  Running get-file-context.ps1 on $testFile..." -ForegroundColor Gray
                $contextJson = & $contextScript -FilePath $testFile -MaxLines 100 -IncludeMetadata
                
                if (-not $contextJson) {
                    throw "No output from get-file-context.ps1"
                }
                
                $context = $contextJson | ConvertFrom-Json
                
                # Validate output structure
                if (-not $context.path) { throw "Missing path" }
                if (-not $context.name) { throw "Missing name" }
                if (-not $context.language) { throw "Missing language" }
                if ($null -eq $context.lineCount) { throw "Missing lineCount" }
                if (-not $context.content) { throw "Missing content" }
                
                Write-Host "  ✓ File context extraction successful" -ForegroundColor Green
                Write-Host "    File: $($context.name)" -ForegroundColor Gray
                Write-Host "    Language: $($context.language)" -ForegroundColor Gray
                Write-Host "    Lines: $($context.lineCount)" -ForegroundColor Gray
                Write-Host "    Truncated: $($context.truncated)" -ForegroundColor Gray
                
                $testsPassed++
            } else {
                Write-Host "  ⊘ Skipped - no test file available" -ForegroundColor Yellow
            }
            
        } catch {
            Write-Host "  ✗ Test 3 failed: $_" -ForegroundColor Red
            $testsFailed++
        }
        
    } catch {
        Write-Host "  ✗ Test 2 failed: $_" -ForegroundColor Red
        $testsFailed++
    }
    
} catch {
    Write-Host "  ✗ Test 1 failed: $_" -ForegroundColor Red
    $testsFailed++
}

# Test 4: SKILL.md Structure
Write-Host "`n[Test 4] Testing SKILL.md structure..." -ForegroundColor Yellow
try {
    $skillFile = Join-Path $scriptDir "SKILL.md"
    
    if (-not (Test-Path $skillFile)) {
        throw "SKILL.md not found"
    }
    
    $content = Get-Content $skillFile -Raw
    
    # Check for YAML frontmatter
    if ($content -notmatch '^---\s*\n') {
        throw "Missing YAML frontmatter"
    }
    
    # Check for required fields
    if ($content -notmatch 'name:\s*review-pr') {
        throw "Missing or incorrect name field"
    }
    
    if ($content -notmatch 'description:') {
        throw "Missing description field"
    }
    
    # Check for key sections
    $requiredSections = @(
        '# Review Pull Request',
        '## When to Use',
        '## The 5 Enterprise-Ready Principles',
        '## Procedure',
        '## Scripts'
    )
    
    foreach ($section in $requiredSections) {
        if ($content -notmatch [regex]::Escape($section)) {
            throw "Missing required section: $section"
        }
    }
    
    Write-Host "  ✓ SKILL.md structure valid" -ForegroundColor Green
    $testsPassed++
    
} catch {
    Write-Host "  ✗ Test 4 failed: $_" -ForegroundColor Red
    $testsFailed++
}

# Summary
Write-Host "`n========================================" -ForegroundColor Cyan
Write-Host "Test Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Passed: $testsPassed" -ForegroundColor Green
Write-Host "Failed: $testsFailed" -ForegroundColor $(if ($testsFailed -eq 0) { "Green" } else { "Red" })
Write-Host ""

if ($testsFailed -eq 0) {
    Write-Host "✓ All tests passed! The review-pr skill is ready to use." -ForegroundColor Green
    exit 0
} else {
    Write-Host "✗ Some tests failed. Please review the errors above." -ForegroundColor Red
    exit 1
}
