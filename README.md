# Deploy Actions

**English** | [🇯🇵 日本語](README-ja.md)

A comprehensive GitHub Actions automation toolkit for multi-service deployment orchestration with Terragrunt and Kubernetes.

## Overview

Deploy Actions provides a complete solution for automating deployments across multiple services and environments. It combines intelligent change detection, configuration validation, and deployment orchestration to streamline CI/CD workflows for complex multi-service architectures.

## Key Features

- **Intelligent Change Detection**: Automatically detects changed services from file modifications
- **Configuration Management**: Validates and manages deployment configurations
- **Deployment Resolution**: Converts PR labels to deployment targets
- **Multi-Stack Support**: Supports Terragrunt and Kubernetes deployments
- **Security-First**: Built-in safety checks and IAM role management
- **Matrix Generation**: Creates deployment matrices for parallel execution

## Architecture

The toolkit consists of three main components:

### 1. Config Manager (`config-manager/`)
Validates and manages workflow configuration files that define deployment environments, services, and automation rules.

**Key Features:**
- Configuration validation with detailed error reporting
- Environment and service management
- Directory convention validation
- Template generation

### 2. Label Dispatcher (`label-dispatcher/`)
Analyzes file changes and automatically creates deployment labels for modified services.

**Key Features:**
- Change detection from git diff
- Service discovery from directory patterns
- Automatic label generation
- Exclusion handling

### 3. Label Resolver (`label-resolver/`)
Converts PR labels and branch information into deployment targets for GitHub Actions automation.

**Key Features:**
- Label-to-target resolution
- Environment detection from branches
- Deployment matrix generation
- Safety validation

## Composite Actions

The toolkit provides ready-to-use composite actions:

### Label Dispatcher
```yaml
- uses: panicboat/deploy-actions/label-dispatcher@main
  with:
    pr-number: ${{ github.event.pull_request.number }}
    repository: ${{ github.repository }}
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

### Label Resolver
```yaml
- uses: panicboat/deploy-actions/label-resolver@main
  with:
    action-type: plan  # or apply
    pr-number: ${{ github.event.pull_request.number }}
    repository: ${{ github.repository }}
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

### Apply Terragrunt
```yaml
- uses: panicboat/deploy-actions/apply-terragrunt@main
  with:
    deployment-targets: ${{ steps.resolve.outputs.deployment-targets }}
    action-type: plan  # or apply
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

## Configuration

The toolkit uses a centralized `workflow-config.yaml` file:

```yaml
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

# Directory structure conventions
directory_conventions:
  - root: "{service}"
    stacks:
      - name: terragrunt
        directory: "terragrunt/{environment}"
      - name: kubernetes
        directory: "kubernetes/overlays/{environment}"

# Service-specific configurations
services:
  - name: excluded-service
    exclude_from_automation: true
    exclusion_config:
      reason: "Manual deployment required"
      type: "permanent"

# Branch-to-environment mapping
branch_patterns:
  develop: develop
  staging: staging
  production: production
```

## Directory Structure Support

The toolkit supports flexible directory structures:

### Pattern 1: Service-First Structure
```yaml
directory_conventions:
  - root: "{service}"
    stacks:
      - name: terragrunt
        directory: "terragrunt/{environment}"
      - name: kubernetes
        directory: "kubernetes/overlays/{environment}"
```

Results in:
- `my-service/terragrunt/develop/`
- `my-service/kubernetes/overlays/develop/`

### Pattern 2: Stack-First Structure
```yaml
directory_conventions:
  - root: ""
    stacks:
      - name: terragrunt
        directory: "terragrunt/{service}/{environment}"
      - name: kubernetes
        directory: "kubernetes/{service}/overlays/{environment}"
