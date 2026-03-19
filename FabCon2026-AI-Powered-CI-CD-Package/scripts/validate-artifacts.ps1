# Validate Fabric Artifacts - Main Orchestrator
# This script orchestrates validation of different Fabric artifact types
# Calls separate validators for each artifact type for easier debugging

param(
    [Parameter(Mandatory=$true)]
    [string]$OutputPath
)

$ErrorActionPreference = "Continue"

# Get the script directory
$scriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$validatorsDir = Join-Path $scriptDir "validators"

# Initialize results
$results = @{
    Timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss UTC"
    TotalArtifacts = 0
    PassedValidations = 0
    FailedValidations = 0
    WarningValidations = 0
    HasViolations = $false
    Artifacts = @()
}

Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Fabric Artifact Validation" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Working directory: $(Get-Location)" -ForegroundColor Gray
Write-Host "Validators directory: $validatorsDir" -ForegroundColor Gray
Write-Host ""

# Function to validate naming convention
function Test-NamingConvention {
    param([string]$Name, [string]$Type)
    
    $violations = @()
    
    # Skip naming convention for DBML files (they follow layer naming: bronze.dbml, silver.dbml, gold.dbml)
    if ($Type -eq "DBML") {
        return $violations
    }
    
    # Expected pattern: ArtifactType_Index_Stage_Description_Suffix
    # At minimum: ArtifactType_Description
    
    $typeAbbreviations = @{
        "Notebook" = "NB"
        "Lakehouse" = "LH"
        "Pipeline" = "PL"
        "Dataflow" = "DFL"
        "Dataset" = "DS"
        "Warehouse" = "WH"
        "VariableLibrary" = "VL"
    }
    
    $expectedPrefix = $typeAbbreviations[$Type]
    
    if ($expectedPrefix) {
        if (-not $Name.StartsWith($expectedPrefix + "_")) {
            $violations += "Name should start with '${expectedPrefix}_' prefix"
        }
    }
    
    # Check for spaces (not allowed per Lakehouse restrictions)
    if ($Name -match '\s') {
        $violations += "Name contains spaces (use underscores instead)"
    }
    
    # Check for special characters (only underscores and alphanumeric allowed)
    if ($Name -match '[^a-zA-Z0-9_]') {
        $violations += "Name contains invalid characters (only letters, numbers, and underscores allowed)"
    }
    
    # Check if first character is a letter
    if ($Name -notmatch '^[a-zA-Z]') {
        $violations += "Name must start with a letter"
    }
    
    return $violations
}

# Scan for artifacts
Write-Host "Scanning for artifacts..." -ForegroundColor Cyan

# Find all Fabric artifact directories
$notebooks = Get-ChildItem -Directory -Filter "*.Notebook" -ErrorAction SilentlyContinue
$lakehouses = Get-ChildItem -Directory -Filter "*.Lakehouse" -ErrorAction SilentlyContinue
$pipelines = Get-ChildItem -Directory -Filter "*.DataPipeline" -ErrorAction SilentlyContinue
$variableLibraries = Get-ChildItem -Directory -Filter "*.VariableLibrary" -ErrorAction SilentlyContinue

# Find all DBML files (schema definitions)
$dbmlFiles = Get-ChildItem -Recurse -Filter "*.dbml" -File -ErrorAction SilentlyContinue | Where-Object { $_.DirectoryName -match "dbml" }

$allArtifacts = [System.Collections.ArrayList]::new()

# Add notebooks
foreach ($nb in $notebooks) {
    $notebookName = $nb.Name -replace '\.Notebook$'
    [void]$allArtifacts.Add([PSCustomObject]@{ 
        Type = "Notebook"
        Path = $nb.FullName
        Name = $notebookName
    })
}

# Add lakehouses
foreach ($lh in $lakehouses) {
    $lakehouseName = $lh.Name -replace '\.Lakehouse$'
    [void]$allArtifacts.Add([PSCustomObject]@{ 
        Type = "Lakehouse"
        Path = $lh.FullName
        Name = $lakehouseName
    })
}

# Add pipelines
foreach ($pl in $pipelines) {
    $pipelineName = $pl.Name -replace '\.DataPipeline$'
    [void]$allArtifacts.Add([PSCustomObject]@{ 
        Type = "Pipeline"
        Path = $pl.FullName
        Name = $pipelineName
    })
}

# Add variable libraries
foreach ($vl in $variableLibraries) {
    $vlName = $vl.Name -replace '\.VariableLibrary$'
    [void]$allArtifacts.Add([PSCustomObject]@{ 
        Type = "VariableLibrary"
        Path = $vl.FullName
        Name = $vlName
    })
}

# Add DBML files
foreach ($dbml in $dbmlFiles) {
    # Determine layer from path (bronze/silver/gold)
    $layer = ""
    if ($dbml.DirectoryName -match "\\dbml\\(bronze|silver|gold)") {
        $layer = $matches[1]
    }
    
    $dbmlName = $dbml.BaseName
    [void]$allArtifacts.Add([PSCustomObject]@{ 
        Type = "DBML"
        Path = $dbml.FullName
        Name = $dbmlName
        Layer = $layer
    })
}

