# Label Resolver

**English** | [🇯🇵 日本語](README-ja.md)

A Ruby-based deployment resolution tool that converts PR labels into deployment targets for GitHub Actions automation using explicit environment targeting.

## Overview

The Label Resolver analyzes PR labels and generates deployment targets for specified environments. It validates deployment safety and creates deployment matrices for multi-service deployments, serving as the central orchestrator for deployment automation decisions.

## Features

- **Label Resolution**: Extract deployment labels from PR information
- **Explicit Environment Targeting**: Direct environment specification without branch dependencies
- **Directory Convention Resolution**: Resolve deployment paths using hierarchical directory structure
- **Matrix Generation**: Create deployment matrices for parallel execution
- **GitHub Actions Integration**: Seamless integration with GitHub Actions workflows

## Usage

The Label Resolver provides a CLI interface through `bin/resolver`:

### Basic Commands

```bash
# Resolve deployment from PR labels for specific environment(s)
bundle exec ruby label-resolver/bin/resolver resolve PR_NUMBER [ENVIRONMENTS]

# Test deployment workflow
bundle exec ruby label-resolver/bin/resolver test PR_NUMBER [ENVIRONMENTS]

# Simulate GitHub Actions environment
bundle exec ruby label-resolver/bin/resolver simulate PR_NUMBER [ENVIRONMENTS]

# Validate environment configuration
bundle exec ruby label-resolver/bin/resolver validate_env

# Debug workflow step-by-step
bundle exec ruby label-resolver/bin/resolver debug PR_NUMBER [ENVIRONMENTS]
```

**Environment Specification:**
- Single environment: `develop`
- Multiple environments: `develop,staging` (comma-separated)
- All environments: omit ENVIRONMENTS parameter

### Examples

```bash
# Resolve deployments for develop environment
./bin/resolver resolve 123 develop

# Test multiple environments simultaneously
./bin/resolver test 456 develop,staging

# Debug production deployment
./bin/resolver debug 789 production

# Deploy to all available environments
./bin/resolver resolve 123
```

### Workflow Integration

The resolver is typically called from GitHub Actions workflows:

```yaml
# Single environment deployment
- name: Resolve deployment targets
  uses: panicboat/deploy-actions/label-resolver@main
  with:
    pr_number: ${{ github.event.pull_request.number }}
    target_environments: ${{ inputs.target_environment }}

# Multiple environment deployment
- name: Resolve deployment targets
  uses: panicboat/deploy-actions/label-resolver@main
  with:
    pr_number: ${{ github.event.pull_request.number }}
    target_environments: "develop,staging"
```

### Environment Variables

The resolver sets the following environment variables for GitHub Actions:

- `DEPLOYMENT_TARGETS`: JSON array of deployment targets
- `DEPLOY_LABELS`: JSON array of deploy labels found
- `HAS_TARGETS`: Boolean indicating if deployment targets exist
- `SAFETY_STATUS`: Result of safety validation
- `MERGED_PR_NUMBER`: PR number for deployment tracking

### Action Outputs

The resolver provides the following GitHub Actions outputs:

- `targets`: JSON array of deployment targets for matrix strategy
- `has-targets`: Boolean indicating if targets exist (`true`/`false`)
- `safety-status`: Result of safety validation (`passed`/`failed`)

## Architecture

### Components

- **LabelResolverController**: Main orchestration logic
- **DetermineTargetEnvironment**: Multi-environment validation
- **GetLabels**: PR label extraction
- **ValidateDeploymentSafety**: Safety checks (currently simplified)
- **GenerateMatrix**: Deployment matrix generation for multiple environments

### Flow

1. **Label Extraction**: Get deploy labels from PR
2. **Environment Validation**: Validate all target environments exist
3. **Safety Validation**: Perform deployment safety checks
4. **Matrix Generation**: Create deployment targets for all environments based on directory structure
5. **Output Generation**: Format results for GitHub Actions with simplified outputs

## Configuration

The resolver uses `workflow-config.yaml` for configuration:

```yaml
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

directory_conventions:
  - root: "{service}"
    stacks:
      - name: terragrunt
        directory: "terragrunt/{environment}"
        targets: ["develop", "staging", "production"]
      - name: kubernetes
        directory: "kubernetes/overlays/{environment}"
        targets: ["develop", "staging", "production"]

services:
  - name: excluded-service
    exclude_from_automation: true
    exclusion_config:
      reason: "Manual deployment required"
      type: "permanent"
```

## Deploy Labels

The system recognizes labels in the format `deploy:service`:

- `deploy:auth` - Deploy auth service
- `deploy:api` - Deploy api service
- `deploy:frontend` - Deploy frontend service
- `deploy:all` - Deploy all non-excluded services

## Environment Targeting

**Trunk-based Development**: The resolver uses explicit environment targeting rather than branch-based mapping:

- Environments are specified directly as parameters
- No dependency on branch names for environment determination
- Supports any deployment environment defined in configuration

## Directory Structure Detection

The resolver automatically detects available stacks by checking directory existence:

```
{service}/
├── terragrunt/{environment}/     # Terragrunt stack
└── kubernetes/overlays/{environment}/  # Kubernetes stack
```

Only directories that actually exist will be included in the deployment matrix.

## Error Handling

The resolver provides comprehensive error handling:

- **Invalid Environment**: Clear error when target environment doesn't exist
- **Missing Labels**: Graceful handling of PRs without deploy labels
- **Configuration Errors**: Detailed validation of workflow configuration
- **Directory Detection**: Warnings for missing deployment directories

## Development

### Running Tests

```bash
cd action-scripts
bundle exec rspec spec/label-resolver/
```

### Local Testing

```bash
# Set up environment
export GITHUB_TOKEN=your_token
export GITHUB_REPOSITORY=owner/repo

# Test with real PR
./bin/resolver debug 123 develop
```
