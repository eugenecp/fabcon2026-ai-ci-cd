# Validate DBML (Database Markup Language) Files
# Checks DBML schemas against enterprise-ready principles

param(
    [Parameter(Mandatory=$true)]
    [string]$Path,
    
    [Parameter(Mandatory=$true)]
    [string]$Name,
    
    [Parameter(Mandatory=$false)]
    [string]$Layer = ""
)

Write-Host "Validating DBML: $Name" -ForegroundColor Yellow

$validations = @()

# ============================================================================
# MAKE IT WORK: Syntax and Structure Validation
# ============================================================================

# Check if DBML file exists
if (-not (Test-Path $Path)) {
    $validations += @{
        Principle = "MakeItWork"
        Check = "DBML file exists"
        Status = "Failed"
        Message = "DBML file not found at path: $Path"
    }
    
    # Return early if file doesn't exist
    return $validations | ConvertTo-Json -Depth 5
}

$validations += @{
    Principle = "MakeItWork"
    Check = "DBML file exists"
    Status = "Passed"
    Message = "DBML file found"
}

$content = Get-Content $Path -Raw

# Check if file is not empty
if ($content -match "^\s*$") {
    $validations += @{
        Principle = "MakeItWork"
        Check = "Not empty"
        Status = "Failed"
        Message = "DBML file is empty"
    }
    return $validations | ConvertTo-Json -Depth 5
}

$validations += @{
    Principle = "MakeItWork"
    Check = "Not empty"
    Status = "Passed"
    Message = "DBML file has content"
}

# Check for Project declaration
if ($content -match "Project\s+\w+\s*\{") {
    $validations += @{
        Principle = "MakeItWork"
        Check = "Has Project declaration"
        Status = "Passed"
        Message = "Project block found"
    }
} else {
    $validations += @{
        Principle = "MakeItWork"
        Check = "Has Project declaration"
        Status = "Failed"
        Message = "Missing Project declaration block"
    }
}

# Check for at least one Table definition
if ($content -match "Table\s+[\w\.]+\s*\{") {
    $validations += @{
        Principle = "MakeItWork"
        Check = "Has Table definitions"
        Status = "Passed"
        Message = "Table definitions found"
    }
} else {
    $validations += @{
        Principle = "MakeItWork"
        Check = "Has Table definitions"
        Status = "Failed"
        Message = "No Table definitions found"
    }
}

# Validate DBML syntax using @dbml/cli (if available)
$dbmlCliPath = Get-Command dbml2sql -ErrorAction SilentlyContinue
if ($dbmlCliPath) {
    try {
        # Attempt to parse DBML to SQL (syntax validation)
        $tempSql = [System.IO.Path]::GetTempFileName()
        $parseResult = & dbml2sql $Path --postgres 2>&1
        
        if ($LASTEXITCODE -eq 0) {
            $validations += @{
                Principle = "MakeItWork"
                Check = "DBML syntax valid"
                Status = "Passed"
                Message = "DBML syntax validated successfully with @dbml/cli"
            }
        } else {
            $errorMsg = $parseResult -join "; "
            $validations += @{
                Principle = "MakeItWork"
                Check = "DBML syntax valid"
                Status = "Failed"
                Message = "DBML syntax errors detected: $errorMsg"
            }
        }
        
        # Clean up temp file
        if (Test-Path $tempSql) { Remove-Item $tempSql -Force }
    }
    catch {
        $validations += @{
            Principle = "MakeItWork"
            Check = "DBML syntax valid"
            Status = "Warning"
            Message = "Could not validate syntax with @dbml/cli: $($_.Exception.Message)"
        }
    }
} else {
    $validations += @{
        Principle = "MakeItWork"
        Check = "DBML syntax valid"
        Status = "Warning"
        Message = "@dbml/cli not installed - syntax validation skipped (install with: npm install -g @dbml/cli)"
    }
}

# ============================================================================
# MAKE IT SECURE: Security Best Practices
# ============================================================================

