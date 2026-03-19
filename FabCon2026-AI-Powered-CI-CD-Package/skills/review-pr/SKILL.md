---
name: review-pr
description: 'Review Pull Request changes against 5 enterprise-ready principles. Evaluates code quality, security, scalability, maintainability, and stakeholder value. Use after CI passes to perform AI-powered code review.'
argument-hint: 'Optional: target branch to compare against (defaults to origin/main)'
---

# Review Pull Request

Performs comprehensive AI-powered code review of Pull Request changes against the 5 enterprise-ready principles defined in the project's copilot instructions. This skill assumes CI validation has already passed and focuses on evaluating the quality, design, and architectural aspects of the changes.

## When to Use

- Reviewing PR changes before approval
- Getting AI feedback on code quality and design
- Validating adherence to enterprise-ready principles
- After automated CI validations pass successfully
- Before merging changes to main branch

## Prerequisites

- Git repository with changes committed
- Current branch differs from target branch
- CI validation pipeline has passed
- Changes follow project naming conventions

## The 5 Enterprise-Ready Principles

This skill evaluates changes against these principles in order:

### 1. Make It Work
- Functional, tested code that meets requirements
- Data flows correctly through medallion architecture (Bronze → Silver → Gold)
- Valid transformations and business logic
- Proper error handling

### 2. Make It Security
- No hardcoded credentials or sensitive data
- Proper use of environment variables and Key Vault
- Input validation and sanitization
- Principle of least privilege
- No security vulnerabilities in dependencies

### 3. Make It Scale
- Handles large datasets efficiently
- Proper partition strategies
- Incremental loading patterns (not full refreshes)
- Optimized Spark configurations
- Parallel processing where appropriate

### 4. Make It Maintainable
- Clear, self-documenting code
- Meaningful variable and function names
- Inline comments for complex logic
- Consistent naming conventions
- Reusable functions (no duplication)
- Comprehensive documentation

### 5. Delight Stakeholders
- Data quality metrics and monitoring
- Intuitive reports with business context
- Data freshness indicators
- Actionable error messages
- Logging for observability
- Self-service analytics support

## Procedure

The skill performs these steps:

### 1. Compare Branches

- Get current branch name
- Compare with target branch (default: origin/main)
- Collect all changed files with diffs
- Identify artifact types (Notebooks, Lakehouses, Pipelines, etc.)

### 2. Analyze Changes by Artifact Type

For each changed artifact:

**Notebooks:**
- Code structure and organization
- Data transformation logic
- Security practices (credentials, SQL injection)
- Performance optimizations
- Documentation quality
- Error handling

**Lakehouses:**
- Schema design
- Medallion layer organization
- Naming conventions
- Table partitioning strategies

**Pipelines:**
- Activity configuration
- Error handling and retry logic
- Monitoring and alerting
- Metadata-driven patterns

**General Code:**
- Code quality and readability
- Security vulnerabilities
- Performance considerations
- Documentation completeness

### 3. Evaluate Against 5 Principles

For each principle, the AI:
- Reviews relevant code sections
- Identifies strengths and weaknesses
- Provides specific examples from the code
- Suggests improvements with code snippets
- Assigns a rating: ✅ Excellent, ⚠️ Needs Work, ❌ Critical Issues

### 4. Generate Review Report

Creates a comprehensive review with:
- Executive summary
- Principle-by-principle evaluation
- Overall recommendations
- Code snippets highlighting concerns
- Suggested improvements
- Priority action items

## Review Report Format

The skill generates a markdown report structured as:

