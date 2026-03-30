# Analyze Artifacts - Categorize changed files by Fabric artifact type
# Returns organized list of artifacts for targeted review

param(
    [Parameter(Mandatory=$true)]
    [string]$BranchComparisonJson
)

$ErrorActionPreference = "Stop"

try {
    # Parse input JSON
    $comparison = $BranchComparisonJson | ConvertFrom-Json

    # Initialize categories
    $artifacts = [PSCustomObject]@{
        notebooks = @()
        lakehouses = @()
        pipelines = @()
        dataflows = @()
        datasets = @()
        scripts = @()
        documentation = @()
        configuration = @()
        other = @()
    }

    # Categorize each file
    foreach ($file in $comparison.files) {
        $path = $file.path
        
        # Get parent directory name safely
        $parentPath = Split-Path -Parent $path
        if ([string]::IsNullOrEmpty($parentPath)) {
            $name = ""
        } else {
            $name = Split-Path -Leaf $parentPath
        }

        # Determine artifact type
        if ($path -match '\.Notebook[/\\]') {
            $notebookName = $name -replace '\.Notebook$'
            $artifacts.notebooks += [PSCustomObject]@{
                name = $notebookName
                path = $path
                status = $file.status
                fullPath = $path
            }
        }
        elseif ($path -match '\.Lakehouse[/\\]') {
            $lakehouseName = $name -replace '\.Lakehouse$'
            $artifacts.lakehouses += [PSCustomObject]@{
                name = $lakehouseName
                path = $path
                status = $file.status
                fullPath = $path
            }
        }
        elseif ($path -match '\.Pipeline[/\\]') {
            $pipelineName = $name -replace '\.Pipeline$'
            $artifacts.pipelines += [PSCustomObject]@{
                name = $pipelineName
                path = $path
                status = $file.status
                fullPath = $path
            }
        }
        elseif ($path -match '\.DataFlow[/\\]') {
            $dataflowName = $name -replace '\.DataFlow$'
            $artifacts.dataflows += [PSCustomObject]@{
                name = $dataflowName
                path = $path
                status = $file.status
                fullPath = $path
            }
        }
        elseif ($path -match '\.Dataset[/\\]') {
            $datasetName = $name -replace '\.Dataset$'
            $artifacts.datasets += [PSCustomObject]@{
                name = $datasetName
                path = $path
                status = $file.status
                fullPath = $path
            }
        }
        elseif ($path -match '\.(ps1|py|sh|bash)$') {
            $artifacts.scripts += [PSCustomObject]@{
                name = (Split-Path -Leaf $path)
                path = $path
                status = $file.status
                fullPath = $path
            }
        }
        elseif ($path -match '\.(md|txt|rst)$') {
            $artifacts.documentation += [PSCustomObject]@{
                name = (Split-Path -Leaf $path)
                path = $path
                status = $file.status
                fullPath = $path
            }
        }
        elseif ($path -match '\.(json|yml|yaml|xml|config)$') {
            $artifacts.configuration += [PSCustomObject]@{
                name = (Split-Path -Leaf $path)
                path = $path
                status = $file.status
                fullPath = $path
            }
        }
        else {
            $artifacts.other += [PSCustomObject]@{
                name = (Split-Path -Leaf $path)
                path = $path
                status = $file.status
                fullPath = $path
            }
        }
    }

    # Add summary counts
    $summary = [PSCustomObject]@{
        totalFiles = $comparison.filesChanged
        notebooks = $artifacts.notebooks.Count
        lakehouses = $artifacts.lakehouses.Count
        pipelines = $artifacts.pipelines.Count
        dataflows = $artifacts.dataflows.Count
        datasets = $artifacts.datasets.Count
        scripts = $artifacts.scripts.Count
        documentation = $artifacts.documentation.Count
        configuration = $artifacts.configuration.Count
        other = $artifacts.other.Count
    }

    $result = [PSCustomObject]@{
        summary = $summary
        artifacts = $artifacts
        timestamp = Get-Date -Format "yyyy-MM-ddTHH:mm:ssZ"
    }

    # Output as JSON
    $result | ConvertTo-Json -Depth 10

    Write-Host "`nArtifacts analyzed:" -ForegroundColor Green
    Write-Host "  Notebooks: $($artifacts.notebooks.Count)" -ForegroundColor Cyan
    Write-Host "  Lakehouses: $($artifacts.lakehouses.Count)" -ForegroundColor Cyan
    Write-Host "  Pipelines: $($artifacts.pipelines.Count)" -ForegroundColor Cyan
    Write-Host "  Scripts: $($artifacts.scripts.Count)" -ForegroundColor Cyan
    Write-Host "  Documentation: $($artifacts.documentation.Count)" -ForegroundColor Cyan
    Write-Host "  Configuration: $($artifacts.configuration.Count)" -ForegroundColor Cyan
    Write-Host "  Other: $($artifacts.other.Count)" -ForegroundColor Cyan

} catch {
    Write-Error "Failed to analyze artifacts: $_"
    exit 1
}
