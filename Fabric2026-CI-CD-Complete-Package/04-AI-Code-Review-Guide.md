# AI-Powered Code Review Guide

**Version:** 1.0  
**Last Updated:** March 2026

## Overview

This guide explains how to use GitHub Copilot skills to automate pull request creation and code review in your Microsoft Fabric projects. These skills leverage AI to generate PR descriptions, analyze code changes, and provide feedback against the 5 enterprise-ready principles.

## The Two Core Skills

### 1. Create-PR Skill
**Purpose:** Automate PR creation with AI-generated titles and descriptions

**When to Use:**
- You've committed changes and are ready for code review
- You want automatic work item linking
- You need a well-formatted PR description

### 2. Review-PR Skill
**Purpose:** AI-powered code review against enterprise principles

**When to Use:**
- After CI validation passes
- Before human code review
- To get immediate feedback on code quality
- To validate adherence to standards

## Setting Up GitHub Copilot Skills

### Prerequisites

1. **VS Code with GitHub Copilot**
   - VS Code version 1.85 or later
   - GitHub Copilot extension installed
   - Active GitHub Copilot subscription

2. **Azure DevOps Personal Access Token (PAT)**
   - Scopes required:
     - Code: Read & Write
     - Pull Request Threads: Read & Write
     - Work Items: Read
   - Expiration: 90+ days recommended

3. **Node.js**
   - Version 18 or later
   - npm (comes with Node.js)

### Step 1: Configure MCP Server

Create `.vscode/mcp.json` in your repository root:

```json
{
  "mcpServers": {
    "ado": {
      "command": "npx",
      "args": [
        "-y",
        "@modelcontextprotocol/server-azure-devops"
      ],
      "env": {
        "AZURE_DEVOPS_ORG": "https://dev.azure.com/YOUR_ORGANIZATION",
        "AZURE_DEVOPS_PROJECT": "YOUR_PROJECT",
        "AZURE_DEVOPS_PAT": "${AZURE_DEVOPS_PAT}"
      }
    }
  }
}
```

**Replace:**
- `YOUR_ORGANIZATION`: Your Azure DevOps organization name
- `YOUR_PROJECT`: Your project name (e.g., "FDT - NYC Taxi")

### Step 2: Set Environment Variable

**Windows (PowerShell):**
```powershell
# Set for current session
$env:AZURE_DEVOPS_PAT = "your-pat-token-here"

# Add to profile for persistence
Add-Content $PROFILE "`n`$env:AZURE_DEVOPS_PAT = 'your-pat-token-here'"

# Reload profile
. $PROFILE
```

**Linux/Mac:**
```bash
# Add to ~/.bashrc or ~/.zshrc
export AZURE_DEVOPS_PAT="your-pat-token-here"

# Reload
source ~/.bashrc
```

### Step 3: Add Skills to Repository

Copy skill files to your repository:

```
.github/
└── skills/
    ├── create-pr/
    │   └── SKILL.md
    └── review-pr/
        └── SKILL.md
```

These files define the skills that GitHub Copilot can use.

### Step 4: Verify Setup

In VS Code Copilot Chat:

```
@workspace /help
```

You should see:
- ✅ `create-pr` - Create Azure DevOps Pull Request
- ✅ `review-pr` - Review Pull Request changes

## Using the Create-PR Skill

### Prerequisites for PR Creation

1. **Branch Naming Convention**
   
   Your feature branch must follow this pattern:
   ```
   <type>/<workItemId>_<description>
   ```
   
   Examples:
   - `feature/12345_add-validation-logic`
   - `bugfix/67890_fix-null-reference`
   - `enhancement/24680_improve-performance`

2. **Committed Changes**
   
   All your changes must be committed (not just staged):
   ```bash
   git add .
   git commit -m "Add new validation logic"
   git push origin feature/12345_add-validation-logic
   ```

3. **Different from Target**
   
   Your branch must have changes compared to `main` (or your target branch)

### Creating a Pull Request

**Step 1: Open Copilot Chat**

Click the Copilot icon in VS Code sidebar, or press `Ctrl+I` / `Cmd+I`

**Step 2: Invoke the Skill**

```
@workspace /create-pr
```

Or specify a different target branch:

```
@workspace /create-pr develop
```

