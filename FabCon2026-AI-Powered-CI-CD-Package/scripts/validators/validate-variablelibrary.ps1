# Validate Variable Library Artifacts
# Checks Variable Libraries against enterprise-ready principles

param(
    [Parameter(Mandatory=$true)]
    [string]$Path,
    
    [Parameter(Mandatory=$true)]
    [string]$Name
)

Write-Host "Validating Variable Library: $Name" -ForegroundColor Yellow

$validations = @()

# MakeItWork: Check for variables.json file
$variablesFile = Join-Path $Path "variables.json"
if (Test-Path $variablesFile) {
    $validations += @{
        Principle = "MakeItWork"
        Check = "Variables definition exists"
        Status = "Passed"
        Message = "variables.json found"
    }
    
    # MakeItWork: Validate JSON structure
    try {
        $variables = Get-Content $variablesFile -Raw | ConvertFrom-Json
        $validations += @{
            Principle = "MakeItWork"
            Check = "Valid JSON structure"
            Status = "Passed"
            Message = "variables.json is valid"
        }
        
        # Check for variables array
        if ($variables.variables) {
            $variableCount = $variables.variables.Count
            if ($variableCount -gt 0) {
                $validations += @{
                    Principle = "MakeItWork"
                    Check = "Has variables defined"
                    Status = "Passed"
                    Message = "Variable library has $variableCount variable(s)"
                }
                
                # MakeItSecure: Check for sensitive data in default values
                $sensitivePatterns = @(
                    'password',
                    'secret',
                    'key',
                    'token',
                    'connectionstring',
                    'accountkey',
                    'sas'
                )
                
                $sensitiveLowerNames = $variables.variables | Where-Object { 
                    $varNameLower = $_.name.ToLower()
                    $sensitivePatterns | Where-Object { $varNameLower -match $_ }
                }
                
                $varsWithValues = $variables.variables | Where-Object { 
                    $_.value -and $_.value -ne ""
                }
                
                if ($sensitiveLowerNames -and $varsWithValues) {
                    # Check if sensitive variables have non-empty default values
                    $sensitiveWithValues = $sensitiveLowerNames | Where-Object {
                        $_.value -and $_.value -ne ""
                    }
                    
                    if ($sensitiveWithValues) {
                        $validations += @{
                            Principle = "MakeItSecure"
                            Check = "No default values for sensitive variables"
                            Status = "Warning"
                            Message = "Sensitive variables should not have default values - use value sets instead"
                        }
                    } else {
                        $validations += @{
                            Principle = "MakeItSecure"
                            Check = "No default values for sensitive variables"
                            Status = "Passed"
                            Message = "Sensitive variables have empty defaults"
                        }
                    }
                } else {
                    $validations += @{
                        Principle = "MakeItSecure"
                        Check = "No default values for sensitive variables"
                        Status = "Passed"
                        Message = "No obvious sensitive variables with default values"
                    }
                }
                
                # MakeItSecure: Check for hardcoded credentials in values
                $credentialPatterns = @(
                    '(?i)(DefaultEndpointsProtocol=https)',
                    '(?i)(AccountKey=[A-Za-z0-9+/=]{20,})',
                    '(?i)(SharedAccessSignature=)',
                    '(?i)(Password=)',
                    '(?i)(pwd=)',
                    '(?i)(token=)'
                )
                
                $hardcodedFound = $false
                foreach ($var in $variables.variables) {
                    if ($var.value) {
                        foreach ($pattern in $credentialPatterns) {
                            if ($var.value -match $pattern) {
                                $hardcodedFound = $true
                                break
                            }
                        }
                        if ($hardcodedFound) { break }
                    }
                }
                
                if ($hardcodedFound) {
                    $validations += @{
                        Principle = "MakeItSecure"
                        Check = "No hardcoded credentials"
                        Status = "Failed"
                        Message = "Hardcoded credentials detected in variable values"
                    }
                } else {
                    $validations += @{
                        Principle = "MakeItSecure"
                        Check = "No hardcoded credentials"
                        Status = "Passed"
                        Message = "No hardcoded credentials found"
                    }
                }
                
                # MakeItMaintainable: Check for variable documentation/notes
                $varsWithNotes = $variables.variables | Where-Object { 
                    $_.note -and $_.note.Trim() -ne ""
                }
                
                if ($varsWithNotes.Count -eq $variableCount) {
                    $validations += @{
                        Principle = "MakeItMaintainable"
                        Check = "Variables are documented"
                        Status = "Passed"
                        Message = "All variables have notes/documentation"
                    }
                } elseif ($varsWithNotes.Count -gt 0) {
                    $validations += @{
                        Principle = "MakeItMaintainable"
                        Check = "Variables are documented"
                        Status = "Warning"
                        Message = "$($varsWithNotes.Count) of $variableCount variables have notes"
                    }
                } else {
                    $validations += @{
                        Principle = "MakeItMaintainable"
                        Check = "Variables are documented"
                        Status = "Warning"
                        Message = "Add notes/descriptions to variables for clarity"
                    }
                }
                
                # MakeItMaintainable: Check for meaningful variable names
                $genericNames = $variables.variables | Where-Object { 
                    $_.name -match '^(Var|Variable|Value|Param|Parameter)\d*$'
                }
                
                if ($genericNames.Count -eq 0) {
                    $validations += @{
                        Principle = "MakeItMaintainable"
                        Check = "Meaningful variable names"
                        Status = "Passed"
                        Message = "Variable names are descriptive"
                    }
                } else {
                    $validations += @{
                        Principle = "MakeItMaintainable"
                        Check = "Meaningful variable names"
                        Status = "Warning"
                        Message = "$($genericNames.Count) variables have generic names (e.g., 'Var1')"
                    }
                }
                
                # MakeItMaintainable: Check for consistent naming convention
                $pascalCase = $variables.variables | Where-Object { 
                    $_.name -cmatch '^[A-Z][a-zA-Z0-9]*$'
                }
                
                if ($pascalCase.Count -eq $variableCount) {
                    $validations += @{
                        Principle = "MakeItMaintainable"
                        Check = "Consistent naming convention"
                        Status = "Passed"
                        Message = "Variables follow PascalCase convention"
                    }
                } else {
                    $validations += @{
                        Principle = "MakeItMaintainable"
                        Check = "Consistent naming convention"
                        Status = "Warning"
                        Message = "Consider using PascalCase for variable names"
                    }
                }
                
                # DelightStakeholders: Check for type definitions
                $varsWithTypes = $variables.variables | Where-Object { $_.type }
                if ($varsWithTypes.Count -eq $variableCount) {
                    $validations += @{
                        Principle = "DelightStakeholders"
                        Check = "Variable types defined"
                        Status = "Passed"
                        Message = "All variables have explicit types"
                    }
                } else {
                    $validations += @{
                        Principle = "DelightStakeholders"
                        Check = "Variable types defined"
                        Status = "Warning"
                        Message = "Define explicit types for all variables"
                    }
                }
                
            } else {
                $validations += @{
                    Principle = "MakeItWork"
                    Check = "Has variables defined"
                    Status = "Warning"
                    Message = "Variable library has no variables defined"
                }
            }
        } else {
            $validations += @{
                Principle = "MakeItWork"
                Check = "Has variables defined"
                Status = "Failed"
                Message = "variables.json missing 'variables' array"
            }
        }
        
    } catch {
        $validations += @{
            Principle = "MakeItWork"
            Check = "Valid JSON structure"
            Status = "Failed"
            Message = "variables.json is malformed: $($_.Exception.Message)"
        }
    }
    
} else {
    $validations += @{
        Principle = "MakeItWork"
        Check = "Variables definition exists"
        Status = "Failed"
        Message = "variables.json file not found"
    }
}

