# Label Dispatcher

A Ruby-based service change detection and label management tool for GitHub Actions automation.

## Overview

The Label Dispatcher analyzes file changes in pull requests, detects affected services, and automatically manages deployment labels. It serves as the entry point for deployment automation by identifying which services need to be deployed based on code changes.

## Features

- **Change Detection**: Analyze Git diffs to identify modified files
- **Service Mapping**: Map file changes to service deployments
- **Label Management**: Automatically add/remove deployment labels on PRs
- **Exclusion Support**: Handle services excluded from automation
- **GitHub Integration**: Seamless PR label and comment management
- **Directory Conventions**: Flexible service directory detection

## Usage

The Label Dispatcher provides a CLI interface through `bin/dispatcher`:

### Basic Commands

```bash
# Dispatch labels for a PR (automatic mode)
bundle exec ruby label-dispatcher/bin/dispatcher dispatch PR_NUMBER

# Test change detection without PR interaction
bundle exec ruby label-dispatcher/bin/dispatcher test

# Test with specific git references
bundle exec ruby label-dispatcher/bin/dispatcher test --base-ref=main --head-ref=feature/auth

# Simulate GitHub Actions environment
bundle exec ruby label-dispatcher/bin/dispatcher simulate PR_NUMBER

# Validate environment configuration
bundle exec ruby label-dispatcher/bin/dispatcher validate_env

# Show usage examples and tips
bundle exec ruby label-dispatcher/bin/dispatcher help_usage
```

### Workflow Integration

The dispatcher is typically called from GitHub Actions workflows:

```yaml
- name: Dispatch labels
  uses: panicboat/deploy-actions/label-dispatcher@main
  with:
    pr-number: ${{ github.event.pull_request.number }}
    repository: ${{ github.repository }}
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

## Core Logic

### 1. Change Detection

Analyzes Git differences to identify modified files:
- Compares base and head commits
- Identifies added, modified, and deleted files
- Filters out non-deployment relevant changes
- Supports both API-based and Git-based detection

### 2. Service Mapping

Maps file changes to service deployments:
- Uses directory conventions to identify services
- Supports both default and custom directory patterns
- Handles multiple deployment stacks (Terragrunt, Kubernetes)
- Applies service-specific configuration overrides

### 3. Label Management

Automatically manages PR labels:
- Adds `deploy:service-name` labels for changed services
- Removes labels for services no longer changed
- Maintains label consistency across PR updates
- Supports batch label operations

### 4. Exclusion Handling

Manages services excluded from automation:
- Identifies excluded services from configuration
- Provides exclusion reason and type information
- Updates PR comments with exclusion details
- Supports temporary and permanent exclusions

## Configuration

The dispatcher uses `workflow-config.yaml` for configuration:

```yaml
# Directory conventions for service detection (hierarchical structure)
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
      reason: "Manual deployment required due to special requirements"
      type: "permanent"

  - name: legacy-service
    exclude_from_automation: true
    exclusion_config:
      reason: "Migration in progress"
      type: "temporary"
```

## Architecture

The Label Dispatcher follows a clean architecture pattern:

### Controllers
- `LabelDispatcherController`: Orchestrates the dispatch process

### Use Cases
- `DetectChangedServices`: Analyzes file changes and maps to services
- `ManageLabels`: Handles PR label operations and comments

### Infrastructure
- `GitHubClient`: GitHub API interactions
- `FileSystemClient`: Git operations and file analysis
- `ConfigClient`: Configuration management

## Output Format

The dispatcher outputs results in GitHub Actions format:

```bash
# Environment variables set
SERVICES_DETECTED='["service1","service2"]'
LABELS_ADDED='["deploy:service1","deploy:service2"]'
LABELS_REMOVED='["deploy:old-service"]'
HAS_CHANGES=true
```

## Environment Variables

- `GITHUB_TOKEN`: Required for GitHub API access
- `GITHUB_REPOSITORY`: Repository name (owner/repo format)
- `GITHUB_ACTIONS`: Enables GitHub Actions output format
- `WORKFLOW_CONFIG_PATH`: Path to configuration file

## Service Detection Logic

The dispatcher uses the following logic to detect services:

1. **File Analysis**: Examine changed files in the PR
2. **Pattern Matching**: Match file paths against directory conventions
3. **Service Extraction**: Extract service names from matched patterns
4. **Configuration Lookup**: Apply service-specific configurations
5. **Exclusion Filtering**: Remove excluded services from results

### Example Detection

For a file change in `services/auth/terragrunt/envs/develop/main.tf`:
- Matches pattern: `services/{service}/terragrunt/envs/{environment}`
- Extracts service: `auth`
- Applies configuration for `auth` service
- Adds label: `deploy:auth`

## Error Handling

The dispatcher provides comprehensive error handling:

- **API Failures**: Retries with exponential backoff
- **Git Operations**: Handles missing refs gracefully
- **Configuration Issues**: Provides detailed error messages
- **Permission Errors**: Clear guidance for token permissions

## Development

### Dependencies

- Ruby 3.4+
- Bundler
- Thor (CLI framework)
- Octokit (GitHub API)
- Git (system dependency)

### Testing

```bash
# Test with current working directory
bundle exec ruby label-dispatcher/bin/dispatcher test

# Test with specific refs
bundle exec ruby label-dispatcher/bin/dispatcher test --base-ref=main --head-ref=HEAD

# Validate environment
bundle exec ruby label-dispatcher/bin/dispatcher validate_env
```

## Integration Points

The Label Dispatcher integrates with:

1. **Config Manager**: Uses validated configuration files
2. **Label Resolver**: Provides labels for deployment resolution
3. **GitHub Actions**: Triggers on PR events and updates
4. **Git Repository**: Analyzes file changes and history

## Label Conventions

The dispatcher uses standardized label formats:

- `deploy:service-name` - Deploy specific service
- `deploy:all` - Deploy all services (special case)
- Labels are automatically managed and synchronized

## Comment Management

The dispatcher updates PR comments with:

- **Detected Services**: List of services that will be deployed
- **Excluded Services**: Services excluded from automation with reasons
- **File Changes**: Summary of relevant file modifications
- **Configuration Status**: Validation and processing status

## Safety Features

- **Change Validation**: Ensures only relevant changes trigger deployments
- **Configuration Validation**: Validates configuration before processing
- **Permission Checks**: Verifies GitHub token permissions
- **Exclusion Respect**: Honors service exclusion configurations
- **Audit Trail**: Logs all label operations for troubleshooting
