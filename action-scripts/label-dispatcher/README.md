# Label Dispatcher

**English** | [🇯🇵 日本語](README-ja.md)

A Ruby-based service change detection and label management tool for GitHub Actions deployment automation.

## Overview

The Label Dispatcher analyzes file changes in pull requests, detects affected services, and automatically manages deployment labels. It serves as the entry point for deployment automation by identifying which services need to be deployed based on code changes.

## Features

- **Change Detection**: Analyze Git diffs to identify modified files
- **Service Mapping**: Map file changes to service deployments
- **Label Management**: Automatically add/remove deployment labels on PRs
- **Exclusion Support**: Exclude matches using conditions defined for each stack
- **GitHub Integration**: Seamless PR label management
- **Directory Conventions**: Flexible service directory detection
- **Deployment Strategy Agnostic**: Works with any branching strategy or development workflow

## Usage

Run commands from the `action-scripts` directory.

The Label Dispatcher provides a CLI interface through `label-dispatcher/bin/dispatcher`:

### Commands

Dispatch labels for a PR (automatic mode).

```bash
bundle exec ruby label-dispatcher/bin/dispatcher dispatch PR_NUMBER
```

Test change detection without PR interaction.

```bash
bundle exec ruby label-dispatcher/bin/dispatcher test
```

Test with specific git references.

```bash
bundle exec ruby label-dispatcher/bin/dispatcher test --base-ref=main --head-ref=feature/auth
```

Simulate GitHub Actions environment.

```bash
bundle exec ruby label-dispatcher/bin/dispatcher simulate PR_NUMBER
```

Validate environment configuration.

```bash
bundle exec ruby label-dispatcher/bin/dispatcher validate_env
```

Show usage examples and tips.

```bash
bundle exec ruby label-dispatcher/bin/dispatcher help_usage
```

### Workflow Integration

The dispatcher is typically called from GitHub Actions workflows:

```yaml
- name: Dispatch labels
  uses: panicboat/deploy-actions/label-dispatcher@v1
  with:
    pr-number: ${{ github.event.pull_request.number }}
    repository: ${{ github.repository }}
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

### Environment Variables

The dispatcher sets the following environment variables for GitHub Actions:

- `SERVICES_DETECTED`: JSON array of detected services
- `LABELS_ADDED`: JSON array of labels that were added
- `LABELS_REMOVED`: JSON array of labels that were removed
- `HAS_CHANGES`: Boolean indicating if changes were detected

## Change Matching

Matches changed files against configured stack paths and extracts services, environments, and arbitrary placeholders. A stack path resolves to a directory, so a changed file matches only when it is located under that directory; a file whose own path equals the resolved path is ignored. A stack with `environments` accepts only its declared names; a path without an environment name is evaluated for each declared environment. A stack with neither attribute map uses the environment captured from the changed path. A stack with `attributes` is evaluated with `environment: null`.

Applies exclusion conditions to each match. A service receives one label if at least one match is not excluded. To detect changes throughout a service directory, include that path in a stack definition. Directories need not exist because deleted files are also matched.

## Configuration

See the root [Configuration](../../README.md#configuration) section for the configuration schema.

## Architecture

The Label Dispatcher follows a clean architecture pattern:

### Controllers

- `LabelDispatcherController`: Orchestrates the dispatch process

### Use Cases

- `DetectChangedServices`: Analyzes file changes and maps to services
- `ManageLabels`: Handles PR label operations

### Infrastructure

- `GitHubClient`: GitHub API interactions
- `FileSystemClient`: Git operations and file analysis
- `ConfigClient`: Configuration management

## Required Environment Variables

- `GITHUB_TOKEN`: Required for GitHub API access
- `GITHUB_REPOSITORY`: Repository name (owner/repo format)
- `GITHUB_ACTIONS`: Enables GitHub Actions output format
- `WORKFLOW_CONFIG_PATH`: Path to configuration file (optional, defaults to workflow-config.yaml)

## Detection Results

Detection results include labels, changed files, and affected services. GitHub Actions outputs are `deploy-labels`, `labels-added`, `labels-removed`, `services-detected`, and `has-changes`. Use [Service Diagnosis](../config-manager/README.md#service-diagnosis) to inspect exclusion status.

## Error Handling

The dispatcher provides comprehensive error handling:

- **API Failures**: Retries with exponential backoff
- **Git Operations**: Handles missing refs gracefully
- **Configuration Issues**: Provides detailed error messages
- **Permission Errors**: Clear guidance for token permissions

## Development

### Dependencies

- Ruby ([.ruby-version](../.ruby-version))
- Bundler
- Thor (CLI framework)
- Octokit (GitHub API)
- Git (system dependency)

### Testing

Inspect change detection in the current working directory.

```bash
bundle exec ruby label-dispatcher/bin/dispatcher test
```

Test with specific refs.

```bash
bundle exec ruby label-dispatcher/bin/dispatcher test --base-ref=main --head-ref=HEAD
```

Validate environment.

```bash
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

## Safety Features

- **Change Validation**: Ensures only relevant changes trigger deployments
- **Configuration Validation**: Validates configuration before processing
- **Permission Checks**: Verifies GitHub token permissions
- **Exclusion Respect**: Apply exclusion conditions to each match
- **Audit Trail**: Logs all label operations for troubleshooting
