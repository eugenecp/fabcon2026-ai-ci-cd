<#
.SYNOPSIS
    Validates YAML transformation files against DBML schemas for CI/CD pipeline.

.DESCRIPTION
    Validates all YAML transformation files in specified directories against their
    source and destination DBML schemas. Designed for Azure DevOps CI/CD integration
    with proper error reporting and exit codes.

.PARAMETER TransformationsPath
    Path to the transformations directory. Defaults to "./transformations".

.PARAMETER BronzeDbmlPath
    Path to the Bronze DBML schema file. Defaults to "./dbml/bronze/bronze.dbml".

.PARAMETER SilverDbmlPath
    Path to the Silver DBML schema file. Defaults to "./dbml/silver/silver.dbml".

.PARAMETER GoldDbmlPath
    Path to the Gold DBML schema file. Defaults to "./dbml/gold/gold.dbml".

.PARAMETER OutputPath
    Optional path to save validation results as JSON.

.PARAMETER QuietMode
    Suppress progress messages. Only shows validation results and errors.

.EXAMPLE
    .\scripts\validate-transformations.ps1

.EXAMPLE
    .\scripts\validate-transformations.ps1 -OutputPath "validation-results.json"

.EXAMPLE
    .\scripts\validate-transformations.ps1 -QuietMode -OutputPath "results.json"
#>

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [string]$TransformationsPath = "./transformations",
    
    [Parameter(Mandatory = $false)]
    [string]$BronzeDbmlPath = "./dbml/bronze/bronze.dbml",
    
    [Parameter(Mandatory = $false)]
    [string]$SilverDbmlPath = "./dbml/silver/silver.dbml",
    
    [Parameter(Mandatory = $false)]
    [string]$GoldDbmlPath = "./dbml/gold/gold.dbml",
    
    [Parameter(Mandatory = $false)]
    [string]$OutputPath,
    
    [Parameter(Mandatory = $false)]
    [switch]$QuietMode
)

# Set error action preference
$ErrorActionPreference = "Stop"

<#
.SYNOPSIS
    Writes a message to the console with optional color formatting, respecting quiet mode.

.DESCRIPTION
    Helper function that outputs messages to the console during validation. When QuietMode
    is enabled, this function suppresses all output to reduce noise during CI/CD execution.
    Supports colored output for success (Green), warnings (Yellow), and errors (Red).

.PARAMETER Message
    The message text to display to the user.

.PARAMETER Color
    Optional foreground color for the message. Default is "White".
    Common values: "White", "Green", "Yellow", "Red", "Cyan"

.EXAMPLE
    Write-Message "Starting validation..." "Cyan"
    Displays a cyan-colored message if not in quiet mode.

.EXAMPLE
    Write-Message "✓ Validation passed" "Green"
    Displays a green success message if not in quiet mode.

.NOTES
    This function respects the parent script's $QuietMode switch parameter.
    In quiet mode, all messages are suppressed to allow for CI/CD integration.
#>
function Write-Message {
    param([string]$Message, [string]$Color = "White")
    if (-not $QuietMode) {
        if ($Color -ne "White") {
            Write-Host $Message -ForegroundColor $Color
        } else {
            Write-Host $Message
        }
    }
}

# Get script directory
$scriptRoot = Split-Path -Parent $MyInvocation.MyCommand.Path
$validatorScript = Join-Path (Split-Path -Parent $scriptRoot) ".github\skills\fdt\Validate-YamlSchema.ps1"

# Verify validator script exists
if (-not (Test-Path $validatorScript)) {
    Write-Host "##vso[task.logissue type=error]Validator script not found: $validatorScript"
    Write-Error "Validator script not found: $validatorScript"
    exit 1
}

# Initialize results
$results = @{
    Timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
    ValidationPassed = $true
    TotalFiles = 0
    ValidFiles = 0
    InvalidFiles = 0
    Transformations = @{}
}

# Banner
Write-Message "========================================"
Write-Message "Validating YAML Transformations"
Write-Message "========================================"
Write-Message ""

# Define transformation directories with their schema mappings
$transformationDirs = @(
    @{
        Path = Join-Path $TransformationsPath "bronze_to_silver"
        SourceDbml = $BronzeDbmlPath
        DestinationDbml = $SilverDbmlPath
        SourceSchema = "bronze"
        DestinationSchema = "silver"
        Name = "Bronze → Silver"
    }
    @{
        Path = Join-Path $TransformationsPath "silver_to_gold"
        SourceDbml = $SilverDbmlPath
        DestinationDbml = $GoldDbmlPath
        SourceSchema = "silver"
        DestinationSchema = "gold"
        Name = "Silver → Gold"
    }
)

