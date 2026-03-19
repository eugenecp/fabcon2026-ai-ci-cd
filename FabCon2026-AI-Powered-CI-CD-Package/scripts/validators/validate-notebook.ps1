# Validate Notebook Artifacts
# Checks notebooks against enterprise-ready principles

param(
    [Parameter(Mandatory=$true)]
    [string]$Path,
    
    [Parameter(Mandatory=$true)]
    [string]$Name
)

Write-Host "Validating Notebook: $Name" -ForegroundColor Yellow

$validations = @()

# MakeItWork: Check if notebook file exists (Python or Scala)
$pythonFile = Join-Path $Path "notebook-content.py"
$scalaFile = Join-Path $Path "notebook-content.scala"
$notebookFile = $null
$notebookLanguage = $null

if (Test-Path $pythonFile) {
    $notebookFile = $pythonFile
    $notebookLanguage = "Python"
} elseif (Test-Path $scalaFile) {
    $notebookFile = $scalaFile
    $notebookLanguage = "Scala"
}

if (-not $notebookFile) {
    $validations += @{
        Principle = "MakeItWork"
        Check = "Notebook file exists"
        Status = "Failed"
        Message = "Neither notebook-content.py nor notebook-content.scala found"
    }
    
    # Return early if file doesn't exist
    return $validations | ConvertTo-Json -Depth 5
}

$validations += @{
    Principle = "MakeItWork"
    Check = "Notebook file exists"
    Status = "Passed"
    Message = "$(Split-Path -Leaf $notebookFile) found ($notebookLanguage)"
}

$content = Get-Content $notebookFile -Raw

# MakeItWork: Check for basic language structure
if ($notebookLanguage -eq "Python") {
    $hasImports = $content -match "import|from\s+\w+\s+import"
} else {
    # Scala uses import statements
    $hasImports = $content -match "import\s+\w+"
}

if ($hasImports) {
    $validations += @{
        Principle = "MakeItWork"
        Check = "Has import statements"
        Status = "Passed"
        Message = "Import statements found"
    }
} else {
    $validations += @{
        Principle = "MakeItWork"
        Check = "Has import statements"
        Status = "Warning"
        Message = "No import statements found - may be empty or incomplete"
    }
}

# MakeItWork: Check for syntax errors (basic check)
if ($content -match "^\\s*$") {
    $validations += @{
        Principle = "MakeItWork"
        Check = "Not empty"
        Status = "Failed"
        Message = "Notebook is empty"
    }
} else {
    $validations += @{
        Principle = "MakeItWork"
        Check = "Not empty"
        Status = "Passed"
        Message = "Notebook has content"
    }
}

# MakeItMaintainable: Check for description in .platform file
$platformFile = Join-Path $Path ".platform"
if (Test-Path $platformFile) {
    try {
        $platform = Get-Content $platformFile -Raw | ConvertFrom-Json
        if ($platform.metadata.description -and $platform.metadata.description.Trim() -ne "") {
            $validations += @{
                Principle = "MakeItMaintainable"
                Check = "Has description"
                Status = "Passed"
                Message = "Description found in .platform file"
            }
        } else {
            $validations += @{
                Principle = "MakeItMaintainable"
                Check = "Has description"
                Status = "Failed"
                Message = "Add description in .platform metadata.description field"
            }
        }
        
        # Check if display name matches folder name
        $folderName = $Name -replace '\.Notebook$', ''
        $displayName = $platform.metadata.displayName
        
        if ($displayName -eq $folderName) {
            $validations += @{
                Principle = "MakeItMaintainable"
                Check = "Display name matches folder name"
                Status = "Passed"
                Message = "Display name '$displayName' matches folder name"
            }
        } else {
            $validations += @{
                Principle = "MakeItMaintainable"
                Check = "Display name matches folder name"
                Status = "Failed"
                Message = "Display name '$displayName' does not match folder name '$folderName' - update .platform metadata.displayName"
            }
        }
    } catch {
        $validations += @{
            Principle = "MakeItMaintainable"
            Check = "Has description"
            Status = "Warning"
            Message = "Could not parse .platform file for description"
        }
    }
} else {
    $validations += @{
        Principle = "MakeItMaintainable"
        Check = "Has description"
        Status = "Warning"
        Message = ".platform file not found"
    }
}

# MakeItMaintainable: Check for lakehouse configuration pattern
# Notebooks should use %%configure magic cell with parameterization, not default_lakehouse in metadata
$hasConfigureCell = $content -match "# MAGIC %%configure|%%configure"
$hasDefaultLakehouse = $content -match "default_lakehouse"
$hasParameterization = $content -match '"parameterName"'

