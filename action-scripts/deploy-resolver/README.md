# Deploy Resolver

A Ruby-based deployment resolution tool that converts PR labels and branch information into deployment targets for GitHub Actions automation.

## Overview

The Deploy Resolver analyzes PR labels and branch context to determine deployment targets, validates deployment safety, and generates deployment matrices for multi-service deployments. It serves as the central orchestrator for deployment automation decisions.

## Features

- **Label Resolution**: Extract deployment labels from PR information
- **Environment Detection**: Determine target environment from branch patterns
- **Directory Convention Resolution**: Resolve deployment paths using hierarchical directory structure
- **Matrix Generation**: Create deployment matrices for parallel execution
- **Branch-based Targeting**: Map branches to deployment environments
- **GitHub Actions Integration**: Seamless integration with GitHub Actions workflows

## Usage

The Deploy Resolver provides a CLI interface through `bin/resolver`:

### Basic Commands

```bash
# Resolve deployment from PR labels
bundle exec ruby deploy-resolver/bin/resolver resolve PR_NUMBER

# Test deployment workflow
bundle exec ruby deploy-resolver/bin/resolver test PR_NUMBER

# Simulate GitHub Actions environment
bundle exec ruby deploy-resolver/bin/resolver simulate PR_NUMBER

# Validate environment configuration
bundle exec ruby deploy-resolver/bin/resolver validate_env

# Debug workflow step-by-step
bundle exec ruby deploy-resolver/bin/resolver debug PR_NUMBER
```

### Workflow Integration

The resolver is typically called from GitHub Actions workflows:

```yaml
- name: Resolve deployment targets
  uses: panicboat/deploy-actions/label-resolver@main
  with:
    action-type: plan  # or apply
    pr-number: ${{ github.event.pull_request.number }}
    repository: ${{ github.repository }}
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

## Core Logic

### 1. Label Extraction

Fetches PR labels that match deployment patterns:
- `deploy:service-name` - Deploy specific service
- `deploy:all` - Deploy all services
- Labels are validated against configured services

### 2. Environment Resolution

Determines target environment based on current branch:
- `develop` → `develop` environment
- `staging` → `staging` environment
- `production` → `production` environment

### 3. Safety Validation

Provides basic deployment validation:
- Validates deployment labels presence
- Checks branch information availability
- Returns success for backward compatibility (safety checks simplified)

### 4. Matrix Generation

Creates deployment matrices for parallel execution:
- Groups services by deployment stack (Terragrunt, Kubernetes)
- Uses hierarchical directory conventions
- Includes environment-specific IAM roles
- Handles service-specific directory overrides
- Supports `deploy:all` for all non-excluded services

## Configuration

The resolver uses `workflow-config.yaml` for configuration:

```yaml
# Branch to environment mapping
branch_patterns:
  develop: develop
  staging: staging
  production: production

# Directory conventions (hierarchical structure)
directory_conventions:
  root: "{service}"
  stacks:
    - name: terragrunt
      directory: "terragrunt/{environment}"
    - name: kubernetes
      directory: "kubernetes/overlays/{environment}"

# Environment configurations
environments:
  - environment: develop
    aws_region: ap-northeast-1
    iam_role_plan: arn:aws:iam::ACCOUNT:role/plan-role
    iam_role_apply: arn:aws:iam::ACCOUNT:role/apply-role
  - environment: staging
    aws_region: ap-northeast-1
    iam_role_plan: arn:aws:iam::ACCOUNT:role/staging-plan-role
    iam_role_apply: arn:aws:iam::ACCOUNT:role/staging-apply-role
  - environment: production
    aws_region: ap-northeast-1
    iam_role_plan: arn:aws:iam::ACCOUNT:role/production-plan-role
    iam_role_apply: arn:aws:iam::ACCOUNT:role/production-apply-role

# Service configurations
services:
  - name: excluded-service
    exclude_from_automation: true
    exclusion_config:
      reason: "Manual deployment required"
      type: "permanent"
```

## Architecture

The Deploy Resolver follows a clean architecture pattern:

### Controllers
- `DeployResolverController`: Orchestrates the resolution process

### Use Cases
- `DetermineTargetEnvironment`: Maps branches to environments
- `GetLabels`: Extracts deployment labels from PR
- `ValidateDeploymentSafety`: Enforces safety rules
- `GenerateMatrix`: Creates deployment matrices

### Infrastructure
- `GitHubClient`: GitHub API interactions
- `ConfigClient`: Configuration file management

## Output Format

The resolver outputs deployment information in GitHub Actions format:

```bash
# Environment variables set
DEPLOYMENT_TARGETS='[{"service":"my-service","environment":"develop","stack":"terragrunt"}]'
HAS_TARGETS=true
TARGET_ENVIRONMENT=develop
SAFETY_STATUS=passed
```

## Environment Variables

- `GITHUB_TOKEN`: Required for GitHub API access
- `GITHUB_REPOSITORY`: Repository name (owner/repo format)
- `GITHUB_REF_NAME`: Current branch name
- `WORKFLOW_CONFIG_PATH`: Path to configuration file
- `SOURCE_REPO_PATH`: Path to source repository checkout

## Error Handling

The resolver provides detailed error handling:

- **No PR Found**: Returns `safety_status=no_merged_pr`
- **Invalid Configuration**: Exits with error and detailed message
- **API Failures**: Retries with exponential backoff
- **Missing Labels**: Returns empty targets array

## Development

### Dependencies

- Ruby 3.4+
- Bundler
- Thor (CLI framework)
- Octokit (GitHub API)

### Testing

```bash
# Test with specific PR
bundle exec ruby deploy-resolver/bin/resolver test 123

# Debug step-by-step
bundle exec ruby deploy-resolver/bin/resolver debug 123

# Validate environment setup
bundle exec ruby deploy-resolver/bin/resolver validate_env
```

## Integration Points

The Deploy Resolver integrates with:

1. **Label Dispatcher**: Consumes labels created by label detection
2. **Deploy Terragrunt**: Provides targets for Terragrunt deployments
3. **Deploy GitOps**: Provides targets for Kubernetes deployments
4. **Config Manager**: Uses validated configuration files

## Safety Features

- **PR Requirement**: Blocks deployments without valid PR
- **Branch Validation**: Ensures deployments only from approved branches
- **Configuration Validation**: Validates configuration before processing
- **Retry Logic**: Handles transient GitHub API failures
- **Audit Trail**: Logs all deployment decisions for troubleshooting
