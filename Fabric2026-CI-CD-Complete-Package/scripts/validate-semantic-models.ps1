# Validate Semantic Models using Best Practice Analyzer
# Requires Tabular Editor 2 CLI (version 2.27.2 recommended)

param(
    [Parameter(Mandatory=$false)]
    [string]$OutputPath = "bpa-results.json",
    
    [Parameter(Mandatory=$false)]
    [switch]$QuietMode,
    
    [Parameter(Mandatory=$false)]
    [switch]$FailOnWarnings
)

$ErrorActionPreference = "Stop"

if (-not $QuietMode) {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Semantic Model Best Practice Analyzer" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
}

# Check if Tabular Editor 2 CLI is available
$te2Available = $null -ne (Get-Command "TabularEditor.exe" -ErrorAction SilentlyContinue)

if (-not $te2Available) {
    if (-not $QuietMode) {
        Write-Host "Tabular Editor 2 CLI not found in PATH. Checking common locations..." -ForegroundColor Yellow
    }
    
    # Check for portable version in common locations
    $portablePaths = @(
        "$PSScriptRoot\..\tools\TabularEditor2\TabularEditor.exe",
        "C:\Program Files (x86)\Tabular Editor\TabularEditor.exe",
        "$env:LOCALAPPDATA\TabularEditor\TabularEditor.exe",
        "$env:TEMP\TabularEditor\TabularEditor.exe"
    )
    
    $te2Path = $portablePaths | Where-Object { Test-Path $_ } | Select-Object -First 1
    
    if (-not $te2Path) {
        # Try to download Tabular Editor 2 portable
        if (-not $QuietMode) {
            Write-Host "Downloading Tabular Editor 2.27.2..." -ForegroundColor Cyan
        }
        
        $downloadPath = Join-Path $env:TEMP "TabularEditor"
        $te2Exe = Join-Path $downloadPath "TabularEditor.exe"
        
        if (-not (Test-Path $downloadPath)) {
            New-Item -ItemType Directory -Path $downloadPath -Force | Out-Null
        }
        
        try {
            # Download Tabular Editor 2 portable version from CDN
            # Use stable version 2.27.2 which has proven BPA support
            $downloadUrl = "https://cdn.tabulareditor.com/files/TabularEditor.2.27.2.zip"
            $zipPath = Join-Path $env:TEMP "te2.zip"
            
            Invoke-WebRequest -Uri $downloadUrl -OutFile $zipPath -UseBasicParsing
            Expand-Archive -Path $zipPath -DestinationPath $downloadPath -Force
            Remove-Item $zipPath -Force
            
            if (-not $QuietMode) {
                Write-Host "✓ Tabular Editor 2 downloaded successfully" -ForegroundColor Green
            }
            
            $te2Path = $te2Exe
        } catch {
            Write-Error "Failed to download Tabular Editor 2: $_`nPlease download manually from: https://github.com/TabularEditor/TabularEditor/releases"
            exit 1
        }
    }
    
    $te2Command = $te2Path
} else {
    $te2Command = "TabularEditor.exe"
}

# Find semantic models
$semanticModels = Get-ChildItem -Path . -Filter "*.SemanticModel" -Directory -Recurse

if ($semanticModels.Count -eq 0) {
    if (-not $QuietMode) {
        Write-Host "No semantic models found in workspace" -ForegroundColor Yellow
    }
    
    # Create empty result
    $result = @{
        Timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss UTC")
        TotalModels = 0
        ModelsAnalyzed = 0
        TotalViolations = 0
        ValidationPassed = $true
        Models = @()
    }
    
    $result | ConvertTo-Json -Depth 10 | Out-File $OutputPath -Encoding UTF8
    
    Write-Host "✓ No semantic models to validate" -ForegroundColor Green
    exit 0
}

if (-not $QuietMode) {
    Write-Host "Found $($semanticModels.Count) semantic model(s)" -ForegroundColor Cyan
    Write-Host ""
}

$results = @{
    Timestamp = (Get-Date).ToUniversalTime().ToString("yyyy-MM-dd HH:mm:ss UTC")
    TotalModels = $semanticModels.Count
    ModelsAnalyzed = 0
    TotalViolations = 0
    ValidationPassed = $true
    Models = @()
}

