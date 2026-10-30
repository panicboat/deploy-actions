# Label Resolver

**English** | [🇯🇵 日本語](README-ja.md)

A Ruby-based deployment resolution tool that converts PR labels into deployment targets for GitHub Actions automation using explicit environment targeting.

## Overview

The Label Resolver analyzes PR labels and generates deployment targets for specified environments. It creates deployment matrices for multi-service deployments, serving as the central orchestrator for deployment automation decisions.

## Features

- **Label Resolution**: Extract deployment labels from PR information
- **Explicit Environment Targeting**: Direct environment specification without branch dependencies
- **Directory Convention Resolution**: Resolve deployment paths using hierarchical directory structure
- **Matrix Generation**: Create deployment matrices for parallel execution
- **GitHub Actions Integration**: Seamless integration with GitHub Actions workflows

## Usage

Run commands from the `action-scripts` directory.

The Label Resolver provides a CLI interface through `label-resolver/bin/resolver`:

### Commands

Resolve deployment from PR labels for specific environment(s).

```bash
bundle exec ruby label-resolver/bin/resolver resolve PR_NUMBER [ENVIRONMENTS]
```

**Environment Specification:**

- Single environment: `develop`
- Multiple environments: `develop,staging` (comma-separated)
- All environments: omit ENVIRONMENTS parameter

Resolve the targets of one service, or of every service, without a pull request. This command does not call the GitHub API and needs no `GITHUB_TOKEN`.

```bash
bundle exec ruby label-resolver/bin/resolver targets SERVICE [ENVIRONMENTS]
```

**Service Specification:**

- Single service: a name matching `[a-zA-Z0-9_-]+`
- Every service: `all`

ENVIRONMENTS follows the same specification as `resolve`. A service name outside the pattern, or an environment that is neither declared nor discovered, fails with exit code 1.

### Examples

Resolve deployments for develop environment.

```bash
bundle exec ruby label-resolver/bin/resolver resolve 123 develop
```

Resolve deployments for multiple environments simultaneously.

```bash
bundle exec ruby label-resolver/bin/resolver resolve 456 develop,staging
```

Resolve deployment targets for all declared and discovered environments.

```bash
bundle exec ruby label-resolver/bin/resolver resolve 123
```

Resolve the targets of one service for the develop environment without a pull request.

```bash
bundle exec ruby label-resolver/bin/resolver targets demo develop
```

Resolve the targets of every service for all environments.

```bash
bundle exec ruby label-resolver/bin/resolver targets all
```

### Workflow Integration

The resolver is typically called from GitHub Actions workflows:

Single environment deployment.

```yaml
- name: Resolve deployment targets
  uses: panicboat/deploy-actions/label-resolver@v0.1.0
  with:
    pr-number: ${{ github.event.pull_request.number }}
    repository: ${{ github.repository }}
    github-token: ${{ secrets.GITHUB_TOKEN }}
    environments: ${{ inputs.target_environment }}
```

Multiple environment deployment.

```yaml
- name: Resolve deployment targets
  uses: panicboat/deploy-actions/label-resolver@v0.1.0
  with:
    pr-number: ${{ github.event.pull_request.number }}
    repository: ${{ github.repository }}
    github-token: ${{ secrets.GITHUB_TOKEN }}
    environments: "develop,staging"
```

### Action Outputs

The resolver provides the following GitHub Actions outputs:

- `targets`: JSON array of deployment targets for matrix strategy
- `has-targets`: Boolean indicating if targets exist (`true`/`false`)

The `targets` command provides the same two outputs, computed from the candidates that are not excluded, and one more:

- `candidates`: JSON array of every candidate including the excluded ones, each in the form `{"target": <matrix item>, "excluded": <bool>, "root": "<root>"}`

An unknown service is not an error: `targets` is `[]`, `has-targets` is `false`, and `candidates` is `[]`.

## Architecture

### Components

- **LabelResolverController**: Main orchestration logic
- **GetLabels**: PR label extraction
- **GenerateMatrix**: Deployment matrix generation from the deploy labels of a PR, without the excluded candidates
- **ListServiceTargets**: Service name validation and the listing of the targets of one service or all, with every candidate including the excluded ones
- **ListCandidates**: Environment validation and candidate enumeration shared by `GenerateMatrix` and `ListServiceTargets`

### Flow

`resolve`:

1. **Label Extraction**: Get deploy labels from PR
2. **Candidate Listing**: `ListCandidates` validates that all target environments exist and enumerates the candidates from the directory structure
3. **Matrix Generation**: `GenerateMatrix` keeps the candidates that are not excluded as deployment targets
4. **Output Generation**: Format results for GitHub Actions with simplified outputs

`targets`:

1. **Service Validation**: `ListServiceTargets` rejects a service name outside `[a-zA-Z0-9_-]+`
2. **Candidate Listing**: `ListCandidates` validates the target environments and enumerates the candidates of the service (every service for `all`)
3. **Output Generation**: `targets` and `has-targets` come from the candidates that are not excluded, and `candidates` lists every candidate with its exclusion and root

## Configuration

See the root [Configuration](../../README.md#configuration) and [Matrix Output](../../README.md#matrix-output) sections for the schema and matrix format.

## Deploy Labels

The system recognizes labels in the format `deploy:service`:

- `deploy:auth` - Deploy auth service
- `deploy:api` - Deploy api service
- `deploy:frontend` - Deploy frontend service
- `deploy:all` - Resolve targets for all existing services

The prefix and additional prefixes are configurable; see the root [Labels](../../README.md#labels) section.

## Environment Targeting

**Trunk-based Development**: The resolver uses explicit environment targeting rather than branch-based mapping:

- Environments are specified directly as parameters
- No dependency on branch names for environment determination
- Supports environments declared in configuration or discovered from stack paths
- Supports targeting multiple environments in one invocation

## Target Resolution

Selects requested environments from each stack's declared or discovered environments and enumerates existing directories across all paths. Omitting the environment selection or providing only whitespace selects the union of declared and discovered names. Targets with `attributes` are shared across environments and generated once per directory.

`deploy:all` discovers all services from the configured paths. Targets matching exclusion conditions are omitted from the matrix. Missing paths produce a valid empty result; unknown environments, enumeration errors, and conflicting captured values cause failures.

## Error Handling

The resolver provides comprehensive error handling:

- **Invalid Environment**: Clear error when target environment doesn't exist
- **Invalid Service Name**: `targets` rejects a service name outside `[a-zA-Z0-9_-]+`
- **Missing Labels**: Graceful handling of PRs without deploy labels
- **Configuration Errors**: Detailed validation of workflow configuration
- **Directory Detection**: Missing paths produce a valid empty result

## Development

### Running Tests

```bash
cd action-scripts
bundle exec rspec spec/label-resolver/
```

### Local Testing

Set up environment.

```bash
export GITHUB_TOKEN=your_token
export GITHUB_REPOSITORY=owner/repo
export SOURCE_REPO_PATH=your_source_path
export WORKFLOW_CONFIG_PATH=workflow-config.yaml
```

Resolve a real PR.

```bash
bundle exec ruby label-resolver/bin/resolver resolve 123 develop
```