if ($hasConfigureCell -and $hasParameterization -and -not $hasDefaultLakehouse) {
    $validations += @{
        Principle = "MakeItMaintainable"
        Check = "Lakehouse configuration"
        Status = "Passed"
        Message = "Uses parameterized %%configure magic cell for dynamic lakehouse configuration"
    }
} elseif ($hasConfigureCell -and -not $hasParameterization -and -not $hasDefaultLakehouse) {
    $validations += @{
        Principle = "MakeItMaintainable"
        Check = "Lakehouse configuration"
        Status = "Warning"
        Message = "Uses %%configure cell but hardcodes lakehouse name - consider using parameterName for pipeline flexibility"
    }
} elseif ($hasConfigureCell -and $hasDefaultLakehouse) {
    $validations += @{
        Principle = "MakeItMaintainable"
        Check = "Lakehouse configuration"
        Status = "Warning"
        Message = "Has %%configure cell but also has default_lakehouse in metadata - remove metadata defaults"
    }
} elseif (-not $hasConfigureCell -and $hasDefaultLakehouse) {
    $validations += @{
        Principle = "MakeItMaintainable"
        Check = "Lakehouse configuration"
        Status = "Failed"
        Message = "Uses default_lakehouse metadata - should use %%configure magic cell instead"
    }
} else {
    $validations += @{
        Principle = "MakeItMaintainable"
        Check = "Lakehouse configuration"
        Status = "Warning"
        Message = "No lakehouse configuration found - add %%configure cell if lakehouse is needed"
    }
}

# MakeItSecure: Check for hardcoded credentials
$securityIssues = @()
if ($content -match "(?i)(password|pwd|secret|key|token)\\s*=\\s*") {
    $securityIssues += "Potential hardcoded credentials (password/key/token)"
}
if ($content -match "(?i)(AccountKey|ConnectionString|AccessKey)\\s*=\\s*") {
    $securityIssues += "Potential hardcoded connection strings"
}
if ($content -match "(?i)(api[_-]?key|apikey)\\s*=\\s*[A-Za-z0-9]{20,}") {
    $securityIssues += "Potential hardcoded API key"
}

if ($securityIssues.Count -eq 0) {
    $validations += @{
        Principle = "MakeItSecure"
        Check = "No hardcoded credentials"
        Status = "Passed"
        Message = "No obvious security violations found"
    }
} else {
    $validations += @{
        Principle = "MakeItSecure"
        Check = "No hardcoded credentials"
        Status = "Failed"
        Message = ($securityIssues -join "; ")
    }
}

# MakeItSecure: Check for SQL injection risks
# Simplified check for string formatting in SQL queries
$sqlInjectionRisk = $false
if ($content -match "%s|%d" -and $content -match "(?i)(SELECT|INSERT|UPDATE|DELETE|EXECUTE)") {
    $sqlInjectionRisk = $true
}
if ($content -match "(?i)\.format\(" -and $content -match "(?i)(SELECT|INSERT|UPDATE|DELETE)") {
    $sqlInjectionRisk = $true
}
if ($content -match "(?i)f[`"'].*SELECT|f[`"'].*INSERT|f[`"'].*UPDATE|f[`"'].*DELETE") {
    $sqlInjectionRisk = $true
}

if ($sqlInjectionRisk) {
    $validations += @{
        Principle = "MakeItSecure"
        Check = "SQL injection prevention"
        Status = "Warning"
        Message = "Possible SQL injection risk detected - verify parameterized queries are used"
    }
} else {
    $validations += @{
        Principle = "MakeItSecure"
        Check = "SQL injection prevention"
        Status = "Passed"
        Message = "No obvious SQL injection patterns detected"
    }
}

# MakeItScale: Check for optimization patterns
$optimizationPatterns = @()
if ($content -match "(?i)repartition|coalesce") {
    $optimizationPatterns += "Partitioning"
}
if ($content -match "(?i)cache|persist") {
    $optimizationPatterns += "Caching"
}
if ($content -match "(?i)optimize|z-?order|vacuum") {
    $optimizationPatterns += "Delta optimization"
}
if ($content -match "(?i)broadcast|partition") {
    $optimizationPatterns += "Distribution strategy"
}

# Check if this is a reference/lookup data notebook (small datasets don't need optimization)
# Look for "Reference" in notebook name OR content mentions reference/lookup data
$isReferenceData = ($Name -match "(?i)reference|lookup") -or 
                   ($content -match "(?i)# Download.*Reference|# Create.*Reference|lookup.*table")

if ($optimizationPatterns.Count -gt 0) {
    $validations += @{
        Principle = "MakeItScale"
        Check = "Uses optimization patterns"
        Status = "Passed"
        Message = "Found: $($optimizationPatterns -join ', ')"
    }
} elseif ($isReferenceData) {
    $validations += @{
        Principle = "MakeItScale"
        Check = "Uses optimization patterns"
        Status = "Passed"
        Message = "Reference/lookup data - optimization patterns not required for small datasets"
    }
} else {
    $validations += @{
        Principle = "MakeItScale"
        Check = "Uses optimization patterns"
        Status = "Warning"
        Message = "Consider adding partition/optimization strategies for large datasets"
    }
}

