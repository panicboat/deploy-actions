# Label Dispatcher

**English** | [🇯🇵 日本語](README-ja.md)

A Ruby-based service change detection and label management tool for GitHub Actions deployment automation.

## Overview

The Label Dispatcher analyzes file changes in pull requests, detects affected services, and automatically manages deployment labels. It serves as the entry point for deployment automation by identifying which services need to be deployed based on code changes.

## Features

- **Change Detection**: Analyze Git diffs to identify modified files
- **Service Mapping**: Map file changes to service deployments
- **Label Management**: Automatically add/remove deployment labels on PRs
- **Exclusion Support**: stack ごとの照合条件で除外
- **GitHub Integration**: Seamless PR label management
- **Directory Conventions**: Flexible service directory detection
- **Deployment Strategy Agnostic**: Works with any branching strategy or development workflow

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

変更ファイルを定義された stack のパスに照合し、サービス・環境・任意 placeholder を抽出します。パスに環境名がない場合は、その stack の定義環境ごとに評価します。環境共通の stack は environment が null の照合として扱います。

各照合に除外条件を適用し、除外されない照合が一つでもあるサービスを一度だけラベル対象にします。サービス全体のディレクトリを検出対象にする場合は、そのパスも stack に定義します。削除されたファイルも照合するため、ディレクトリの存在は要求しません。

## Configuration

設定仕様はルートの [Configuration](../../README.md#configuration) を参照してください。

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

検出結果にはラベル、変更ファイル、対象サービスを含みます。GitHub Actions では `deploy-labels`、`labels-added`、`labels-removed`、`services-detected`、`has-changes` を出力します。除外状態の確認には [Service Diagnosis](../config-manager/README.md#service-diagnosis) を使います。

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

## Safety Features

- **Change Validation**: Ensures only relevant changes trigger deployments
- **Configuration Validation**: Validates configuration before processing
- **Permission Checks**: Verifies GitHub token permissions
- **Exclusion Respect**: 各照合の除外条件を適用
- **Audit Trail**: Logs all label operations for troubleshooting
