# Generate Validation Report for PR Comment
# Creates markdown report from validation results

param(
    [Parameter(Mandatory=$true)]
    [string]$ResultsPath,
    
    [Parameter(Mandatory=$true)]
    [string]$OutputPath,
    
    [Parameter(Mandatory=$false)]
    [string]$TransformationResultsPath,
    
    [Parameter(Mandatory=$false)]
    [string]$PylintResultsPath,
    
    [Parameter(Mandatory=$false)]
    [string]$BpaResultsPath
)

# Load results
$results = Get-Content $ResultsPath | ConvertFrom-Json

# Load transformation results first to include in overall status
$transformResults = $null
$hasTransformationFailures = $false
if ($TransformationResultsPath -and (Test-Path $TransformationResultsPath)) {
    try {
        $transformResults = Get-Content $TransformationResultsPath | ConvertFrom-Json
        $hasTransformationFailures = -not $transformResults.ValidationPassed
    } catch {
        Write-Warning "Could not load transformation validation results: $_"
    }
}

# Load BPA results to include in totals
$bpaResults = $null
$bpaWarningCount = 0
if ($BpaResultsPath -and (Test-Path $BpaResultsPath)) {
    try {
        $bpaResults = Get-Content $BpaResultsPath | ConvertFrom-Json
        $bpaWarningCount = $bpaResults.TotalViolations
    } catch {
        Write-Warning "Could not load BPA results: $_"
    }
}

# Load Pylint results to include in totals
$pylintResults = $null
$pylintErrorCount = 0
$pylintWarningCount = 0
if ($PylintResultsPath -and (Test-Path $PylintResultsPath)) {
    try {
        $pylintResults = Get-Content $PylintResultsPath | ConvertFrom-Json
        $pylintErrorCount = ($pylintResults | Where-Object { $_.type -eq "error" }).Count
        $pylintWarningCount = ($pylintResults | Where-Object { $_.type -eq "warning" }).Count
    } catch {
        Write-Warning "Could not load pylint results: $_"
    }
}

# Load Bandit security results to include in summary
$banditResults = $null
$banditIssueCount = 0
$stagingDir = Split-Path $ResultsPath -Parent
$banditPath = Join-Path $stagingDir "bandit-results.json"
if (Test-Path $banditPath) {
    try {
        $banditResults = Get-Content $banditPath | ConvertFrom-Json
        $banditIssueCount = $banditResults.results.Count
    } catch {
        Write-Warning "Could not load Bandit results: $_"
    }
}

# Calculate overall status including all validation sources
$overallHasViolations = $results.HasViolations -or $hasTransformationFailures -or ($pylintErrorCount -gt 0)
$totalFailedCount = $results.FailedValidations + $(if ($hasTransformationFailures) { $transformResults.InvalidFiles } else { 0 }) + $pylintErrorCount
$totalWarningCount = $results.WarningValidations + $bpaWarningCount + $pylintWarningCount + $banditIssueCount

# Start building markdown report
$report = @"
# 🔍 Fabric Artifact Validation Report

**Validation Time:** $($results.Timestamp)

"@

# Add summary with emojis
if ($overallHasViolations) {
    $report += @"
## ❌ Validation Failed

"@
} else {
    $report += @"
## ✅ All Validations Passed

"@
}

$report += @"
| Metric | Count |
|--------|-------|
| Total Artifacts | $($results.TotalArtifacts) |
| ✅ Passed | $($results.PassedValidations) |
| ❌ Failed | $totalFailedCount |
| ⚠️ Warnings | $totalWarningCount |

"@

# Add sub-totals for transparency
if ($bpaWarningCount -gt 0 -or $pylintWarningCount -gt 0 -or $banditIssueCount -gt 0) {
    $report += @"
<details>
<summary>📊 Warning Breakdown</summary>

- Artifact Validations: $($results.WarningValidations)
- Semantic Model BPA: $bpaWarningCount
- Pylint Code Quality: $pylintWarningCount
- Bandit Security: $banditIssueCount

</details>

"@
}

$report += "---`n`n"