foreach ($model in $semanticModels) {
    $modelName = $model.Name -replace '\.SemanticModel$', ''
    
    # Safely get relative path, handle null FullName
    $relativePath = ""
    if ($model.FullName) {
        try {
            $relativePath = $model.FullName -replace [regex]::Escape((Get-Location).Path + [System.IO.Path]::DirectorySeparatorChar), ""
        }
        catch {
            $relativePath = $modelName
        }
    }
    else {
        $relativePath = $modelName
    }
    
    if (-not $QuietMode) {
        Write-Host "========================================" -ForegroundColor White
        Write-Host "Analyzing: $modelName" -ForegroundColor White
        Write-Host "Path: $relativePath" -ForegroundColor Gray
        Write-Host "========================================" -ForegroundColor White
    }
    
    # Determine model path for TMDL format (Fabric semantic models use definition folder)
    $modelPath = $null
    
    # Safely access FullName - in some Linux/ADO environments Get-ChildItem returns objects with null FullName
    # We need to be very careful not to pass null to Join-Path as parameter binding errors can't be caught
    if ($model -and $model.FullName) {
        try {
            # Manually construct path to avoid parameter binding errors with Join-Path
            $baseFolder = $model.FullName.ToString().TrimEnd('\', '/')
            $definitionPath = $baseFolder + [System.IO.Path]::DirectorySeparatorChar + "definition"
            
            if (Test-Path -LiteralPath $definitionPath -ErrorAction SilentlyContinue) {
                $modelPath = $definitionPath
            }
        }
        catch {
            # Silently catch any errors during path construction
        }
    }
    
    # Skip model if no valid path found
    if (-not $modelPath) {
        if (-not $QuietMode) {
            Write-Warning "Skipping $modelName - Cannot access definition folder (FullName may be null or path invalid)"
        }
        
        # Add to results as skipped (don't fail build for missing models)
        $results.Models += @{
            Name = $modelName
            Path = $relativePath
            Analyzed = $false
            Error = "Cannot access definition folder - model.FullName is null or definition folder not found"
            TotalViolations = 0
            Errors = 0
            Warnings = 0
            Info = 0
            Violations = @()
        }
        continue
    }
    
    # Run BPA analysis
    try {
        if (-not $QuietMode) {
            Write-Host "Running Best Practice Analyzer..." -ForegroundColor Cyan
        }
        
        # Run BPA using Tabular Editor 2 CLI with verbose output
        # Uses built-in BPA rules + custom rules if present
        $bpaArgs = @(
            "`"$modelPath`""
        )
        
        # Add custom BPA rules if present
        $customRulesPath = $null
        if ($PSScriptRoot) {
            $customRulesPath = Join-Path $PSScriptRoot ".bpaRules.json"
        }
        
        if ($customRulesPath -and (Test-Path $customRulesPath)) {
            $bpaArgs += "-A"
            $bpaArgs += "`"$customRulesPath`""
            if (-not $QuietMode) {
                Write-Host "Using custom BPA rules from: $customRulesPath" -ForegroundColor Cyan
            }
        } else {
            $bpaArgs += "-A"
            if (-not $QuietMode) {
                Write-Host "Using built-in BPA rules only" -ForegroundColor Cyan
            }
        }
        
        # Add verbose flag for detailed output
        $bpaArgs += "-V"
        
        if (-not $QuietMode) {
            Write-Host "Running Best Practice Analyzer..." -ForegroundColor Cyan
        }
        
        # Run Tabular Editor and capture output using Start-Process with output redirection
        # Use cross-platform temp directory
        $tempDir = if ($env:TEMP) { $env:TEMP } elseif ($env:TMPDIR) { $env:TMPDIR } else { "/tmp" }
        $tempOutput = Join-Path $tempDir "bpa-output-$modelName-$(Get-Date -Format 'yyyyMMddHHmmss').txt"
        
        # Build full argument string
        $argString = $bpaArgs -join " "
        
        # Run process and capture output
        $psi = New-Object System.Diagnostics.ProcessStartInfo
        $psi.FileName = $te2Command
        $psi.Arguments = $argString
        $psi.RedirectStandardOutput = $true
        $psi.RedirectStandardError = $true
        $psi.UseShellExecute = $false
        $psi.CreateNoWindow = $true
        
        $process = New-Object System.Diagnostics.Process
        $process.StartInfo = $psi
        $process.Start() | Out-Null
        
        $stdout = $process.StandardOutput.ReadToEnd()
        $stderr = $process.StandardError.ReadToEnd()
        $process.WaitForExit()
        
        # Combine stdout and stderr
        $output = $stdout + "`n" + $stderr
        
        # Parse BPA results from verbose text output
        $bpaResults = @()
        $violationPattern = 'violates rule "(.+)"'
        $errorPattern = '##\[error\]|Error loading|TmdlFormatException|Parsing error'
        
        $outputLines = $output -split '\r?\n'
        
        # Parse violations
        foreach ($line in $outputLines) {
            if ($line -match $violationPattern) {
                $ruleName = $Matches[1]
                
                # Determine severity based on rule category in the rule name
                $severity = if ($ruleName -match '\[Performance\]|\[Best Practice\]') {
                    "Error"
                } elseif ($ruleName -match '\[User Experience\]|\[Hygiene\]|\[Documentation\]|\[Naming\]') {
                    "Warning"
                } else {
                    "Warning"  # Default to warning
                }
                
                $violation = @{
                    RuleName = $ruleName
                    Severity = $severity
                    Description = $line.Trim()
                }
                
                $bpaResults += $violation
            }
        }
        
        # Check for critical errors
        $errorLines = $outputLines | Where-Object { $_ -match $errorPattern }
        $criticalErrors = $errorLines.Count
        
        $errorCount = ($bpaResults | Where-Object { $_.Severity -eq "Error" }).Count + $criticalErrors
        $warningCount = ($bpaResults | Where-Object { $_.Severity -eq "Warning" }).Count
        $infoCount = ($bpaResults | Where-Object { $_.Severity -eq "Info" }).Count
        $totalViolations = $bpaResults.Count + $criticalErrors
        
        $modelResult = @{
            Name = $modelName
            Path = $modelPath
            Analyzed = $true
            TotalViolations = $totalViolations
            Errors = $errorCount
            Warnings = $warningCount
            Info = $infoCount
            Violations = $bpaResults
        }
        
        $results.Models += $modelResult
        $results.ModelsAnalyzed++
        $results.TotalViolations += $totalViolations
        
        if ($errorCount -gt 0) {
            $results.ValidationPassed = $false
        } elseif ($FailOnWarnings -and $warningCount -gt 0) {
            $results.ValidationPassed = $false
        }
        
        if (-not $QuietMode) {
            if ($totalViolations -eq 0) {
                Write-Host "  ✓ No violations found" -ForegroundColor Green
            } else {
                Write-Host "  ✓ Analysis complete" -ForegroundColor Yellow
                Write-Host "    Errors:   $errorCount" -ForegroundColor $(if ($errorCount -gt 0) { "Red" } else { "Gray" })
                Write-Host "    Warnings: $warningCount" -ForegroundColor $(if ($warningCount -gt 0) { "Yellow" } else { "Gray" })
                Write-Host "    Info:     $infoCount" -ForegroundColor Gray
                if ($FailOnWarnings -and $warningCount -gt 0) {
                    Write-Host "    Status:   FAILED (warnings treated as errors)" -ForegroundColor Red
                }
            }
        }
        
    } catch {
        if (-not $QuietMode) {
            Write-Warning "Failed to analyze ${modelName}: $($_.Exception.Message)"
        }
        
        $modelResult = @{
            Name = $modelName
            Path = $relativePath
            Analyzed = $false
            Error = $_.Exception.Message
            TotalViolations = 0
            Errors = 0
            Warnings = 0
            Info = 0
            Violations = @()
        }
        
        $results.Models += $modelResult
        
        # Fail validation only for actual BPA issues, not infrastructure problems
        if ($_.Exception.Message -notmatch "path|does not exist|cannot find|Tabular Editor") {
            $results.ValidationPassed = $false
        }
    }
    
    if (-not $QuietMode) {
        Write-Host ""
    }
}

# Save results
$results | ConvertTo-Json -Depth 10 | Out-File $OutputPath -Encoding UTF8

if (-not $QuietMode) {
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Validation Summary" -ForegroundColor Cyan
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host "Total Models:  $($results.TotalModels)" -ForegroundColor White
    Write-Host "Total Violations: $($results.TotalViolations)" -ForegroundColor $(if ($results.TotalViolations -gt 0) { "Yellow" } else { "Green" })
    
    $errorModels = $results.Models | Where-Object { $_.Errors -gt 0 }
    $warningModels = $results.Models | Where-Object { $_.Warnings -gt 0 -and $_.Errors -eq 0 }
    
    if ($errorModels.Count -gt 0) {
        Write-Host "Models with Errors: $($errorModels.Count)" -ForegroundColor Red
    }
    if ($warningModels.Count -gt 0) {
        Write-Host "Models with Warnings: $($warningModels.Count)" -ForegroundColor Yellow
    }
    
    if ($results.ValidationPassed) {
        Write-Host "Status: PASSED ✓" -ForegroundColor Green
    } else {
        if ($FailOnWarnings) {
            Write-Host "Status: FAILED (errors or warnings found)" -ForegroundColor Red
        } else {
            Write-Host "Status: FAILED (errors found)" -ForegroundColor Red
        }
    }
    Write-Host "========================================" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "✓ Results saved to: $OutputPath" -ForegroundColor Green
}

# Exit with appropriate code
if (-not $results.ValidationPassed) {
    exit 1
}

exit 0
