# AI Resources — Shared Claude Code Review Pipeline

Reusable GitHub Actions workflow that runs automated code reviews on pull requests using Claude.

## Quick Start

### 1. Add the API key

Add `ANTHROPIC_API_KEY` as a repository secret in your GitHub repo settings.

### 2. Create the workflow

Add `.github/workflows/claude-review.yml` to your repo:

```yaml
name: Claude Code Review

on:
  pull_request:
    types: [opened, ready_for_review]
    branches: [main]
  workflow_dispatch:
    inputs:
      pr_number:
        description: 'PR number to review'
        required: true

jobs:
  review:
    uses: leobit-llc/AI-resources/.github/workflows/claude-review.yml@main
    secrets:
      ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
```

That's it. Open a PR and the review will run automatically.

## Project-Specific Review Guidelines

By default, the pipeline applies company-wide review guidelines from [`defaults/REVIEW.md`](defaults/REVIEW.md).

To add project-specific rules, create a `REVIEW.md` in your repo root (or any path) with additions like tech stack conventions, naming rules, or domain-specific checks. These get **appended** to the base guidelines — they don't replace them.

To use a custom path:

```yaml
jobs:
  review:
    uses: leobit-llc/AI-resources/.github/workflows/claude-review.yml@main
    with:
      review_guidelines_path: .claude/REVIEW.md
    secrets:
      ANTHROPIC_API_KEY: ${{ secrets.ANTHROPIC_API_KEY }}
```

## Inputs

| Input | Type | Default | Description |
|---|---|---|---|
| `review_guidelines_path` | string | `REVIEW.md` | Path to project-specific review guidelines in the consumer repo |

## How It Works

1. Triggers on PR events in the consuming repo
2. Checks out the consumer repo and this shared repo
3. Merges base + project-specific review guidelines
4. Generates a diff between the PR branches
5. Runs Claude to review the diff and produce structured JSON feedback
6. Posts review comments (inline and general) back to the PR