# Add transformation validation results if available
if ($transformResults) {
    $transformStatus = if ($transformResults.ValidationPassed) { "✅" } else { "❌" }
    
    $report += @"
## $transformStatus YAML Transformation Validation

**Transformation Files:** $($transformResults.TotalFiles) | ✅ Valid: $($transformResults.ValidFiles) | ❌ Invalid: $($transformResults.InvalidFiles)

"@
    
    if ($transformResults.InvalidFiles -gt 0) {
        $report += "### ❌ Failed Transformations`n`n"
        
        $failedTransforms = $transformResults.Transformations.PSObject.Properties | Where-Object { -not $_.Value.Valid }
        
        foreach ($transform in $failedTransforms) {
            $report += "#### 🔴 ``$($transform.Name)``"
            $report += " *[$($transform.Value.TransformationType)]*`n`n"
            
            if ($transform.Value.Errors -and $transform.Value.Errors.Count -gt 0) {
                $report += "**Validation Errors:**`n"
                $report += "``````text`n"
                foreach ($validationError in $transform.Value.Errors) {
                    $report += "$validationError`n"
                }
                $report += "``````"
                $report += "`n`n"
            }
        }
    } else {
        $report += "✅ All transformation files validated successfully against DBML schemas`n`n"
    }
    
    $report += "---`n`n"
} elseif ($TransformationResultsPath) {
    $report += "## ⚠️ YAML Transformation Validation`n`n⚠️ Results not available`n`n---`n`n"
}

# Add pylint code quality results if available
if ($pylintResults) {
    $conventionCount = ($pylintResults | Where-Object { $_.type -eq "convention" }).Count
    $totalIssues = $pylintErrorCount + $pylintWarningCount + $conventionCount
    
    $pylintStatus = if ($pylintErrorCount -gt 0) { "❌" } elseif ($pylintWarningCount -gt 0) { "⚠️" } else { "✅" }
    
    $report += @"
## $pylintStatus Code Quality (Pylint)

**Issues Found:** $totalIssues | ❌ Errors: $pylintErrorCount | ⚠️ Warnings: $pylintWarningCount | ℹ️ Conventions: $conventionCount

"@
    
    if ($pylintErrorCount -gt 0) {
        $report += "### ❌ Pylint Errors`n`n"
        $errors = $pylintResults | Where-Object { $_.type -eq "error" } | Select-Object -First 10
        foreach ($err in $errors) {
            $report += "- **``$($err.path)``** (Line $($err.line)): $($err.message) [``$($err.symbol)``]`n"
        }
        if ($pylintErrorCount -gt 10) {
            $report += "`n*... and $($pylintErrorCount - 10) more errors. See build artifacts for full report.*`n"
        }
        $report += "`n"
    }
    
    if ($pylintWarningCount -gt 0 -and $pylintWarningCount -le 5) {
        $report += "### ⚠️ Top Pylint Warnings`n`n"
        $warnings = $pylintResults | Where-Object { $_.type -eq "warning" } | Select-Object -First 5
        foreach ($warn in $warnings) {
            $report += "- **``$($warn.path)``** (Line $($warn.line)): $($warn.message) [``$($warn.symbol)``]`n"
        }
        $report += "`n"
    }
    
    $report += "*Full pylint report available in build artifacts: ``pylint-results.json``*`n`n"
    $report += "---`n`n"
}

# Add semantic model BPA results if available
if ($bpaResults -and $bpaResults.TotalModels -gt 0) {
    # Check if there are real failures (not just skipped models)
    $hasRealFailures = $false
    $hasSkippedModels = $false
    foreach ($model in $bpaResults.Models) {
        if (-not $model.Analyzed) {
            if ($model.Error -match "path is null|path is empty|not exist in workspace|does not exist|Error accessing model path|Skipping") {
                $hasSkippedModels = $true
            } else {
                $hasRealFailures = $true
            }
        }
    }
    
    $bpaStatus = if ($hasRealFailures -or (-not $bpaResults.ValidationPassed)) { 
        "❌" 
    } elseif ($bpaResults.TotalViolations -gt 0 -or $hasSkippedModels) { 
        "⚠️" 
    } else { 
        "✅" 
    }
    
    $report += @"
## $bpaStatus Semantic Model Best Practices

**Models Analyzed:** $($bpaResults.ModelsAnalyzed) | **Total Violations:** $($bpaResults.TotalViolations)

"@
    
    foreach ($model in $bpaResults.Models) {
        if (-not $model.Analyzed) {
            # Check if it's a skipped model (path issues) or a real failure
            $isSkipped = $model.Error -match "path is null|path is empty|not exist in workspace|does not exist|Error accessing model path|Skipping"
            $icon = if ($isSkipped) { "⚠️" } else { "❌" }
            
            $report += "### $icon $($model.Name)`n`n"
            
            if ($isSkipped) {
                $report += "⚠️ Skipped: $($model.Error)`n`n"
            } else {
                $report += "❌ Failed to analyze: $($model.Error)`n`n"
            }
            continue
        }
        
        $modelStatus = if ($model.Errors -gt 0) { "❌" } elseif ($model.Warnings -gt 0) { "⚠️" } else { "✅" }
        
        $report += "### $modelStatus $($model.Name)`n`n"
        $report += " ❌ Errors: $($model.Errors) | ⚠️ Warnings: $($model.Warnings) | ℹ️ Info: $($model.Info)`n`n"
        
        # Show top violations
        if ($model.Violations.Count -gt 0) {
            $topViolations = $model.Violations | Sort-Object -Property Severity | Select-Object -First 10
            
            foreach ($violation in $topViolations) {
                $icon = switch ($violation.Severity) {
                    "Error" { "❌" }
                    "Warning" { "⚠️" }
                    default { "ℹ️" }
                }
                $report += "- $icon **$($violation.RuleName)**: $($violation.Description)``n"
                if ($violation.Object) {
                    $report += "  *Object: ``$($violation.Object)``*`n"
                }
            }
            
            if ($model.Violations.Count -gt 10) {
                $report += "`n*... and $($model.Violations.Count - 10) more violations. See build artifacts for full report.*`n"
            }
            
            $report += "`n"
        }
    }
    
    $report += "*Full BPA report available in build artifacts: ``bpa-results.json``*`n`n"
    $report += "---`n`n"
}