# Process each transformation directory
foreach ($dir in $transformationDirs) {
    $dirPath = $dir.Path
    
    # Check if directory exists
    if (-not (Test-Path $dirPath)) {
        Write-Message "Skipping $($dir.Name): Directory not found at $dirPath" "Yellow"
        continue
    }
    
    # Check if DBML files exist
    if (-not (Test-Path $dir.SourceDbml)) {
        Write-Host "##vso[task.logissue type=error]Source DBML not found: $($dir.SourceDbml)"
        Write-Error "Source DBML not found: $($dir.SourceDbml)"
        exit 1
    }
    
    if (-not (Test-Path $dir.DestinationDbml)) {
        Write-Host "##vso[task.logissue type=error]Destination DBML not found: $($dir.DestinationDbml)"
        Write-Error "Destination DBML not found: $($dir.DestinationDbml)"
        exit 1
    }
    
    Write-Message "Transformation: $($dir.Name)" "Cyan"
    Write-Message "  Directory: $dirPath"
    Write-Message "  Source: $($dir.SourceDbml)"
    Write-Message "  Destination: $($dir.DestinationDbml)"
    Write-Message ""
    
    # Get all YAML files
    $yamlFiles = Get-ChildItem -Path $dirPath -Filter "*.yaml" -File | Where-Object { 
        $_.Name -notlike "*.assessment.md" 
    }
    
    if ($yamlFiles.Count -eq 0) {
        Write-Message "  No YAML files found in $dirPath" "Yellow"
        Write-Message ""
        continue
    }
    
    Write-Message "  Found $($yamlFiles.Count) YAML file(s) to validate"
    Write-Message ""
    
    # Validate each YAML file
    foreach ($yamlFile in $yamlFiles) {
        $results.TotalFiles++
        $fileName = $yamlFile.Name
        $fileResult = @{
            Path = $yamlFile.FullName
            Valid = $false
            Errors = @()
            TransformationType = $dir.Name
        }
        
        Write-Message "  Validating: $fileName"
        
        try {
            # Capture output
            $output = & $validatorScript `
                -Path $yamlFile.FullName `
                -SourceDbml $dir.SourceDbml `
                -DestinationDbml $dir.DestinationDbml `
                -SourceSchemaName $dir.SourceSchema `
                -DestinationSchemaName $dir.DestinationSchema `
                -QuietMode 2>&1
            
            if ($LASTEXITCODE -eq 0) {
                $results.ValidFiles++
                $fileResult.Valid = $true
                Write-Message "    ✓ PASSED" "Green"
            } else {
                $results.InvalidFiles++
                $results.ValidationPassed = $false
                $fileResult.Errors = @($output | Out-String)
                Write-Message "    ✗ FAILED" "Red"
                Write-Host "##vso[task.logissue type=error]Validation failed for ${fileName} in $($dir.Name)"
                
                # Show errors if not in quiet mode
                if (-not $QuietMode -and $output) {
                    $output | ForEach-Object { Write-Message "      $_" "Red" }
                }
            }
        } catch {
            $results.InvalidFiles++
            $results.ValidationPassed = $false
            $fileResult.Errors = @($_.Exception.Message)
            Write-Message "    ✗ ERROR: $($_.Exception.Message)" "Red"
            $errorMsg = $_.Exception.Message
            Write-Host "##vso[task.logissue type=error]Validation error for ${fileName}: $errorMsg"
        }
        
        $results.Transformations[$fileName] = $fileResult
        Write-Message ""
    }
}

# Summary
Write-Message "========================================"
Write-Message "Validation Summary"
Write-Message "========================================"
Write-Message "Total files:   $($results.TotalFiles)"
Write-Message "Valid files:   $($results.ValidFiles)" "Green"
Write-Message "Invalid files: $($results.InvalidFiles)" $(if ($results.InvalidFiles -eq 0) { "Green" } else { "Red" })

# Save results if output path specified
if ($OutputPath) {
    $results | ConvertTo-Json -Depth 10 | Set-Content -Path $OutputPath
    Write-Message ""
    Write-Message "Results saved to: $OutputPath"
}

# Final result
Write-Message ""
if ($results.ValidationPassed) {
    Write-Message "All YAML transformations validated successfully ✓" "Green"
    exit 0
} else {
    Write-Message "YAML transformation validation failed ✗" "Red"
    
    # List failed files
    $failedFiles = $results.Transformations.GetEnumerator() | Where-Object { -not $_.Value.Valid }
    if ($failedFiles) {
        Write-Message ""
        Write-Message "Failed files:"
        foreach ($file in $failedFiles) {
            Write-Message "  - $($file.Key) [$($file.Value.TransformationType)]" "Red"
        }
    }
    
    Write-Host "##vso[task.complete result=Failed;]YAML transformation validation failed"
    exit 1
}
