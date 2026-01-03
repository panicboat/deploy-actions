# Claude Code Action

Run Claude Code action with AWS Bedrock integration for automated code assistance.

## Overview

This composite action integrates Claude Code with your GitHub workflows, allowing Claude to assist with code reviews, bug fixes, and feature implementations directly from issue comments or pull requests. It uses AWS Bedrock for Claude API access.

## Inputs

| Name | Required | Default | Description |
|------|----------|---------|-------------|
| `token` | Yes | - | GitHub token for authentication (e.g., from `actions/create-github-app-token`) |
| `aws-role-arn` | Yes | - | AWS IAM role ARN for Bedrock access |
| `aws-region` | No | `us-west-2` | AWS region where Bedrock is available |
| `trigger-phrase` | No | `@claude` | Phrase to trigger Claude in comments |
| `model` | No | `us.anthropic.claude-sonnet-4-5-20250929-v1:0` | Claude model to use |

## Usage

### Basic Example

```yaml
name: Claude Code Action

permissions:
  contents: write
  pull-requests: write
  issues: write
  id-token: write

on:
  issues:
    types: [opened, assigned]
  issue_comment:
    types: [created]
  pull_request_review:
    types: [submitted]
  pull_request_review_comment:
    types: [created]

jobs:
  claude-code:
    runs-on: ubuntu-latest
    timeout-minutes: 60
    if: contains(github.event.comment.body, '@claude') || contains(github.event.issue.body, '@claude')

    steps:
      - name: Generate GitHub App token
        id: app-token
        uses: actions/create-github-app-token@v2.2.1
        with:
          app-id: ${{ vars.APP_ID }}
          private-key: ${{ secrets.APP_PRIVATE_KEY }}

      - name: Run Claude Code
        uses: panicboat/deploy-actions/claude-code-action@main
        with:
          token: ${{ steps.app-token.outputs.token }}
          aws-role-arn: ${{ vars.AWS_ROLE_ARN }}
```

### Advanced Example with User Restrictions

```yaml
name: Claude Code Action

permissions:
  contents: write
  pull-requests: write
  issues: write
  id-token: write

on:
  issues:
    types: [opened, assigned]
  issue_comment:
    types: [created]
  pull_request_review:
    types: [submitted]
  pull_request_review_comment:
    types: [created]

jobs:
  claude-code:
    runs-on: ubuntu-latest
    timeout-minutes: 60
    if: |
      (contains(github.event.comment.body, '@claude') || contains(github.event.issue.body, '@claude')) &&
      contains(fromJSON(vars.ALLOWED_USERS), github.actor)

    steps:
      - name: Generate GitHub App token
        id: app-token
        uses: actions/create-github-app-token@v2.2.1
        with:
          app-id: ${{ vars.APP_ID }}
          private-key: ${{ secrets.APP_PRIVATE_KEY }}

      - name: Run Claude Code
        uses: panicboat/deploy-actions/claude-code-action@main
        with:
          token: ${{ steps.app-token.outputs.token }}
          aws-role-arn: arn:aws:iam::123456789012:role/github-actions-role
          aws-region: us-east-1
          trigger-phrase: "@claude"
          model: "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
```

## Features

- **AWS Bedrock Integration**: Uses AWS Bedrock for Claude API access
- **Flexible Triggering**: Customizable trigger phrase for invoking Claude
- **Multi-Context Support**: Works with issues, pull requests, and comments
- **Configurable Models**: Choose from available Claude models
- **Automatic Retries**: Built-in retry logic for API calls

## Required Permissions

The calling workflow must have the following permissions:

```yaml
permissions:
  contents: write         # To create commits and push changes
  pull-requests: write   # To comment on and modify pull requests
  issues: write          # To comment on issues
  id-token: write        # For AWS authentication with OIDC
```

## AWS Setup

1. Create an IAM role with permissions to access AWS Bedrock
2. Configure the role to trust GitHub Actions OIDC provider
3. Ensure the Bedrock model is available in your selected region
4. Store the role ARN in your repository variables

Example IAM trust policy:
```json
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Principal": {
        "Federated": "arn:aws:iam::YOUR_ACCOUNT_ID:oidc-provider/token.actions.githubusercontent.com"
      },
      "Action": "sts:AssumeRoleWithWebIdentity",
      "Condition": {
        "StringEquals": {
          "token.actions.githubusercontent.com:aud": "sts.amazonaws.com"
        },
        "StringLike": {
          "token.actions.githubusercontent.com:sub": "repo:YOUR_ORG/YOUR_REPO:*"
        }
      }
    }
  ]
}
```

## Environment Variables

The following environment variables are automatically set:

- `ANTHROPIC_BEDROCK_BASE_URL`: Bedrock endpoint URL
- `ANTHROPIC_MAX_RETRIES`: Maximum number of API retries (3)
- `ANTHROPIC_TIMEOUT`: API timeout in seconds (120)
- `ANTHROPIC_REQUEST_DELAY`: Delay between requests in seconds (5)
- `CLAUDE_CODE_MAX_OUTPUT_TOKENS`: Maximum output tokens (8192)

## Migration from Standalone Workflow

If you're migrating from a standalone workflow:

**Before:**
```yaml
steps:
  - name: Generate GitHub App token
    id: app-token
    uses: actions/create-github-app-token@v2.2.1
    with:
      app-id: ${{ vars.APP_ID }}
      private-key: ${{ secrets.APP_PRIVATE_KEY }}

  - name: Checkout code
    uses: actions/checkout@v6
    with:
      token: ${{ steps.app-token.outputs.token }}

  - name: Configure AWS Credentials
    uses: aws-actions/configure-aws-credentials@v5
    with:
      role-to-assume: ${{ vars.AWS_ROLE_ARN }}
      aws-region: us-west-2

  - uses: anthropics/claude-code-action@beta
    with:
      github_token: ${{ steps.app-token.outputs.token }}
      trigger_phrase: "@claude"
      model: "us.anthropic.claude-sonnet-4-5-20250929-v1:0"
      use_bedrock: "true"
```

**After:**
```yaml
steps:
  - name: Generate GitHub App token
    id: app-token
    uses: actions/create-github-app-token@v2.2.1
    with:
      app-id: ${{ vars.APP_ID }}
      private-key: ${{ secrets.APP_PRIVATE_KEY }}

  - name: Run Claude Code
    uses: panicboat/deploy-actions/claude-code-action@main
    with:
      token: ${{ steps.app-token.outputs.token }}
      aws-role-arn: ${{ vars.AWS_ROLE_ARN }}
```

## User Restrictions

To restrict which users can trigger Claude Code, add a condition to your workflow:

```yaml
jobs:
  claude-code:
    if: |
      (contains(github.event.comment.body, '@claude') || contains(github.event.issue.body, '@claude')) &&
      contains(fromJSON(vars.ALLOWED_USERS), github.actor)
```

Then set the `ALLOWED_USERS` variable in your repository:
```json
["username1", "username2", "username3"]
```

## Notes

- For production use, pin to a specific version tag instead of `@main`
- Ensure your AWS role has appropriate Bedrock model access permissions
- The timeout should be set at the job level to allow sufficient time for Claude to complete tasks
- Claude Code requires write permissions to create commits and comments