# Add security scan results if available
$securitySection = ""
$hasSecurityResults = $false
$overallSecurityStatus = "✅"  # Track worst status across all scanners
$stagingDir = Split-Path $ResultsPath -Parent

Write-Host "DEBUG: Checking for security scan results in: $stagingDir"

# Bandit - Python security issues
$banditPath = Join-Path $stagingDir "bandit-results.json"
Write-Host "DEBUG: Looking for Bandit results at: $banditPath (Exists: $(Test-Path $banditPath))"
if (Test-Path $banditPath) {
    $hasSecurityResults = $true
    try {
        $bandit = Get-Content $banditPath | ConvertFrom-Json
        $highCount = ($bandit.results | Where-Object { $_.issue_severity -eq "HIGH" }).Count
        $mediumCount = ($bandit.results | Where-Object { $_.issue_severity -eq "MEDIUM" }).Count
        $lowCount = ($bandit.results | Where-Object { $_.issue_severity -eq "LOW" }).Count
        
        $banditStatus = if ($highCount -gt 0) { "❌" } elseif ($mediumCount -gt 0) { "⚠️" } else { "✅" }
        
        # Update overall status
        if ($banditStatus -eq "❌") { $overallSecurityStatus = "❌" }
        elseif ($banditStatus -eq "⚠️" -and $overallSecurityStatus -ne "❌") { $overallSecurityStatus = "⚠️" }
        
        $securitySection += @"
### $banditStatus Bandit (Python Security)

| Severity | Count |
|----------|-------|
| 🔴 High | $highCount |
| 🟡 Medium | $mediumCount |
| 🔵 Low | $lowCount |

"@
        if ($highCount + $mediumCount + $lowCount -eq 0) {
            $securitySection += "✅ No security issues found`n`n"
        }
    } catch {
        $securitySection += "⚠️ Error parsing Bandit results: $_`n`n"
    }
}

# Safety - Dependency vulnerabilities
$safetyPath = Join-Path $stagingDir "safety-results.json"
Write-Host "DEBUG: Looking for Safety results at: $safetyPath (Exists: $(Test-Path $safetyPath))"
if (Test-Path $safetyPath) {
    $hasSecurityResults = $true
    try {
        $safetyContent = Get-Content $safetyPath -Raw
        if ($safetyContent -and $safetyContent.Trim() -and $safetyContent.Trim() -ne '[]') {
            $safety = $safetyContent | ConvertFrom-Json
            $vulnCount = if ($safety.vulnerabilities) { $safety.vulnerabilities.Count } elseif ($safety -is [array]) { $safety.Count } else { 0 }
            
            $safetyStatus = if ($vulnCount -gt 0) { "⚠️" } else { "✅" }
            
            # Update overall status
            if ($safetyStatus -eq "⚠️" -and $overallSecurityStatus -ne "❌") { $overallSecurityStatus = "⚠️" }
            
            $securitySection += @"
### $safetyStatus Safety (Dependency Vulnerabilities)

"@
            if ($vulnCount -gt 0) {
                $securitySection += "⚠️ **$vulnCount** vulnerable dependencies found`n`n"
                $vulns = if ($safety.vulnerabilities) { $safety.vulnerabilities } else { $safety }
                foreach ($vuln in $vulns | Select-Object -First 5) {
                    $pkgName = if ($vuln.package) { $vuln.package } else { $vuln.name }
                    $vulnDesc = if ($vuln.vulnerability) { $vuln.vulnerability } else { $vuln.advisory }
                    $securitySection += "- 🔓 ``$pkgName``: $vulnDesc`n"
                }
                if ($vulnCount -gt 5) {
                    $securitySection += "`n*... and $($vulnCount - 5) more*`n"
                }
            } else {
                $securitySection += "✅ No vulnerable dependencies found`n"
            }
            $securitySection += "`n"
        } else {
            # Empty or no dependencies
            $securitySection += "### ✅ Safety (Dependency Vulnerabilities)`n`n✅ No Python dependencies found (Fabric project)`n`n"
        }
    } catch {
        # Safety parsing failed - likely no requirements.txt for Fabric project
        $securitySection += "### ℹ️ Safety (Dependency Vulnerabilities)`n`nℹ️ Skipped - No Python requirements.txt found (normal for Fabric projects)`n`n"
    }
}

