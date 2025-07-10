# Config Manager

A Ruby-based configuration validation and management tool for GitHub Actions deployment automation.

## Overview

The Config Manager validates and manages workflow configuration files that define deployment environments, services, and automation rules. It provides comprehensive configuration validation, diagnostic tools, and templates for deployment automation setups.

## Features

- **Configuration Validation**: Validate `workflow-config.yaml` files with detailed error reporting
- **Environment Management**: List and test configured environments with AWS IAM roles
- **Service Configuration**: Manage service-specific deployment settings and exclusions
- **Directory Conventions**: Validate hierarchical directory structure configuration
- **Template Generation**: Generate configuration templates with examples
- **Diagnostic Tools**: Comprehensive health checks for deployment setup

## Usage

The Config Manager provides a CLI interface through `bin/config-manager`:

### Basic Commands

```bash
# Validate configuration file
bundle exec ruby config-manager/bin/config-manager validate

# Show parsed configuration
bundle exec ruby config-manager/bin/config-manager show

# List all environments
bundle exec ruby config-manager/bin/config-manager environments

# List all services
bundle exec ruby config-manager/bin/config-manager services

# List services excluded from automation
bundle exec ruby config-manager/bin/config-manager excluded_services

# Test specific service configuration
bundle exec ruby config-manager/bin/config-manager test SERVICE_NAME ENVIRONMENT

# Run diagnostic checks
bundle exec ruby config-manager/bin/config-manager diagnostics

# Generate configuration template
bundle exec ruby config-manager/bin/config-manager template

# Check if configuration file exists and is readable
bundle exec ruby config-manager/bin/config-manager check_file
```

### Configuration File

The tool expects a `workflow-config.yaml` file in the working directory with the following structure:

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
  root: "{service}"
  stacks:
    - name: terragrunt
      directory: "terragrunt/{environment}"
    - name: kubernetes
      directory: "kubernetes/overlays/{environment}"

services:
  - name: excluded-service
    exclude_from_automation: true
    exclusion_config:
      reason: "Manual deployment required"
      type: "permanent"

branch_patterns:
  develop: develop
  staging: staging
  production: production
```

## Architecture

The Config Manager follows a clean architecture pattern:

- **Controllers**: Handle CLI commands and coordinate use cases
- **Use Cases**: Implement business logic for configuration validation
- **Infrastructure**: File system and configuration loading
- **Presenters**: Format output for console and GitHub Actions

## Integration

This tool is designed to be used from composite GitHub Actions. The typical workflow:

1. **Checkout**: Action checks out the deploy-actions repository
2. **Configuration Copy**: Source repository's config file is copied to `workflow-config.yaml`
3. **Validation**: Config Manager validates the configuration
4. **Processing**: Other tools use the validated configuration

## Environment Variables

- `WORKFLOW_CONFIG_PATH`: Path to configuration file (default: `workflow-config.yaml`)
- `GITHUB_ACTIONS`: Enables GitHub Actions output format
- `GITHUB_TOKEN`: Required for GitHub API operations
- `GITHUB_REPOSITORY`: Repository name for GitHub operations

## Error Handling

The tool provides detailed error messages and appropriate exit codes:

- **Exit 0**: Success
- **Exit 1**: Configuration validation failed or file not found
- **Exit 2**: Environment/dependency issues

## Development

### Dependencies

- Ruby 3.4+
- Bundler
- Thor (CLI framework)
- YAML (configuration parsing)

### Testing

```bash
# Check configuration file exists
bundle exec ruby config-manager/bin/config-manager check_file

# Test with specific environment
bundle exec ruby config-manager/bin/config-manager test my-service develop

# Run full diagnostics
bundle exec ruby config-manager/bin/config-manager diagnostics

# List all environments
bundle exec ruby config-manager/bin/config-manager environments

# List all services
bundle exec ruby config-manager/bin/config-manager services

# List services excluded from automation
bundle exec ruby config-manager/bin/config-manager excluded_services
```

## Output Formats

The tool supports two output formats:

- **Console**: Human-readable format with colors and emojis
- **GitHub Actions**: Structured format with `::error::` and `::warning::` annotations

The format is automatically selected based on the `GITHUB_ACTIONS` environment variable.