**Step 3: Copilot Analyzes Your Changes**

GitHub Copilot will:
1. ✅ Check you're on a feature branch
2. ✅ Extract work item ID from branch name
3. ✅ Analyze git changes (diffs)
4. ✅ Generate PR title and description
5. ✅ Check for existing PRs
6. ✅ Create the PR in Azure DevOps

**Step 4: Review and Open PR**

Copilot provides:
- ✅ PR number and title
- ✅ Direct link to view PR in Azure DevOps
- ✅ Confirmation that work item #12345 is linked

Example output:
```
✅ Pull Request Created Successfully!

PR #7514: Add Validation Logic for Taxi Trips
Link: https://dev.azure.com/yourorg/yourproject/_git/yourrepo/pullrequest/7514

Work item #12345 has been automatically linked.

The PR description includes:
- Summary of changes
- Files modified
- Testing notes
- Related artifacts

You can now:
1. Review the PR in Azure DevOps
2. Add reviewers
3. Wait for CI validation
4. Request code review
```

### What Gets Generated

**PR Title Example:**
```
Add Data Quality Validation for NYC Taxi Trips
```

**PR Description Example:**
```markdown
## Summary
This PR implements comprehensive data quality validation for NYC taxi trip data 
in the Bronze to Silver transformation notebook.

## Changes Made
- Added `validate_trip_data()` function with 5 quality rules
- Implemented passenger count validation (1-6 passengers)
- Added trip distance checks (> 0 miles)  
- Added fare amount validation (>= 0)
- Created quality metrics reporting

## Files Modified
- `NB_2000_SILVER_Transform_Trip_Data.Notebook/notebook-content.py` (120 lines)
- `docs/data-quality-rules.md` (new file)

## Testing
- ✅ Tested with January 2026 data (1.2M records)
- ✅ Successfully filters invalid records (0.3% rejection rate)
- ✅ Quality metrics written to control.quality_metrics table

## Related Work Items
- Closes #12345: Implement data quality checks for trip data

## Enterprise Principles
- ✅ Make It Work: Functional validation logic with unit tests
- ✅ Make It Secure: No credentials, uses environment variables
- ✅ Make It Scale: Incremental processing, handles millions of records
- ✅ Make It Maintainable: Clear function names, inline documentation
- ✅ Delight Stakeholders: Quality metrics for monitoring dashboard
```

### Handling Existing PRs

If a PR already exists from your branch:

```
⚠️ Existing PR Found

PR #7501: Earlier Version of Validation Logic
Status: Active
Link: https://dev.azure.com/yourorg/yourproject/_git/yourrepo/pullrequest/7501

You have two options:
1. Update the existing PR by pushing new commits to your branch
2. Abandon the existing PR and create a new one

Would you like me to help update the existing PR description?
```

## Using the Review-PR Skill

### When to Use

**Ideal Timing:**
- ✅ After CI validation passes (no syntax errors)
- ✅ Before requesting human code review
- ✅ For quick feedback on code quality
- ✅ To validate architectural decisions

**Not Recommended:**
- ❌ Before CI validation (fix syntax errors first)
- ❌ As only code review (human review still needed)
- ❌ For trivial changes (single-line fixes)

### Performing an AI Code Review

**Step 1: Open Copilot Chat**

In VS Code, open Copilot Chat panel

**Step 2: Invoke the Skill**

```
@workspace /review-pr
```

Or compare against a different branch:

```
@workspace /review-pr origin/develop
```

**Step 3: Copilot Analyzes Your Changes**

GitHub Copilot will:
1. ✅ Load all changed files
2. ✅ Analyze code changes line-by-line
3. ✅ Evaluate against 5 enterprise principles
4. ✅ Generate detailed feedback
5. ✅ Provide actionable recommendations

**Step 4: Review Feedback**

Copilot provides a comprehensive report:

```markdown
# 🔍 AI Code Review Results

**Branch:** feature/12345_add-validation-logic  
**Compared to:** origin/main  
**Files Changed:** 3 files (+215 / -45)

---

## ✅ Principle 1: Make It Work

**Overall: PASS**

### Notebook: NB_2000_SILVER_Transform_Trip_Data
✅ Valid Python syntax
✅ Proper error handling in validate_trip_data()
✅ Test notebook before committing (recommended)

**Recommendations:**
- Add unit tests for edge cases (null values, extreme outliers)
- Consider testing with empty DataFrame

---

## ⚠️ Principle 2: Make It Secure

**Overall: PASS with Warnings**

### Notebook: NB_2000_SILVER_Transform_Trip_Data
✅ No hardcoded credentials detected
✅ Uses environment variables correctly
⚠️ **Warning**: SQL query concatenation at line 120

**Issue at Line 120:**
```python
query = f"SELECT * FROM trips WHERE {filter_column} = '{filter_value}'"
```

**Recommendation:**
```python
# Use parameterized approach
df = spark.table("trips").filter(F.col(filter_column) == filter_value)
```

This prevents potential SQL injection if filter_value comes from user input.

---

## ✅ Principle 3: Make It Scale

**Overall: EXCELLENT**

### Notebook: NB_2000_SILVER_Transform_Trip_Data
✅ Uses incremental loading from watermark table
✅ Proper partitioning by year/month
✅ Includes OPTIMIZE and VACUUM commands
✅ Avoids collect() on large DataFrames

**Strengths:**
- Excellent use of watermarks for incremental processing
- Partition strategy allows efficient queries
- Good Spark DataFrame transformations

---

## ✅ Principle 4: Make It Maintainable

**Overall: PASS**

### Notebook: NB_2000_SILVER_Transform_Trip_Data
✅ Clear function names (validate_trip_data, calculate_metrics)
✅ Good inline documentation with markdown cells
✅ Follows naming convention: NB_2000_SILVER_*
✅ Docstrings present for all functions

**Recommendations:**
- Consider adding type hints to function parameters:
  ```python
  def validate_trip_data(df: DataFrame, min_distance: float = 0.1) -> DataFrame:
  ```

---

## ✅ Principle 5: Delight Stakeholders

**Overall: EXCELLENT**

### Notebook: NB_2000_SILVER_Transform_Trip_Data
✅ Quality metrics written to control.quality_metrics
✅ Clear error messages with troubleshooting steps
✅ Logging includes timestamps and record counts
✅ Business-friendly comments explaining validation rules

**Strengths:**
- Excellent quality reporting for stakeholder visibility
- Error messages include actionable next steps
- Clear logging for operational monitoring

---

## 📊 Summary

- **Passed:** 4 out of 5 principles
- **Warnings:** 1 security concern (SQL injection risk)
- **Overall Assessment:** Ready for merge after addressing security warning

## 🎯 Recommended Actions

1. **High Priority:** Fix SQL injection risk at line 120 (use parameterized filtering)
2. **Medium Priority:** Add unit tests for edge cases
3. **Nice to Have:** Add type hints to function signatures

## ✅ What's Working Well

- Excellent scalability with incremental loading
- Great stakeholder focus with quality metrics
- Clear, maintainable code structure
- Good security practices overall

---

**Ready for human review?** Yes, after addressing the security warning.

Would you like me to help fix the SQL injection issue?
```

### Acting on Feedback

**High Priority Items (Fix Before Merge):**
- Security vulnerabilities
- Syntax errors
- Breaking changes
- Missing required files

**Medium Priority Items (Should Fix):**
- Performance concerns
- Missing documentation
- Code style inconsistencies
- Missing error handling

**Nice to Have Items (Consider):**
- Code refactoring suggestions
- Additional tests
- Optimization opportunities

### Iterating with Copilot

After making fixes, run the review again:

```
@workspace /review-pr
```

Copilot will analyze the updated changes and confirm fixes:

```
✅ Security Warning Resolved!

The SQL injection risk has been addressed. 
Code now uses parameterized DataFrame filtering.

All 5 enterprise principles now passing. Ready for merge!
```

## Best Practices

### For Developers

1. **Use create-pr for Every PR**
   - Consistent PR descriptions
   - Automatic work item linking
   - Saves time writing descriptions

2. **Run review-pr Before Human Review**
   - Catch issues early
   - Faster feedback cycle
   - Reduce reviewer burden

3. **Act on Warnings**
   - Don't ignore security warnings
   - Address high priority items
   - Document why if you can't fix