# Check for hardcoded credentials in connection strings or notes
$securityPatterns = @(
    @{ Pattern = "password\s*[=:]\s*['`"][^'`"]+['`"]"; Message = "Hardcoded password detected" }
    @{ Pattern = "pwd\s*[=:]\s*['`"][^'`"]+['`"]"; Message = "Hardcoded password (pwd) detected" }
    @{ Pattern = "connectionstring\s*[=:]\s*['`"][^'`"]*password[^'`"]+['`"]"; Message = "Connection string with password detected" }
    @{ Pattern = "secret\s*[=:]\s*['`"][^'`"]+['`"]"; Message = "Hardcoded secret detected" }
    @{ Pattern = "api[_-]?key\s*[=:]\s*['`"][^'`"]+['`"]"; Message = "Hardcoded API key detected" }
    @{ Pattern = "access[_-]?token\s*[=:]\s*['`"][^'`"]+['`"]"; Message = "Hardcoded access token detected" }
)

$securityViolations = @()
foreach ($pattern in $securityPatterns) {
    if ($content -match $pattern.Pattern) {
        $securityViolations += $pattern.Message
    }
}

if ($securityViolations.Count -gt 0) {
    $validations += @{
        Principle = "MakeItSecure"
        Check = "No hardcoded credentials"
        Status = "Failed"
        Message = "Security violations found: $($securityViolations -join '; ')"
    }
} else {
    $validations += @{
        Principle = "MakeItSecure"
        Check = "No hardcoded credentials"
        Status = "Passed"
        Message = "No hardcoded credentials detected"
    }
}

# ============================================================================
# MAKE IT SCALE: Performance and Optimization
# ============================================================================

# Check for primary keys on tables
$tableBlocks = [regex]::Matches($content, "Table\s+([\w\.]+)\s*\{([^\}]+)\}", [System.Text.RegularExpressions.RegexOptions]::Singleline)
$tablesWithoutPK = @()

foreach ($table in $tableBlocks) {
    $tableName = $table.Groups[1].Value
    $tableContent = $table.Groups[2].Value
    
    if ($tableContent -notmatch "\[.*\bpk\b.*\]") {
        $tablesWithoutPK += $tableName
    }
}

if ($tablesWithoutPK.Count -gt 0) {
    $validations += @{
        Principle = "MakeItScale"
        Check = "Primary keys defined"
        Status = "Warning"
        Message = "Tables without primary keys: $($tablesWithoutPK -join ', ')"
    }
} else {
    $validations += @{
        Principle = "MakeItScale"
        Check = "Primary keys defined"
        Status = "Passed"
        Message = "All tables have primary keys defined"
    }
}

# Check for indexes on foreign key columns
if ($content -match "Indexes\s*\{") {
    $validations += @{
        Principle = "MakeItScale"
        Check = "Has index definitions"
        Status = "Passed"
        Message = "Index definitions found"
    }
} else {
    $validations += @{
        Principle = "MakeItScale"
        Check = "Has index definitions"
        Status = "Warning"
        Message = "No index definitions found - consider adding indexes for performance"
    }
}

# Check for relationships (foreign keys)
if ($content -match "Ref:.*>") {
    $validations += @{
        Principle = "MakeItScale"
        Check = "Has relationships defined"
        Status = "Passed"
        Message = "Table relationships (Ref) defined"
    }
} else {
    $validations += @{
        Principle = "MakeItScale"
        Check = "Has relationships defined"
        Status = "Warning"
        Message = "No table relationships found - verify if relationships exist"
    }
}

# ============================================================================
# MAKE IT MAINTAINABLE: Documentation and Standards
# ============================================================================

# Check for Project Note (overall documentation)
if ($content -match "Project\s+\w+\s*\{[^\}]*Note:") {
    $validations += @{
        Principle = "MakeItMaintainable"
        Check = "Has Project documentation"
        Status = "Passed"
        Message = "Project Note documentation found"
    }
} else {
    $validations += @{
        Principle = "MakeItMaintainable"
        Check = "Has Project documentation"
        Status = "Failed"
        Message = "Missing Project Note - add documentation describing the schema purpose"
    }
}

# Check for Table Notes (table-level documentation)
$tablesWithoutNotes = @()
foreach ($table in $tableBlocks) {
    $tableName = $table.Groups[1].Value
    $tableContent = $table.Groups[2].Value
    
    if ($tableContent -notmatch "Note:\s*['\`"]") {
        $tablesWithoutNotes += $tableName
    }
}

if ($tablesWithoutNotes.Count -gt 0) {
    $validations += @{
        Principle = "MakeItMaintainable"
        Check = "Tables have documentation"
        Status = "Failed"
        Message = "Tables without Note documentation: $($tablesWithoutNotes -join ', ')"
    }
} else {
    $validations += @{
        Principle = "MakeItMaintainable"
        Check = "Tables have documentation"
        Status = "Passed"
        Message = "All tables have Note documentation"
    }
}

# Check for column notes with Source/Transformation metadata
$columnNotesPattern = [regex]::Matches($content, "note:\s*'([^']*)'", [System.Text.RegularExpressions.RegexOptions]::IgnoreCase)
$columnsWithMetadata = 0
$columnsWithoutMetadata = 0

foreach ($note in $columnNotesPattern) {
    $noteContent = $note.Groups[1].Value
    if ($noteContent -match "Source:|Transformation:|Conformance:") {
        $columnsWithMetadata++
    } else {
        $columnsWithoutMetadata++
    }
}

$totalColumns = $columnsWithMetadata + $columnsWithoutMetadata
if ($totalColumns -gt 0) {
    $metadataPercentage = [math]::Round(($columnsWithMetadata / $totalColumns) * 100, 1)
    
    if ($metadataPercentage -ge 80) {
        $validations += @{
            Principle = "MakeItMaintainable"
            Check = "Column notes include metadata"
            Status = "Passed"
            Message = "$metadataPercentage% of columns have Source/Transformation/Conformance metadata"
        }
    } elseif ($metadataPercentage -ge 50) {
        $validations += @{
            Principle = "MakeItMaintainable"
            Check = "Column notes include metadata"
            Status = "Warning"
            Message = "Only $metadataPercentage% of columns have Source/Transformation/Conformance metadata (target: 80%+)"
        }
    } else {
        $validations += @{
            Principle = "MakeItMaintainable"
            Check = "Column notes include metadata"
            Status = "Failed"
            Message = "Only $metadataPercentage% of columns have Source/Transformation/Conformance metadata (target: 80%+)"
        }
    }
} else {
    $validations += @{
        Principle = "MakeItMaintainable"
        Check = "Column notes include metadata"
        Status = "Warning"
        Message = "No column notes found"
    }
}

# Check for consistent naming (schema prefix)
$tablesWithSchema = [regex]::Matches($content, "Table\s+[\w]+\.[\w]+\s*\{").Count
$tablesWithoutSchema = [regex]::Matches($content, "Table\s+[a-zA-Z_][\w]*\s+\{").Count

if ($tablesWithSchema -gt 0 -and $tablesWithoutSchema -eq 0) {
    $validations += @{
        Principle = "MakeItMaintainable"
        Check = "Consistent table naming"
        Status = "Passed"
        Message = "All tables use schema prefix (e.g., bronze.table_name)"
    }
} elseif ($tablesWithSchema -eq 0 -and $tablesWithoutSchema -gt 0) {
    $validations += @{
        Principle = "MakeItMaintainable"
        Check = "Consistent table naming"
        Status = "Passed"
        Message = "Tables use consistent naming without schema prefix"
    }
} else {
    $validations += @{
        Principle = "MakeItMaintainable"
        Check = "Consistent table naming"
        Status = "Warning"
        Message = "Inconsistent table naming - some tables have schema prefix, others don't (With schema: $tablesWithSchema, Without: $tablesWithoutSchema)"
    }
}

# ============================================================================
# DELIGHT STAKEHOLDERS: Data Quality and Lineage
# ============================================================================

# Check for data lineage information in notes
if ($content -match "Source:|Sources:|Origin:") {
    $validations += @{
        Principle = "DelightStakeholders"
        Check = "Has data lineage"
        Status = "Passed"
        Message = "Data lineage information found in notes"
    }
} else {
    $validations += @{
        Principle = "DelightStakeholders"
        Check = "Has data lineage"
        Status = "Warning"
        Message = "No data lineage information found - add Source: references in column/table notes"
    }
}

# Check for validation rules in notes
if ($content -match "Validation:|Constraints:") {
    $validations += @{
        Principle = "DelightStakeholders"
        Check = "Has validation rules"
        Status = "Passed"
        Message = "Validation rules documented in notes"
    }
} else {
    $validations += @{
        Principle = "DelightStakeholders"
        Check = "Has validation rules"
        Status = "Warning"
        Message = "No validation rules documented - consider adding Validation: notes"
    }
}

# Check for Not Null constraints on important columns
if ($content -match "\[.*\bnot null\b.*\]") {
    $validations += @{
        Principle = "DelightStakeholders"
        Check = "Has NOT NULL constraints"
        Status = "Passed"
        Message = "NOT NULL constraints defined for data quality"
    }
} else {
    $validations += @{
        Principle = "DelightStakeholders"
        Check = "Has NOT NULL constraints"
        Status = "Warning"
        Message = "No NOT NULL constraints found - ensure data quality constraints are defined"
    }
}

# Check for medallion layer alignment (bronze/silver/gold)
if ($Layer -ne "") {
    $expectedSchema = $Layer.ToLower()
    if ($content -match "Table\s+$expectedSchema\.") {
        $validations += @{
            Principle = "DelightStakeholders"
            Check = "Medallion layer alignment"
            Status = "Passed"
            Message = "Tables use expected schema: $expectedSchema"
        }
    } else {
        $validations += @{
            Principle = "DelightStakeholders"
            Check = "Medallion layer alignment"
            Status = "Warning"
            Message = "File is in $Layer folder but tables don't use $expectedSchema schema prefix"
        }
    }
}

# ============================================================================
# Return Results
# ============================================================================

return $validations | ConvertTo-Json -Depth 5
