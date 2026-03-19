# Review PR Skill

AI-powered Pull Request review skill that evaluates code changes against the 5 enterprise-ready principles defined in the project's copilot instructions.

## Overview

This skill provides comprehensive code review by analyzing git diffs and evaluating changes against:

1. **Make It Work** - Functionality and correctness
2. **Make It Secure** - Security practices and vulnerability prevention
3. **Make It Scale** - Performance and scalability patterns
4. **Make It Maintainable** - Code quality and documentation
5. **Delight Stakeholders** - Business value and user experience

## Quick Start

### From VS Code Chat

```
@workspace review this PR
```

or with a specific target branch:

```
@workspace review changes against origin/develop
```

### Manually Running Scripts

```powershell
# 1. Compare branches
$comparison = .\scripts\compare-branches.ps1 -TargetBranch "origin/main" | ConvertFrom-Json

# 2. Analyze artifacts
$artifacts = .\scripts\analyze-artifacts.ps1 -BranchComparisonJson ($comparison | ConvertTo-Json) | ConvertFrom-Json

# 3. Get file context for review
$context = .\scripts\get-file-context.ps1 -FilePath "path/to/file.py" -IncludeMetadata | ConvertFrom-Json
```

## What Gets Reviewed

### Notebooks
- Code structure and organization
- Data transformation logic
- Security practices (no hardcoded credentials)
- Performance optimization (partitioning, incremental loads)
- Documentation quality
- Error handling
- Medallion architecture adherence

### Lakehouses
- Schema design
- Layer organization (Bronze/Silver/Gold)
- Naming conventions
- Table partitioning strategies
- README documentation

### Pipelines
- Activity configuration
- Error handling and retry logic
- Monitoring and alerting
- Metadata-driven patterns
- Pipeline dependencies

### Scripts
- Code quality and readability
- Security vulnerabilities
- Error handling
- Documentation
- Reusability

### Documentation
- Completeness
- Clarity
- Up-to-date information
- Examples and usage

## Review Output

The skill generates a comprehensive markdown report with:

- **Executive Summary**: High-level overview of changes
- **Branch Comparison**: Statistics and file changes
- **Artifact Breakdown**: Changes by type
- **Principle Evaluations**: Detailed assessment for each of the 5 principles
- **Code Examples**: Specific snippets highlighting concerns or strengths
- **Recommendations**: Prioritized action items
- **Conclusion**: Overall assessment and approval recommendation

### Rating System

Each principle receives one of these ratings:

- ✅ **Excellent** - Exceeds expectations, no concerns
- ⚠️ **Needs Work** - Some issues identified, improvements recommended
- ❌ **Critical Issues** - Serious problems that must be addressed

## Design Philosophy

### Complementary to Automation

This skill is designed to work **after** automated CI checks pass:

- **Automated CI**: Syntax, security scanning, naming conventions
- **AI Review**: Architecture, design patterns, business logic, code quality

### Context-Aware

The review considers:
- Project naming conventions
- Medallion architecture patterns
- Microsoft Fabric best practices
- Enterprise-ready principles
- Team coding standards

### Actionable Feedback

Reviews provide:
- Specific file and line references
- Code examples
- Concrete suggestions
- Priority levels
- Improvement recommendations

## Scripts

### compare-branches.ps1

Compares current branch with target and returns detailed diff information.

**Parameters:**
- `TargetBranch` (string): Branch to compare against (default: "origin/main")
- `IncludeDiffs` (switch): Include full file diffs (default: true)

**Output:** JSON with branch comparison data and file diffs

### analyze-artifacts.ps1

Categorizes changed files by Fabric artifact type.

**Parameters:**
- `BranchComparisonJson` (string): JSON output from compare-branches.ps1

**Output:** JSON with categorized artifacts (notebooks, lakehouses, pipelines, etc.)

### get-file-context.ps1

Extracts file content with metadata for AI analysis.

**Parameters:**
- `FilePath` (string): Path to file to extract
- `MaxLines` (int): Maximum lines to include (default: 500)
- `IncludeMetadata` (switch): Include git history and file metadata

**Output:** JSON with file content and metadata

## Example Review Flow

1. **User initiates review**: `@workspace review this PR`

2. **Skill compares branches**: Gets diff between current branch and origin/main

3. **Skill analyzes artifacts**: Categorizes changed files by type

4. **Skill gathers context**: Reads file contents and git history

5. **AI evaluates**: Reviews changes against each of the 5 principles:
   - Examines code patterns
   - Checks security practices
   - Assesses scalability
   - Evaluates maintainability
   - Considers stakeholder value

6. **Skill generates report**: Creates comprehensive markdown review

7. **User receives feedback**: Actionable recommendations with examples

## Integration Points

### Azure DevOps Pipelines

Can be integrated into CI/CD:

```yaml
- task: PowerShell@2
  displayName: 'AI Code Review'
  inputs:
    filePath: '.github/skills/review-pr/scripts/compare-branches.ps1'
    arguments: '-TargetBranch "origin/main"'
  condition: succeededOrFailed()
```

### VS Code Copilot

Invoked through:
- Chat interface: `@workspace /review-pr`
- Agent selection: Available in Copilot agent list
- Auto-completion: Suggested when reviewing PRs

### Manual Review

Can be run independently:

```powershell
# Review changes
.\test-skill.ps1 -TargetBranch "origin/main"
```

## Best Practices

### For PR Authors

1. **Small, focused PRs** - Easier to review thoroughly
2. **Clear commit messages** - Help AI understand intent
3. **Good documentation** - Add comments for complex logic
4. **Self-review first** - Run the skill before requesting review
5. **Address feedback** - Respond to recommendations

### For Reviewers

1. **Run after CI passes** - Don't repeat automated checks
2. **Read the full report** - Consider all 5 principles
3. **Apply critical thinking** - AI suggestions need human judgment
4. **Provide context** - Add your own insights
5. **Be constructive** - Focus on improvement, not criticism

## Troubleshooting

### "Not in a git repository"

Ensure you're in the workspace root with a valid git repository:

```powershell
git rev-parse --show-toplevel
```

### "Target branch does not exist"

Fetch latest changes:

```powershell
git fetch origin
```

### "No changes detected"

Verify current branch differs from target:

```powershell
git diff origin/main --name-only
```

### Script execution errors

Ensure execution policy allows scripts:

```powershell
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope CurrentUser
```

## Limitations

- **Cannot execute code** - Static analysis only
- **No external access** - Can't connect to databases/APIs
- **Text-based** - Relies on code and documentation
- **Context limited** - May miss architectural context
- **AI limitations** - Subject to AI model capabilities

## Future Enhancements

Potential improvements:

- [ ] Integration with code coverage reports
- [ ] Performance metrics analysis
- [ ] Historical PR comparison
- [ ] Team-specific customization
- [ ] Auto-fix suggestions
- [ ] Multi-language support
- [ ] Custom principle definitions

## Contributing

To improve this skill:

1. Update scripts in `scripts/` directory
2. Enhance SKILL.md with new capabilities
3. Add test cases to test-skill.ps1
4. Update this README
5. Test thoroughly before committing

## Related Documentation

- [Copilot Instructions](../../../copilot-instructions.md) - Enterprise-ready principles
- [Validation Scripts](../../../../scripts/README.md) - Automated CI validation
- [Create PR Skill](../create-pr/README.md) - PR creation companion skill
- [Azure Pipelines](../../../../azure-pipelines.yml) - CI/CD configuration

---

*This skill empowers teams to maintain high code quality standards while accelerating the review process with AI-powered insights.*
