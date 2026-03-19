# Setup Guide - Review PR Skill

This guide helps you get the review-pr skill working in your workspace.

## Prerequisites

1. **Git Repository**: Workspace must be a valid git repository
2. **GitHub Copilot**: VS Code extension installed and active
3. **PowerShell**: Version 5.1 or higher (Windows) or PowerShell Core 7+ (cross-platform)
4. **Git**: Installed and configured

## Installation

The skill is already included in the workspace under `.github/skills/review-pr/`. No additional installation is required.

## Verification

Run the test script to verify everything works:

```powershell
cd .github\skills\review-pr
.\test-skill.ps1
```

All tests should pass.

## Configuration

### Git Configuration

Ensure your git remote is properly configured:

```powershell
# Check remote configuration
git remote -v

# If needed, add remote
git remote add origin <your-repo-url>

# Fetch latest
git fetch origin
```

### PowerShell Execution Policy

If you encounter execution policy errors:

```powershell
# For current user (recommended)
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser

# Verify
Get-ExecutionPolicy -List
```

## Usage

### In VS Code Chat

The skill is automatically available in Copilot chat:

```
@workspace review this PR
```

or 

```
@workspace review changes against origin/develop
```

### Manual Script Execution

You can also run the scripts directly:

```powershell
# Compare branches
.\.github\skills\review-pr\scripts\compare-branches.ps1 -TargetBranch "origin/main"

# Analyze artifacts (requires comparison JSON)
$comparison = .\.github\skills\review-pr\scripts\compare-branches.ps1 | ConvertFrom-Json
.\.github\skills\review-pr\scripts\analyze-artifacts.ps1 -BranchComparisonJson ($comparison | ConvertTo-Json)

# Get file context
.\.github\skills\review-pr\scripts\get-file-context.ps1 -FilePath "path/to/file.py" -IncludeMetadata
```

## Skill Registration

The skill is automatically registered through the VS Code Copilot system. You can verify registration:

1. Open VS Code
2. Open Copilot Chat (`Ctrl+Alt+I` or `Cmd+Alt+I`)
3. Type `@workspace` and check available skills
4. Look for "review-pr" in the suggestions

## Customization

### Modify Review Criteria

Edit [SKILL.md](SKILL.md) to adjust the 5 principles or add custom evaluation criteria:

```markdown
## The 5 Enterprise-Ready Principles

### 1. Make It Work
[Your custom criteria]

### 2. Make It Secure
[Your custom criteria]
...
```

### Adjust File Limits

In [scripts/get-file-context.ps1](scripts/get-file-context.ps1), change the default `MaxLines`:

```powershell
param(
    ...
    [int]$MaxLines = 500,  # Change this value
    ...
)
```

### Custom Artifact Types

In [scripts/analyze-artifacts.ps1](scripts/analyze-artifacts.ps1), add new artifact categories:

```powershell
$artifacts = [PSCustomObject]@{
    notebooks = @()
    lakehouses = @()
    ...
    myCustomType = @()  # Add new type
}
```

## Troubleshooting

### Issue: "Not in a git repository"

**Solution**: Ensure you're running from the workspace root:

```powershell
cd c:\fabcon\fdt-nyc-taxi
```

### Issue: "Target branch does not exist"

**Solution**: Fetch latest changes from remote:

```powershell
git fetch origin
git branch -r  # List remote branches
```

### Issue: "Script execution disabled"

**Solution**: Update PowerShell execution policy:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

### Issue: "No changes detected"

**Solution**: Verify you're not on the target branch:

```powershell
git branch --show-current
git diff origin/main --name-only
```

### Issue: Skill not appearing in Copilot

**Solutions**:
1. Reload VS Code window (`Ctrl+Shift+P` → "Reload Window")
2. Check SKILL.md has proper YAML frontmatter
3. Verify file is in `.github/skills/review-pr/SKILL.md`
4. Check VS Code Copilot extension is enabled

## Testing

### Run Full Test Suite

```powershell
cd .github\skills\review-pr
.\test-skill.ps1
```

### Test Individual Scripts

```powershell
# Test branch comparison
.\scripts\compare-branches.ps1 -TargetBranch "origin/main"

# Test artifact analysis (requires comparison data)
$comparison = .\scripts\compare-branches.ps1 | ConvertFrom-Json
.\scripts\analyze-artifacts.ps1 -BranchComparisonJson ($comparison | ConvertTo-Json)

# Test file context
.\scripts\get-file-context.ps1 -FilePath "README.md" -IncludeMetadata
```

### Test with Specific Branch

```powershell
.\test-skill.ps1 -TargetBranch "origin/develop"
```

## Integration

### Azure DevOps Pipeline

Add to `azure-pipelines.yml`:

```yaml
- task: PowerShell@2
  displayName: 'AI Code Review'
  inputs:
    filePath: '.github/skills/review-pr/scripts/compare-branches.ps1'
    arguments: '-TargetBranch "origin/$(System.PullRequest.TargetBranch)"'
  condition: eq(variables['Build.Reason'], 'PullRequest')
```

### GitHub Actions

Add to `.github/workflows/review.yml`:

```yaml
- name: AI Code Review
  shell: pwsh
  run: |
    .github/skills/review-pr/scripts/compare-branches.ps1 -TargetBranch "origin/${{ github.base_ref }}"
```

## Updating the Skill

To update the skill:

1. **Modify scripts** in `scripts/` directory
2. **Update documentation** in [SKILL.md](SKILL.md) and [README.md](README.md)
3. **Run tests** to ensure changes work
4. **Commit changes** with clear message

```powershell
git add .github/skills/review-pr/
git commit -m "Update review-pr skill: [description]"
git push
```

## Support

### Common Questions

**Q: Can I use this with GitHub instead of Azure DevOps?**  
A: Yes, the skill works with any git repository. It only requires git commands.

**Q: Does this replace human code review?**  
A: No, it complements human review by providing AI-powered insights on code quality and adherence to principles.

**Q: Can I customize the 5 principles?**  
A: Yes, edit the SKILL.md file to define your own evaluation criteria.

**Q: How long does a review take?**  
A: Depends on the number of changes. Typically 30 seconds to 2 minutes for PRs with 10-20 files.

**Q: Can I run this in CI/CD?**  
A: Yes, see the Integration section above for examples.

### Getting Help

1. Check [README.md](README.md) for usage examples
2. Review [SKILL.md](SKILL.md) for detailed documentation
3. Run `.\test-skill.ps1` to validate setup
4. Check [Troubleshooting](#troubleshooting) section above

## Next Steps

1. ✅ Run `.\test-skill.ps1` to verify setup
2. ✅ Try reviewing a sample PR: `@workspace review this PR`
3. ✅ Read [README.md](README.md) for usage examples
4. ✅ Customize evaluation criteria in [SKILL.md](SKILL.md)
5. ✅ Integrate into your CI/CD pipeline

---

*For more information about skills, see the [VS Code Copilot documentation](https://code.visualstudio.com/docs/copilot).*
