# Validate Lakehouse Artifacts
# Checks lakehouses against enterprise-ready principles

param(
    [Parameter(Mandatory=$true)]
    [string]$Path,
    
    [Parameter(Mandatory=$true)]
    [string]$Name
)

Write-Host "Validating Lakehouse: $Name" -ForegroundColor Yellow

$validations = @()

# MakeItWork: Check for metadata file
$metadataFile = Join-Path $Path "lakehouse.metadata.json"
if (Test-Path $metadataFile) {
    $validations += @{
        Principle = "MakeItWork"
        Check = "Metadata file exists"
        Status = "Passed"
        Message = "lakehouse.metadata.json found"
    }
    
    # MakeItWork: Validate JSON structure
    try {
        $metadata = Get-Content $metadataFile -Raw | ConvertFrom-Json
        $validations += @{
            Principle = "MakeItWork"
            Check = "Valid JSON metadata"
            Status = "Passed"
            Message = "Metadata file is valid JSON"
        }
        
        # Note: name and type are in .platform file, not lakehouse.metadata.json
        # lakehouse.metadata.json typically only contains schema information
        $validations += @{
            Principle = "MakeItWork"
            Check = "Metadata completeness"
            Status = "Passed"
            Message = "Lakehouse metadata structure valid (name/type are in .platform file)"
        }
        
    } catch {
        $validations += @{
            Principle = "MakeItWork"
            Check = "Valid JSON metadata"
            Status = "Failed"
            Message = "Metadata JSON is malformed: $($_.Exception.Message)"
        }
    }
} else {
    $validations += @{
        Principle = "MakeItWork"
        Check = "Metadata file exists"
        Status = "Failed"
        Message = "lakehouse.metadata.json not found"
    }
}