# MakeItScale: Check for incremental loading
if ($content -match "(?i)(incremental|watermark|last_?modified|delta|merge)") {
    $validations += @{
        Principle = "MakeItScale"
        Check = "Incremental loading pattern"
        Status = "Passed"
        Message = "Incremental/delta loading patterns detected"
    }
} else {
    $validations += @{
        Principle = "MakeItScale"
        Check = "Incremental loading pattern"
        Status = "Warning"
        Message = "Consider incremental loading instead of full refresh"
    }
}

# MakeItMaintainable: Check for documentation in markdown cells
# Notebooks should have markdown cells describing Purpose, Input/Data Source, Output/Target
# Support both Python (# MARKDOWN) and Scala (// MARKDOWN) comment syntax
$hasMarkdown = $content -match "# MARKDOWN" -or $content -match "// MARKDOWN"
$hasPurpose = $content -match "\*\*Purpose\*\*"
$hasDataSource = $content -match "\*\*Data Source\*\*"
$hasTarget = $content -match "\*\*Target\*\*|\*\*Output\*\*"

if ($hasMarkdown -and ($hasPurpose -or $hasDataSource) -and $hasTarget) {
    $validations += @{
        Principle = "MakeItMaintainable"
        Check = "Has documentation markdown"
        Status = "Passed"
        Message = "Markdown documentation with Purpose/Data Source/Target found"
    }
} else {
    $validations += @{
        Principle = "MakeItMaintainable"
        Check = "Has documentation markdown"
        Status = "Failed"
        Message = "Missing markdown documentation - add markdown cell with Purpose, Data Source, Target"
    }
}

# MakeItMaintainable: Check for functions with docstrings
$functionCount = ([regex]::Matches($content, "def\\s+\\w+")).Count
$docstringCount = ([regex]::Matches($content, "def\\s+\\w+.*:\\s+`"`"`"")).Count

if ($functionCount -gt 0) {
    if ($docstringCount -ge $functionCount * 0.8) {
        $validations += @{
            Principle = "MakeItMaintainable"
            Check = "Functions have docstrings"
            Status = "Passed"
            Message = "$docstringCount of $functionCount functions have docstrings"
        }
    } else {
        $validations += @{
            Principle = "MakeItMaintainable"
            Check = "Functions have docstrings"
            Status = "Warning"
            Message = "Only $docstringCount of $functionCount functions have docstrings"
        }
    }
} else {
    $validations += @{
        Principle = "MakeItMaintainable"
        Check = "Functions have docstrings"
        Status = "Passed"
        Message = "No functions defined or inline code"
    }
}

# MakeItMaintainable: Check for meaningful variable names
if ($content -match "\\b(x|y|z|temp|tmp|data1|data2|df1|df2)\\b") {
    $validations += @{
        Principle = "MakeItMaintainable"
        Check = "Meaningful variable names"
        Status = "Warning"
        Message = "Consider using more descriptive variable names (avoid x, temp, df1, etc.)"
    }
} else {
    $validations += @{
        Principle = "MakeItMaintainable"
        Check = "Meaningful variable names"
        Status = "Passed"
        Message = "Variable names appear descriptive"
    }
}

# DelightStakeholders: Check for data quality validation
$validationPatterns = @()
if ($content -match "(?i)(validate|check|verify|assert)") {
    $validationPatterns += "Validation functions"
}
if ($content -match "(?i)\\.count\\(\\)|\\.isNull\\(\\)|\\.isNotNull\\(\\)") {
    $validationPatterns += "Null checks"
}
if ($content -match "(?i)(if.*raise|raise\\s+ValueError|raise\\s+Exception)") {
    $validationPatterns += "Exception handling"
}

if ($validationPatterns.Count -gt 0) {
    $validations += @{
        Principle = "DelightStakeholders"
        Check = "Has data quality checks"
        Status = "Passed"
        Message = "Found: $($validationPatterns -join ', ')"
    }
} else {
    $validations += @{
        Principle = "DelightStakeholders"
        Check = "Has data quality checks"
        Status = "Warning"
        Message = "Add data validation to ensure quality and catch issues early"
    }
}

# DelightStakeholders: Check for logging/observability
if ($content -match "(?i)(print|logging|logger|log\\.)") {
    $validations += @{
        Principle = "DelightStakeholders"
        Check = "Has logging/output"
        Status = "Passed"
        Message = "Logging or output statements found"
    }
} else {
    $validations += @{
        Principle = "DelightStakeholders"
        Check = "Has logging/output"
        Status = "Warning"
        Message = "Add logging for better observability and troubleshooting"
    }
}

# DelightStakeholders: Check for error handling
if ($content -match "(?i)(try:|except:|finally:)") {
    $validations += @{
        Principle = "DelightStakeholders"
        Check = "Has error handling"
        Status = "Passed"
        Message = "Try/except blocks found"
    }
} else {
    $validations += @{
        Principle = "DelightStakeholders"
        Check = "Has error handling"
        Status = "Warning"
        Message = "Add try/except blocks for better error handling"
    }
}

# Return results as JSON
return $validations | ConvertTo-Json -Depth 5