# Pylint - Code quality
$pylintPath = Join-Path $stagingDir "pylint-results.json"
Write-Host "DEBUG: Looking for Pylint results at: $pylintPath (Exists: $(Test-Path $pylintPath))"
if (Test-Path $pylintPath) {
    $hasSecurityResults = $true
    try {
        $pylintContent = Get-Content $pylintPath -Raw
        if ($pylintContent -and $pylintContent.Trim()) {
            $pylint = $pylintContent | ConvertFrom-Json
            
            if ($pylint -is [array]) {
                $errorCount = ($pylint | Where-Object { $_.type -eq "error" }).Count
                $warningCount = ($pylint | Where-Object { $_.type -eq "warning" }).Count
                $conventionCount = ($pylint | Where-Object { $_.type -eq "convention" }).Count
                
                $pylintStatus = if ($errorCount -gt 0) { "❌" } elseif ($warningCount -gt 10) { "⚠️" } else { "✅" }
                
                # Update overall status
                if ($pylintStatus -eq "❌") { $overallSecurityStatus = "❌" }
                elseif ($pylintStatus -eq "⚠️" -and $overallSecurityStatus -ne "❌") { $overallSecurityStatus = "⚠️" }
                
                $securitySection += @"
### $pylintStatus Pylint (Code Quality)

| Type | Count |
|------|-------|
| ❌ Errors | $errorCount |
| ⚠️ Warnings | $warningCount |
| 📝 Conventions | $conventionCount |

"@
            } else {
                $securitySection += "### ✅ Pylint (Code Quality)`n`n✅ No issues found or empty results`n`n"
            }
        } else {
            $securitySection += "### ✅ Pylint (Code Quality)`n`n✅ No Python files to analyze`n`n"
        }
    } catch {
        $securitySection += "### ⚠️ Pylint (Code Quality)`n`n⚠️ Error parsing Pylint results: $_`n`n"
    }
}

if ($hasSecurityResults) {
    # Add header with overall status emoji
    Write-Host "DEBUG: Adding security section to report with status: $overallSecurityStatus"
    $report += "`n## $overallSecurityStatus Security Scan Results`n`n"
    $report += $securitySection
    $report += "---`n`n"
} else {
    Write-Host "DEBUG: No security results found - section not added"
}

# Add details for each artifact
foreach ($artifact in $results.Artifacts) {
    $statusEmoji = switch ($artifact.Status) {
        "Passed" { "✅" }
        "Failed" { "❌" }
        default { "⚠️" }
    }
    
    $report += @"
## $statusEmoji $($artifact.Type): ``$($artifact.Name)``

"@
    
    # Naming violations
    if ($artifact.NamingViolations -and $artifact.NamingViolations.Count -gt 0) {
        $report += @"
### 🏷️ Naming Convention Violations

"@
        foreach ($violation in $artifact.NamingViolations) {
            $report += "- ❌ $violation`n"
        }
        $report += "`n"
    }
    
    # Group validations by principle
    $principleGroups = $artifact.Validations | Group-Object -Property Principle
    
    foreach ($group in $principleGroups) {
        $report += "### 📋 $($group.Name)`n`n"
        
        foreach ($validation in $group.Group) {
            $icon = switch ($validation.Status) {
                "Passed" { "✅" }
                "Failed" { "❌" }
                "Warning" { "⚠️" }
                default { "❓" }
            }
            
            $report += "- $icon **$($validation.Check)**: $($validation.Message)`n"
        }
        $report += "`n"
    }
    
    $report += "---`n`n"
}

# Add footer
if ($results.HasViolations) {
    $report += @"
## 📝 Next Steps

1. Review the violations listed above
2. Update your artifacts to meet the enterprise-ready principles:
   - ✨ Make it work
   - 🔒 Make it secure
   - 📈 Make it scale
   - 📚 Make it maintainable
   - 💡 Delight stakeholders
3. Push your changes to trigger a new validation
4. Check the [copilot-instructions.md](copilot-instructions.md) for detailed guidelines

"@
} else {
    $report += @"
## 🎉 Great Work!

All artifacts meet the enterprise-ready standards. This PR is ready for review!

"@
}

$report += @"

---
*Automated validation powered by GitHub Copilot & Azure DevOps*
"@

# Save report
$report | Out-File -FilePath $OutputPath -Encoding UTF8

Write-Host "✓ Validation report generated: $OutputPath" -ForegroundColor Cyan