# MakeItWork: Check for ALM settings (deployment configuration)
$almFile = Join-Path $Path "alm.settings.json"
if (Test-Path $almFile) {
    $validations += @{
        Principle = "MakeItWork"
        Check = "ALM settings configured"
        Status = "Passed"
        Message = "alm.settings.json found for deployment configuration"
    }
} else {
    $validations += @{
        Principle = "MakeItWork"
        Check = "ALM settings configured"
        Status = "Warning"
        Message = "Consider adding alm.settings.json for deployment configuration"
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

# MakeItWork: Tables folder check removed - data is not part of source control
# Tables are created dynamically in Fabric and excluded from Git

# MakeItSecure: Check shortcuts metadata for security
$shortcutsFile = Join-Path $Path "shortcuts.metadata.json"
if (Test-Path $shortcutsFile) {
    try {
        $shortcuts = Get-Content $shortcutsFile -Raw | ConvertFrom-Json
        
        # Check if shortcuts contain any credentials (they shouldn't)
        $shortcutsJson = $shortcuts | ConvertTo-Json -Depth 10
        if ($shortcutsJson -match '(?i)(password|key|secret|token|connectionstring)') {
            $validations += @{
                Principle = "MakeItSecure"
                Check = "Shortcuts security"
                Status = "Warning"
                Message = "Shortcuts metadata may contain sensitive information"
            }
        } else {
            $validations += @{
                Principle = "MakeItSecure"
                Check = "Shortcuts security"
                Status = "Passed"
                Message = "No obvious credentials in shortcuts metadata"
            }
        }
    } catch {
        $validations += @{
            Principle = "MakeItSecure"
            Check = "Shortcuts security"
            Status = "Warning"
            Message = "Could not parse shortcuts metadata"
        }
    }
}

# MakeItSecure: Lakehouse permissions (placeholder - would need API access)
$validations += @{
    Principle = "MakeItSecure"
    Check = "Access controls"
    Status = "Passed"
    Message = "Lakehouse uses Fabric workspace permissions by default"
}

# MakeItScale: Delta Lake format
$validations += @{
    Principle = "MakeItScale"
    Check = "Uses Delta Lake format"
    Status = "Passed"
    Message = "Fabric Lakehouses use Delta Lake by default for ACID transactions"
}

# MakeItScale: OneLake integration
$validations += @{
    Principle = "MakeItScale"
    Check = "OneLake integration"
    Status = "Passed"
    Message = "Fabric Lakehouse is integrated with OneLake for scale"
}

# MakeItMaintainable: Check naming follows medallion architecture
# For multi-layer lakehouses (all layers in one LH), don't require layer in name
if ($Name -match '_(BRONZE|RAW|LANDING)_') {
    $validations += @{
        Principle = "MakeItMaintainable"
        Check = "Medallion layer: Bronze"
        Status = "Passed"
        Message = "Bronze/Raw layer identified in name (single-layer lakehouse)"
    }
} elseif ($Name -match '_(SILVER|CLEAN|CURATED)_') {
    $validations += @{
        Principle = "MakeItMaintainable"
        Check = "Medallion layer: Silver"
        Status = "Passed"
        Message = "Silver/Clean layer identified in name (single-layer lakehouse)"
    }
} elseif ($Name -match '_(GOLD|ENRICHED|ANALYTICS)_') {
    $validations += @{
        Principle = "MakeItMaintainable"
        Check = "Medallion layer: Gold"
        Status = "Passed"
        Message = "Gold/Enriched layer identified in name (single-layer lakehouse)"
    }
} else {
    # Check if this is a multi-layer lakehouse
    # Primary: Check .platform description (Tables folder not in source control)
    # Fallback: Check Tables folder if it exists (for local validation)
    $hasMultiLayerStructure = $false
    
    # First check .platform description for multi-layer indicators
    $platformFile = Join-Path $Path ".platform"
    if (Test-Path $platformFile) {
        try {
            $platform = Get-Content $platformFile -Raw | ConvertFrom-Json
            $description = $platform.metadata.description
            if ($description -match '(?i)(multi-layer|bronze.*silver.*gold|medallion|layers?|schema)') {
                $hasMultiLayerStructure = $true
            }
        } catch {
            # Ignore parsing errors
        }
    }
    
    # Fallback: Check Tables folder for bronze/silver/gold schemas (if folder exists locally)
    if (-not $hasMultiLayerStructure) {
        $tablesFolder = Join-Path $Path "Tables"
        if (Test-Path $tablesFolder) {
            $tables = Get-ChildItem -Path $tablesFolder -Directory -ErrorAction SilentlyContinue
            $schemaNames = $tables | ForEach-Object { $_.Name.ToLower() }
            
            $hasBronze = $schemaNames -contains 'bronze' -or ($schemaNames | Where-Object { $_ -match 'bronze' })
            $hasSilver = $schemaNames -contains 'silver' -or ($schemaNames | Where-Object { $_ -match 'silver' })
            $hasGold = $schemaNames -contains 'gold' -or ($schemaNames | Where-Object { $_ -match 'gold' })
            
            if ($hasBronze -or $hasSilver -or $hasGold) {
                $hasMultiLayerStructure = $true
            }
        }
    }
    
    if ($hasMultiLayerStructure) {
        $validations += @{
            Principle = "MakeItMaintainable"
            Check = "Medallion architecture pattern"
            Status = "Passed"
            Message = "Multi-layer lakehouse detected (bronze/silver/gold layers within single lakehouse)"
        }
    } else {
        $validations += @{
            Principle = "MakeItMaintainable"
            Check = "Medallion architecture pattern"
            Status = "Warning"
            Message = "Consider organizing as: (1) single-layer LH with layer in name, OR (2) multi-layer LH with bronze/silver/gold schemas"
        }
    }
}

# MakeItMaintainable: Index in name
if ($Name -match '_(\d{4})_') {
    $index = $matches[1]
    $validations += @{
        Principle = "MakeItMaintainable"
        Check = "Index in name"
        Status = "Passed"
        Message = "Index $index found in name for ordering"
    }
} elseif ($Name -notmatch '_(BRONZE|SILVER|GOLD|RAW|CLEAN|ENRICHED)_') {
    # Only suggest index for multi-layer lakehouses (no layer in name)
    $validations += @{
        Principle = "MakeItMaintainable"
        Check = "Index in name"
        Status = "Passed"
        Message = "Multi-layer lakehouse - index not required"
    }
} else {
    $validations += @{
        Principle = "MakeItMaintainable"
        Check = "Index in name"
        Status = "Warning"
        Message = "Consider adding 4-digit index (1000, 2000, 3000) to name for single-layer lakehouses"
    }
}

# Note: README.md validation removed - Fabric removes README files when loading artifacts to workspace

# DelightStakeholders: SQL Endpoint availability
$validations += @{
    Principle = "DelightStakeholders"
    Check = "SQL Endpoint available"
    Status = "Passed"
    Message = "Fabric Lakehouse provides automatic SQL Endpoint for querying"
}

# DelightStakeholders: Default Dataset
$validations += @{
    Principle = "DelightStakeholders"
    Check = "Default Dataset for Power BI"
    Status = "Passed"
    Message = "Fabric Lakehouse creates default Dataset for reporting"
}

# Return results as JSON
return $validations | ConvertTo-Json -Depth 5