```

Results in:
- `terragrunt/my-service/develop/`
- `kubernetes/my-service/overlays/develop/`

### Pattern 3: Multiple Directory Conventions
```yaml
directory_conventions:
  - root: "apps/web/{service}"
    stacks:
      - name: terragrunt
        directory: "terragrunt/{environment}"
  - root: "services/{service}"
    stacks:
      - name: terragrunt
        directory: "terragrunt/{environment}"
      - name: kubernetes
        directory: "kubernetes/overlays/{environment}"
```

Results in:
- `apps/web/my-service/terragrunt/develop/`
- `services/my-service/terragrunt/develop/`
- `services/my-service/kubernetes/overlays/develop/`

## Workflow Integration

### 1. Change Detection Workflow
```yaml
name: Detect Changes and Create Labels
on:
  pull_request:
    types: [opened, synchronize, reopened]

jobs:
  detect-changes:
    runs-on: ubuntu-latest
    steps:
      - name: Dispatch Labels
        uses: panicboat/deploy-actions/label-dispatcher@main
        with:
          pr-number: ${{ github.event.pull_request.number }}
          repository: ${{ github.repository }}
          github-token: ${{ secrets.GITHUB_TOKEN }}
```

### 2. Deployment Workflow
```yaml
name: Deploy Infrastructure
on:
  pull_request:
    types: [labeled]

jobs:
  plan:
    runs-on: ubuntu-latest
    if: contains(github.event.label.name, 'deploy:')
    steps:
      - name: Resolve Deployment Targets
        id: resolve
        uses: panicboat/deploy-actions/label-resolver@main
        with:
          action-type: plan
          pr-number: ${{ github.event.pull_request.number }}
          repository: ${{ github.repository }}
          github-token: ${{ secrets.GITHUB_TOKEN }}

      - name: Deploy with Terragrunt
        uses: panicboat/deploy-actions/apply-terragrunt@main
        with:
          deployment-targets: ${{ steps.resolve.outputs.deployment-targets }}
          action-type: plan
          github-token: ${{ secrets.GITHUB_TOKEN }}
```

## Environment Variables

### Required
- `GITHUB_TOKEN`: GitHub API access token
- `GITHUB_REPOSITORY`: Repository name (owner/repo format)

### Optional
- `WORKFLOW_CONFIG_PATH`: Path to configuration file (default: `workflow-config.yaml`)
- `SOURCE_REPO_PATH`: Path to source repository checkout
- `GITHUB_ACTIONS`: Enables GitHub Actions output format
- `GITHUB_REF_NAME`: Current branch name

## Development

### Prerequisites
- Ruby 3.4+
- Bundler
- Git

### Setup
```bash
# Clone the repository
git clone https://github.com/panicboat/deploy-actions.git
cd deploy-actions

# Install dependencies
bundle install

# Run tests
bundle exec rspec
```

### Testing Individual Components
```bash
# Test config manager
bundle exec ruby config-manager/bin/config-manager validate

# Test label dispatcher
bundle exec ruby label-dispatcher/bin/dispatcher detect

# Test Label Resolver
bundle exec ruby label-resolver/bin/resolver resolve PR_NUMBER
```

## Security Features

- **IAM Role Integration**: Secure AWS credentials management
- **PR-based Deployment**: Deployments only triggered from valid PRs
- **Branch Validation**: Environment-specific branch restrictions
- **Configuration Validation**: Comprehensive safety checks
- **Audit Trail**: Detailed logging for all deployment decisions

## Error Handling

The toolkit provides comprehensive error handling:

- **Configuration Errors**: Detailed validation messages
- **API Failures**: Retry logic with exponential backoff
- **Permission Issues**: Clear IAM role guidance
- **Network Issues**: Graceful degradation

## Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests for new functionality
5. Run the test suite
6. Submit a pull request

## License

This project is licensed under the MIT License - see the LICENSE file for details.

## Support

For issues and questions:
- Check the [documentation](./action-scripts/) for detailed component information
- Open an issue on GitHub
- Review the example workflows in the repository
