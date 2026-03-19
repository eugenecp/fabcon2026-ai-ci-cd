# Get File Context - Extract relevant context from files for AI review
# Returns file content with metadata for comprehensive analysis

param(
    [Parameter(Mandatory=$true)]
    [string]$FilePath,
    
    [int]$MaxLines = 500,
    
    [switch]$IncludeMetadata
)

$ErrorActionPreference = "Stop"

try {
    # Ensure file exists
    if (-not (Test-Path $FilePath)) {
        throw "File not found: $FilePath"
    }

    # Get file info
    $fileInfo = Get-Item $FilePath
    
    # Read file content
    $content = Get-Content -Path $FilePath -Raw
    $lines = Get-Content -Path $FilePath
    $lineCount = $lines.Count

    # Truncate if necessary
    $truncated = $false
    if ($lineCount -gt $MaxLines) {
        $lines = $lines | Select-Object -First $MaxLines
        $content = $lines -join "`n"
        $truncated = $true
    }

    # Determine file type and language
    $extension = $fileInfo.Extension.ToLower()
    $language = switch ($extension) {
        '.py' { 'python' }
        '.ps1' { 'powershell' }
        '.sql' { 'sql' }
        '.md' { 'markdown' }
        '.json' { 'json' }
        '.yml' { 'yaml' }
        '.yaml' { 'yaml' }
        '.sh' { 'bash' }
        '.bash' { 'bash' }
        default { 'text' }
    }

    # Build result
    $result = [PSCustomObject]@{
        path = $FilePath
        name = $fileInfo.Name
        extension = $extension
        language = $language
        size = $fileInfo.Length
        lineCount = $lineCount
        truncated = $truncated
        maxLines = $MaxLines
        content = $content
    }

    # Add metadata if requested
    if ($IncludeMetadata) {
        $result | Add-Member -NotePropertyName 'created' -NotePropertyValue $fileInfo.CreationTime
        $result | Add-Member -NotePropertyName 'modified' -NotePropertyValue $fileInfo.LastWriteTime
        
        # Try to get git info
        try {
            $gitLog = git log -1 --format="%H|%an|%ae|%ad|%s" -- $FilePath 2>&1
            if ($LASTEXITCODE -eq 0 -and $gitLog) {
                $parts = $gitLog -split '\|'
                $result | Add-Member -NotePropertyName 'lastCommit' -NotePropertyValue ([PSCustomObject]@{
                    hash = $parts[0]
                    author = $parts[1]
                    email = $parts[2]
                    date = $parts[3]
                    message = $parts[4]
                })
            }
        } catch {
            # Git info not available, skip
        }
    }

    # Output as JSON
    $result | ConvertTo-Json -Depth 10

    if ($truncated) {
        Write-Host "`nWarning: File truncated to $MaxLines lines (total: $lineCount)" -ForegroundColor Yellow
    }

} catch {
    Write-Error "Failed to get file context: $_"
    exit 1
}
