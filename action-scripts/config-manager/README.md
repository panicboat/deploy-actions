# Config Manager

**English** | [🇯🇵 日本語](README-ja.md)

A Ruby-based configuration validation and management tool for GitHub Actions deployment automation.

## Overview

The Config Manager validates and manages workflow configuration files that define deployment environments, services, and automation rules. It provides comprehensive configuration validation, diagnostic tools, and templates for deployment automation setups optimized for trunk-based development.

## Features

- **Configuration Validation**: Validate `workflow-config.yaml` files with detailed error reporting
- **Environment Management**: List and test configured environments with AWS IAM roles
- **Service Configuration**: Manage service-specific deployment settings and exclusions
- **Directory Conventions**: Validate hierarchical directory structure configuration
- **Template Generation**: Generate configuration templates optimized
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
```

### Examples

```bash
# Validate current configuration
./bin/config-manager validate

# Test auth service in develop environment
./bin/config-manager test auth develop

# Show all configuration details
./bin/config-manager show

# Generate new configuration template
./bin/config-manager template > new-workflow-config.yaml
```

## Configuration Structure

The Config Manager manages `workflow-config.yaml` files with the following structure:

### Environments

Defines deployment environments without branch dependencies:

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
```

### Directory Conventions

Hierarchical directory structure for service discovery:

```yaml
stack_conventions:
  - root: "{service}"
    stacks:
      - name: terragrunt
        directory: "terragrunt/{environment}"
        targets: ["develop", "staging", "production"]
      - name: kubernetes
        directory: "kubernetes/overlays/{environment}"
        targets: ["develop", "staging", "production"]
```

### Services

Service-specific configurations and exclusions:

```yaml
services:
  - name: excluded-service
    exclude_from_automation: true
    exclusion_config:
      reason: "Manual deployment required due to special requirements"
      type: "permanent"

  - name: special-service
    stack_conventions:
      terragrunt: "custom/{service}/infra/{environment}"
```

## Validation Rules

The Config Manager enforces comprehensive validation:

### Environment Validation
- All environments must have `environment`, `aws_region`, `iam_role_plan`, and `iam_role_apply`
- AWS regions must follow standard format (`us-west-2`, `ap-northeast-1`, etc.)
- IAM role ARNs must be valid AWS ARN format
- Required environments: `develop`, `staging`, `production`

### Directory Convention Validation
- Root patterns must include `{service}` placeholder (unless empty)
- Stack directories must include `{environment}` placeholder
- Required stacks: `terragrunt` (minimum)
- Directory conventions must be an array

### Service Validation
- Service names cannot start with dot (`.`)
- Service-specific directory conventions must include `{service}` placeholder
- Excluded services must have `exclusion_config` with reason

## Placeholder Rules

Patterns in `stack_conventions[].root` and `stack_conventions[].stacks[].directory` accept `{name}` placeholders. The grammar:

- `name` must match `[a-z_][a-z0-9_]*` (lowercase letter or underscore followed by lowercase letters, digits, or underscores).
- Strings like `{Team}`, `{my-var}`, or `{a b}` are not recognized as placeholders; the entire literal is rejected by `validate`.
- The same placeholder name may appear multiple times in one pattern. Expansion uses the same value at every occurrence; extraction requires the same value at every occurrence.

### Built-in placeholders

- `{service}` is required in `root` (unless `root` is the empty string).
- `{environment}` is optional in `stacks[].directory` — omitting it makes the stack environment-agnostic.

### Custom placeholders

Any additional placeholder name acts as a capture. After resolving a deploy target, its value is emitted as a top-level key on the matrix item (see repository-root `README.md` `## Matrix Output`). Custom placeholder names are rejected at validate time if they would collide with:

- A reserved DeploymentTarget field: `stack`, `working_directory`, `stack_convention_root`.
- Any attribute key used under `environments[].stacks[].*` (e.g. `aws_region`).

### Structural equivalence

If two conventions share a stack name and have placeholders at the same positions but with different names (e.g. `{team}/{service}` and `{team99}/{service}` both for stack `terragrunt`), `validate` rejects the configuration: the captured key name would otherwise depend on YAML order.

### Implementation

Placeholder parsing, expansion, and extraction are centralized in `Entities::PatternMatcher` (`shared/entities/pattern_matcher.rb`). All three components (`config-manager`, `label-dispatcher`, `label-resolver`) call into it, so the grammar above is authoritative.

## Template Generation

Generate configuration templates optimized:

```bash
./bin/config-manager template
```

Generated templates include:
- Environment configurations without branch fields
- Modern directory conventions
- Service exclusion examples
- Comprehensive documentation

## Diagnostic Tools

Comprehensive health checks for deployment automation:

```bash
./bin/config-manager diagnostics
```

Checks include:
- Configuration file validation
- Environment variable availability
- Git repository status
- Configuration file location
- Directory structure integrity

## Architecture

### Components

- **ConfigManagerController**: Main orchestration and CLI interface
- **ValidateConfig**: Comprehensive configuration validation
- **ConfigClient**: Configuration loading and parsing
- **ConsolePresenter**: Human-readable output formatting

### Validation Flow

1. **Structure Validation**: YAML structure and required sections
2. **Environment Validation**: AWS credentials and region validation
3. **Service Validation**: Service configurations and exclusions
4. **Directory Validation**: Directory conventions and placeholders
5. **Summary Generation**: Validation results and statistics

## Error Handling

Detailed error reporting with:
- **Specific Error Messages**: Pinpoint configuration issues
- **Validation Context**: Clear indication of problematic sections
- **Suggestions**: Guidance for fixing common configuration problems
- **Summary Statistics**: Overview of configuration health

## Integration

The Config Manager integrates with:
- **Label Resolver**: Provides configuration for deployment targeting
- **Label Dispatcher**: Validates service and directory configurations
- **GitHub Actions**: Environment validation for CI/CD workflows

## Development

### Running Tests

```bash
cd action-scripts
bundle exec rspec spec/config-manager/
```

### Local Testing

```bash
# Test with custom configuration
cp workflow-config.yaml test-config.yaml
./bin/config-manager validate

# Test service configuration
./bin/config-manager test myservice develop
```

## Migration Notes

**Trunk-based Migration**: This version removes branch-based configuration dependencies:

- **Branch fields removed**: No longer needed in environment configurations
- **Direct environment targeting**: Use explicit environment parameters in workflows
- **Backward compatibility**: Old configurations will show warnings but continue to work
- **Template updates**: New templates exclude branch configurations

This migration provides:
- Simplified configuration management
- Better support for trunk-based development
- More flexible deployment strategies
- Cleaner separation of concerns between branch management and deployment configuration