# MakeItWork: Check for settings.json
$settingsFile = Join-Path $Path "settings.json"
if (Test-Path $settingsFile) {
    try {
        # Validate JSON is parseable
        $null = Get-Content $settingsFile -Raw | ConvertFrom-Json
        $validations += @{
            Principle = "MakeItWork"
            Check = "Settings file valid"
            Status = "Passed"
            Message = "settings.json is valid"
        }
        
        # MakeItScale: Check for value sets
        $valueSetsDir = Join-Path $Path "valueSets"
        if (Test-Path $valueSetsDir) {
            $valueSets = Get-ChildItem -Path $valueSetsDir -Filter "*.json" -ErrorAction SilentlyContinue
            if ($valueSets.Count -gt 0) {
                $validations += @{
                    Principle = "MakeItScale"
                    Check = "Environment-specific value sets"
                    Status = "Passed"
                    Message = "Found $($valueSets.Count) value set(s) for different environments"
                }
                
                # Validate value sets
                foreach ($valueSet in $valueSets) {
                    try {
                        $vsContent = Get-Content $valueSet.FullName -Raw | ConvertFrom-Json
                        
                        # Check if value set has variable overrides
                        if ($vsContent.variableOverrides -and $vsContent.variableOverrides.Count -gt 0) {
                            $validations += @{
                                Principle = "DelightStakeholders"
                                Check = "Value set '$($vsContent.name)' configured"
                                Status = "Passed"
                                Message = "Value set '$($vsContent.name)' has $($vsContent.variableOverrides.Count) override(s)"
                            }
                        } else {
                            $validations += @{
                                Principle = "DelightStakeholders"
                                Check = "Value set '$($valueSet.BaseName)' configured"
                                Status = "Warning"
                                Message = "Value set '$($valueSet.BaseName)' has no variable overrides"
                            }
                        }
                    } catch {
                        $validations += @{
                            Principle = "MakeItWork"
                            Check = "Value set '$($valueSet.BaseName)' valid"
                            Status = "Failed"
                            Message = "Value set JSON is malformed: $($_.Exception.Message)"
                        }
                    }
                }
            } else {
                $validations += @{
                    Principle = "MakeItScale"
                    Check = "Environment-specific value sets"
                    Status = "Warning"
                    Message = "No value sets found - consider adding environment-specific configurations"
                }
            }
        } else {
            $validations += @{
                Principle = "MakeItScale"
                Check = "Environment-specific value sets"
                Status = "Warning"
                Message = "No valueSets directory - consider adding for multi-environment support"
            }
        }
        
    } catch {
        $validations += @{
            Principle = "MakeItWork"
            Check = "Settings file valid"
            Status = "Failed"
            Message = "settings.json is malformed: $($_.Exception.Message)"
        }
    }
} else {
    $validations += @{
        Principle = "MakeItWork"
        Check = "Settings file exists"
        Status = "Warning"
        Message = "settings.json not found"
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

# Note: README.md validation removed - Fabric removes README files when loading artifacts to workspace

# Return results as JSON
return $validations | ConvertTo-Json -Depth 5
