# Validate Pipeline Artifacts
# Checks Data Factory pipelines against enterprise-ready principles

param(
    [Parameter(Mandatory=$true)]
    [string]$Path,
    
    [Parameter(Mandatory=$true)]
    [string]$Name
)

Write-Host "Validating Pipeline: $Name" -ForegroundColor Yellow

$validations = @()

# MakeItWork: Check for pipeline definition file
$pipelineFile = Join-Path $Path "pipeline-content.json"
if (-not (Test-Path $pipelineFile)) {
    # Try alternative name
    $pipelineFile = Get-ChildItem -Path $Path -Filter "*.json" | Select-Object -First 1 -ExpandProperty FullName
}

if ($pipelineFile -and (Test-Path $pipelineFile)) {
    $validations += @{
        Principle = "MakeItWork"
        Check = "Pipeline definition exists"
        Status = "Passed"
        Message = "Pipeline JSON found"
    }
    
    # MakeItWork: Validate JSON structure
    try {
        $pipeline = Get-Content $pipelineFile -Raw | ConvertFrom-Json
        $validations += @{
            Principle = "MakeItWork"
            Check = "Valid JSON structure"
            Status = "Passed"
            Message = "Pipeline JSON is valid"
        }
        
        # Check for activities
        if ($pipeline.properties.activities) {
            $activityCount = $pipeline.properties.activities.Count
            $validations += @{
                Principle = "MakeItWork"
                Check = "Has activities"
                Status = "Passed"
                Message = "Pipeline has $activityCount activity/activities"
            }
            
            # MakeItWork: Check for activity dependencies
            $dependenciesExist = $pipeline.properties.activities | Where-Object { $_.dependsOn } | Measure-Object | Select-Object -ExpandProperty Count
            if ($dependenciesExist -gt 0) {
                $validations += @{
                    Principle = "MakeItWork"
                    Check = "Activity dependencies defined"
                    Status = "Passed"
                    Message = "$dependenciesExist activities have dependencies"
                }
            } else {
                $validations += @{
                    Principle = "MakeItWork"
                    Check = "Activity dependencies defined"
                    Status = "Warning"
                    Message = "No activity dependencies - ensure execution order is correct"
                }
            }
            
            # MakeItSecure: Check for hardcoded connections
            $pipelineJson = $pipeline | ConvertTo-Json -Depth 20
            if ($pipelineJson -match "(?i)(password|AccountKey|ConnectionString|accessToken)") {
                $validations += @{
                    Principle = "MakeItSecure"
                    Check = "No hardcoded credentials"
                    Status = "Warning"
                    Message = "Manual review recommended - check for hardcoded credentials in pipeline"
                }
            } else {
                $validations += @{
                    Principle = "MakeItSecure"
                    Check = "No hardcoded credentials"
                    Status = "Passed"
                    Message = "No obvious hardcoded credentials found"
                }
            }
            
            # MakeItSecure: Check for parameters/variables usage
            $hasParameters = $pipeline.properties.parameters -and $pipeline.properties.parameters.PSObject.Properties.Count -gt 0
            $hasVariables = $pipeline.properties.variables -and $pipeline.properties.variables.PSObject.Properties.Count -gt 0
            
            if ($hasParameters -or $hasVariables) {
                $validations += @{
                    Principle = "MakeItSecure"
                    Check = "Uses parameters/variables"
                    Status = "Passed"
                    Message = "Pipeline uses parameterization for flexibility and security"
                }
            } else {
                $validations += @{
                    Principle = "MakeItSecure"
                    Check = "Uses parameters/variables"
                    Status = "Warning"
                    Message = "Consider using parameters for dynamic configuration"
                }
            }
            
            # MakeItScale: Check for ForEach or parallel execution
            $parallelActivities = $pipeline.properties.activities | Where-Object { $_.type -eq 'ForEach' -or $_.type -eq 'ExecutePipeline' }
            if ($parallelActivities) {
                $validations += @{
                    Principle = "MakeItScale"
                    Check = "Parallel execution patterns"
                    Status = "Passed"
                    Message = "Pipeline uses ForEach or Execute Pipeline for scale"
                }
            } else {
                $validations += @{
                    Principle = "MakeItScale"
                    Check = "Parallel execution patterns"
                    Status = "Warning"
                    Message = "Consider parallel execution for processing multiple items"
                }
            }
            
            # MakeItMaintainable: Check for activity descriptions
            $activitiesWithDesc = $pipeline.properties.activities | Where-Object { $_.description -or $_.name }
            if ($activitiesWithDesc.Count -eq $activityCount) {
                $validations += @{
                    Principle = "MakeItMaintainable"
                    Check = "Activities are documented"
                    Status = "Passed"
                    Message = "All activities have names/descriptions"
                }
            } else {
                $validations += @{
                    Principle = "MakeItMaintainable"
                    Check = "Activities are documented"
                    Status = "Warning"
                    Message = "Some activities lack documentation"
                }
            }
            
            # MakeItMaintainable: Check for meaningful activity names
            $genericNames = $pipeline.properties.activities | Where-Object { $_.name -match '^(Activity|Copy|Execute|Notebook)\d+$' }
            if ($genericNames.Count -eq 0) {
                $validations += @{
                    Principle = "MakeItMaintainable"
                    Check = "Meaningful activity names"
                    Status = "Passed"
                    Message = "Activity names are descriptive"
                }
            } else {
                $validations += @{
                    Principle = "MakeItMaintainable"
                    Check = "Meaningful activity names"
                    Status = "Warning"
                    Message = "$($genericNames.Count) activities have generic names (e.g., 'Activity1')"
                }
            }
            
            # DelightStakeholders: Check for error handling
            $errorHandling = $pipeline.properties.activities | Where-Object { 
                ($_.dependsOn | Where-Object { $_.dependencyConditions -contains 'Failed' }) -or
                $_.type -eq 'WebHook' -or
                $_.type -eq 'ExecutePipeline'
            }
            
            if ($errorHandling) {
                $validations += @{
                    Principle = "DelightStakeholders"
                    Check = "Error handling configured"
                    Status = "Passed"
                    Message = "Pipeline has error handling activities"
                }
            } else {
                $validations += @{
                    Principle = "DelightStakeholders"
                    Check = "Error handling configured"
                    Status = "Warning"
                    Message = "Add error handling (on failure dependencies, notifications)"
                }
            }
            
            # DelightStakeholders: Check for retry policy
            $activitiesWithRetry = $pipeline.properties.activities | Where-Object { $_.policy -and $_.policy.retry }
            if ($activitiesWithRetry.Count -gt 0) {
                $validations += @{
                    Principle = "DelightStakeholders"
                    Check = "Retry policies configured"
                    Status = "Passed"
                    Message = "$($activitiesWithRetry.Count) activities have retry policies"
                }
            } else {
                $validations += @{
                    Principle = "DelightStakeholders"
                    Check = "Retry policies configured"
                    Status = "Warning"
                    Message = "Consider adding retry policies for transient failures"
                }
            }
            
            # DelightStakeholders: Check for monitoring/logging activities
            $monitoringActivities = $pipeline.properties.activities | Where-Object { 
                $_.type -eq 'WebActivity' -or 
                $_.type -eq 'AppendVariable' -or
                ($_.name -match '(?i)(log|monitor|notify|alert)')
            }
            
            if ($monitoringActivities) {
                $validations += @{
                    Principle = "DelightStakeholders"
                    Check = "Monitoring and logging"
                    Status = "Passed"
                    Message = "Pipeline includes monitoring/logging activities"
                }
            } else {
                $validations += @{
                    Principle = "DelightStakeholders"
                    Check = "Monitoring and logging"
                    Status = "Warning"
                    Message = "Consider adding logging/monitoring for observability"
                }
            }
            
        } else {
            $validations += @{
                Principle = "MakeItWork"
                Check = "Has activities"
                Status = "Failed"
                Message = "Pipeline has no activities defined"
            }
        }
        
    } catch {
        $validations += @{
            Principle = "MakeItWork"
            Check = "Valid JSON structure"
            Status = "Failed"
            Message = "Pipeline JSON is malformed: $($_.Exception.Message)"
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
    
} else {
    $validations += @{
        Principle = "MakeItWork"
        Check = "Pipeline definition exists"
        Status = "Failed"
        Message = "Pipeline JSON file not found"
    }
}

# Note: README.md validation removed - Fabric removes README files when loading artifacts to workspace

# Return results as JSON
return $validations | ConvertTo-Json -Depth 5