```markdown
# Pull Request Review

## Summary
Brief overview of changes and overall assessment.

## Branch Comparison
- **Current Branch**: feature/123_add-validation
- **Target Branch**: origin/main
- **Files Changed**: 5
- **Additions**: 250 lines
- **Deletions**: 50 lines

## Changes by Artifact Type
- Notebooks: 2 modified
- Lakehouses: 1 modified
- Pipelines: 1 new, 1 modified

---

## 1. Make It Work ✅

**Assessment**: Excellent

**Strengths**:
- All functions have proper error handling
- Data validation checks implemented at each stage
- Clear separation between Bronze/Silver/Gold layers

**Code Examples**:
[Specific examples from the code]

---

## 2. Make It Secure ⚠️

**Assessment**: Needs Work

**Concerns**:
- Connection string found in notebook cell 4
- SQL query constructed with string concatenation

**Recommendations**:
[Specific suggestions with code]

---

[Continue for all 5 principles]

---

## Overall Recommendations

1. **Priority 1 (Critical)**: Fix security issues
2. **Priority 2 (High)**: Add optimization for large datasets
3. **Priority 3 (Medium)**: Improve documentation

## Conclusion

[Final summary and approval recommendation]
```

## Scripts

### [compare-branches.ps1](./scripts/compare-branches.ps1)
Compares current branch with target branch and returns detailed diff.

**Parameters:**
- `TargetBranch`: Branch to compare against (default: origin/main)
- `IncludeDiffs`: Include full file diffs (default: true)

**Returns:**
```json
{
  "currentBranch": "feature/123_add-validation",
  "targetBranch": "origin/main",
  "filesChanged": 5,
  "additions": 250,
  "deletions": 50,
  "files": [
    {
      "path": "NB_1000_BRONZE_Download_Data.Notebook/notebook-content.py",
      "status": "modified",
      "diff": "..."
    }
  ]
}
```

### [analyze-artifacts.ps1](./scripts/analyze-artifacts.ps1)
Categorizes changed files by Fabric artifact type.

**Returns:**
```json
{
  "notebooks": ["NB_1000_BRONZE_Download_Data"],
  "lakehouses": ["LH_NYC_Taxi"],
  "pipelines": ["PL_1000_BRONZE_Ingest"],
  "other": ["README.md", "scripts/validate.ps1"]
}
```

### [get-file-context.ps1](./scripts/get-file-context.ps1)
Extracts relevant context from changed files for AI review.

**Parameters:**
- `FilePath`: Path to the file
- `MaxLines`: Maximum lines to include (default: 500)

## Usage Example

### As a User Command

```
@workspace review this PR against the 5 principles
```

or

```
@workspace /review-pr
```

### From Another Agent

```markdown
Please use the review-pr skill to evaluate the current PR changes 
against the enterprise-ready principles defined in our copilot instructions.
Compare against origin/main.
```

## Integration with CI/CD

This skill complements automated CI validation:

1. **CI Pipeline** (automated):
   - Syntax checks
   - Security scanning
   - Naming convention validation
   - Required file checks

2. **PR Review Skill** (AI-powered):
   - Code quality assessment
   - Architectural review
   - Design pattern evaluation
   - Business logic validation
   - Stakeholder value assessment

## Best Practices

- Run this skill after CI passes (don't repeat automated checks)
- Focus on design, architecture, and business logic
- Provide specific, actionable feedback
- Reference actual code from the PR
- Suggest concrete improvements
- Consider the full context of the project

## Limitations

- Cannot execute code or run tests
- Cannot access external systems (databases, APIs)
- Relies on git diff and file content
- Limited to text-based analysis
- Requires good documentation to understand intent

## Tips for Better Reviews

1. **Clear Commit Messages**: Help the AI understand intent
2. **Good Documentation**: Add comments for complex logic
3. **Small PRs**: Easier to review thoroughly
4. **Meaningful Names**: Use descriptive variable/function names
5. **Test Coverage**: Include test results or descriptions

## Output

The skill returns a comprehensive markdown review report that can be:
- Posted as a PR comment
- Saved to a file for reference
- Used to guide code improvements
- Shared with the team for discussion

---

*This skill provides AI-powered insights to complement automated validation and human judgment. Always apply critical thinking to AI recommendations.*