$results.TotalArtifacts = $allArtifacts.Count
Write-Host "Found $($results.TotalArtifacts) artifact(s)" -ForegroundColor Cyan
Write-Host ""

# Process each artifact
foreach ($artifact in $allArtifacts) {
    Write-Host "========================================" -ForegroundColor DarkGray
    Write-Host "Artifact: $($artifact.Name)" -ForegroundColor Green
    Write-Host "Type: $($artifact.Type)" -ForegroundColor Gray
    Write-Host "========================================" -ForegroundColor DarkGray
    
    $artifactResult = @{
        Name = $artifact.Name
        Type = $artifact.Type
        Path = $artifact.Path
        NamingViolations = @()
        Validations = @()
        Status = "Passed"
    }
    
    # Check naming convention
    Write-Host "Checking naming convention..." -ForegroundColor Yellow
    $namingViolations = Test-NamingConvention -Name $artifact.Name -Type $artifact.Type
    if ($namingViolations.Count -gt 0) {
        $artifactResult.NamingViolations = $namingViolations
        $results.HasViolations = $true
        $artifactResult.Status = "Failed"
        Write-Host "  ❌ Naming violations: $($namingViolations.Count)" -ForegroundColor Red
        foreach ($violation in $namingViolations) {
            Write-Host "     - $violation" -ForegroundColor Red
        }
    } else {
        Write-Host "  ✓ Naming convention passed" -ForegroundColor Green
    }
    
    # Run type-specific validator
    $validatorScript = Join-Path $validatorsDir "validate-$($artifact.Type.ToLower()).ps1"
    
    if (Test-Path $validatorScript) {
        Write-Host "Running $($artifact.Type) validator..." -ForegroundColor Yellow
        try {
            # For DBML files, pass the Layer parameter
            if ($artifact.Type -eq "DBML" -and $artifact.Layer) {
                $validationJson = & $validatorScript -Path $artifact.Path -Name $artifact.Name -Layer $artifact.Layer
            } else {
                $validationJson = & $validatorScript -Path $artifact.Path -Name $artifact.Name
            }
            
            $artifactResult.Validations = $validationJson | ConvertFrom-Json
            
            # Count results
            $passed = ($artifactResult.Validations | Where-Object { $_.Status -eq "Passed" }).Count
            $failed = ($artifactResult.Validations | Where-Object { $_.Status -eq "Failed" }).Count
            $warnings = ($artifactResult.Validations | Where-Object { $_.Status -eq "Warning" }).Count
            
            $results.PassedValidations += $passed
            $results.FailedValidations += $failed
            $results.WarningValidations += $warnings
            
            if ($failed -gt 0) {
                $artifactResult.Status = "Failed"
                $results.HasViolations = $true
            }
            
            Write-Host "  ✓ Passed: $passed" -ForegroundColor Green
            if ($failed -gt 0) {
                Write-Host "  ❌ Failed: $failed" -ForegroundColor Red
            }
            if ($warnings -gt 0) {
                Write-Host "  ⚠ Warnings: $warnings" -ForegroundColor Yellow
            }
            
        } catch {
            Write-Host "  ❌ Validator error: $($_.Exception.Message)" -ForegroundColor Red
            $artifactResult.Validations += @{
                Principle = "Validation"
                Check = "Validator execution"
                Status = "Failed"
                Message = "Validator script error: $($_.Exception.Message)"
            }
            $artifactResult.Status = "Failed"
            $results.HasViolations = $true
            $results.FailedValidations++
        }
    } else {
        Write-Host "  ⚠ No validator found: $validatorScript" -ForegroundColor Yellow
        $artifactResult.Validations += @{
            Principle = "Validation"
            Check = "Validator exists"
            Status = "Warning"
            Message = "No validator script found for $($artifact.Type)"
        }
        $results.WarningValidations++
    }
    
    Write-Host ""
    $results.Artifacts += $artifactResult
}

# Summary
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Validation Summary" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "Total Artifacts: $($results.TotalArtifacts)" -ForegroundColor White
Write-Host "✓ Passed Validations: $($results.PassedValidations)" -ForegroundColor Green
if ($results.FailedValidations -gt 0) {
    Write-Host "❌ Failed Validations: $($results.FailedValidations)" -ForegroundColor Red
}
if ($results.WarningValidations -gt 0) {
    Write-Host "⚠ Warnings: $($results.WarningValidations)" -ForegroundColor Yellow
}
Write-Host "Has Violations: $(if ($results.HasViolations) { 'YES' } else { 'NO' })" -ForegroundColor $(if ($results.HasViolations) { "Red" } else { "Green" })
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Save results
$resultsJson = $results | ConvertTo-Json -Depth 10
$resultsJson | Out-File -FilePath $OutputPath -Encoding UTF8
Write-Host "✓ Results saved to: $OutputPath" -ForegroundColor Cyan

exit 0