4. **Learn from Feedback**
   - Review skill looks for patterns
   - Avoid repeating same issues
   - Improves code quality over time

### For Teams

1. **Standardize on Skills**
   - Everyone uses same PR creation process
   - Consistent quality checks
   - Shared understanding of standards

2. **Customize for Your Needs**
   - Add organization-specific checks
   - Adjust severity levels
   - Include team conventions

3. **Combine with Human Review**
   - AI catches common issues
   - Humans review architecture and design
   - Best of both approaches

4. **Track Metrics**
   - Monitor skill usage
   - Track issues caught
   - Measure quality improvements

## Advanced Usage

### Custom Target Branches

For projects with different branching strategies:

```
@workspace /create-pr develop
@workspace /review-pr origin/develop
```

### Reviewing Before Committing

Run review on uncommitted changes:

```bash
# Stash changes temporarily
git stash

# Create temp branch
git checkout -b temp/review-$(date +%s)

# Apply and commit changes
git stash pop
git add .
git commit -m "temp: for review"

# Run review
@workspace /review-pr

# Clean up
git checkout your-feature-branch
git branch -D temp/review-*
```

### Batch PR Creation

For multiple features:

```bash
# Create and push multiple branches
for feature in feature-a feature-b feature-c; do
  git checkout -b $feature
  # ... make changes ...
  git commit -m "Implement $feature"
  git push origin $feature
done

# Create PRs for each
# Switch to each branch and run:
@workspace /create-pr
```

## Troubleshooting

### Skill Not Found

**Issue:** `@workspace /create-pr` shows "Unknown command"

**Solutions:**
1. Verify `.github/skills/` folder exists with SKILL.md files
2. Reload VS Code window (Ctrl+Shift+P → "Reload Window")
3. Check GitHub Copilot extension is enabled
4. Ensure skills have proper YAML frontmatter

### MCP Connection Failed

**Issue:** "Cannot connect to Azure DevOps MCP server"

**Solutions:**
1. Verify `.vscode/mcp.json` exists and is valid JSON
2. Check `AZURE_DEVOPS_PAT` environment variable is set
3. Verify PAT hasn't expired
4. Ensure Node.js 18+ installed: `node --version`
5. Clear npm cache: `npm cache clean --force`

### PR Creation Fails

**Issue:** "Failed to create pull request"

**Solutions:**
1. Verify branch name follows `type/12345_description` pattern
2. Check work item #12345 exists in Azure DevOps
3. Ensure you have permissions to create PRs
4. Verify repository name matches Azure DevOps
5. Check for existing PR from same branch

### Review Takes Too Long

**Issue:** Review skill times out or is very slow

**Solutions:**
1. Review fewer files at once (split into multiple PRs)
2. Exclude generated files from review
3. Ensure good internet connection
4. Check GitHub Copilot service status

## FAQ

**Q: Can I edit the PR after creation?**  
A: Yes! The PR is in Azure DevOps. You can edit title, description, add reviewers, etc.

**Q: Does review-pr replace human code review?**  
A: No. It catches common issues but human review is still essential for architecture, business logic, and context.

**Q: Can I use these skills without Azure DevOps?**  
A: The current implementation is specific to Azure DevOps. For GitHub, you'd need to adapt the MCP configuration.

**Q: How does AI know our coding standards?**  
A: It reads your `.github/copilot-instructions.md` file which contains your enterprise principles and conventions.

**Q: Can I add custom validation rules?**  
A: Yes! Edit the SKILL.md files to add organization-specific checks and patterns.

**Q: Is my code sent to OpenAI?**  
A: GitHub Copilot uses your code for context but follows GitHub's privacy policy. Check your organization's GitHub Copilot settings.

## Next Steps

1. **Practice Creating PRs**
   - Make a small change
   - Use `@workspace /create-pr`
   - Review the generated description

2. **Try AI Code Review**
   - Use `@workspace /review-pr`
   - Address feedback
   - Run again to confirm fixes

3. **Customize Skills**
   - Add team-specific patterns
   - Include organization standards
   - Share with your team

4. **Integrate with CI/CD**
   - Combine with automated validation
   - Use as pre-commit check
   - Track quality metrics

---

**🎉 You're now ready to leverage AI for code review!** Use these skills on every PR to maintain high code quality and accelerate development.
