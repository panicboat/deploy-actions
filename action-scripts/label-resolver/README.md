# Label Resolver

**English** | [🇯🇵 Japanese](README-ja.md)

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

Run commands from the `action-scripts` directory.

The Label Resolver provides a CLI interface through `label-resolver/bin/resolver`:

### Commands

Resolve deployment from PR labels for specific environment(s).

```bash
bundle exec ruby label-resolver/bin/resolver resolve PR_NUMBER [ENVIRONMENTS]
```

Inspect deployment target resolution.

```bash
bundle exec ruby label-resolver/bin/resolver test PR_NUMBER [ENVIRONMENTS]
```

Simulate GitHub Actions environment.

```bash
bundle exec ruby label-resolver/bin/resolver simulate PR_NUMBER [ENVIRONMENTS]
```

Validate environment configuration.

```bash
bundle exec ruby label-resolver/bin/resolver validate_env
```

Debug workflow step-by-step.

```bash
bundle exec ruby label-resolver/bin/resolver debug PR_NUMBER [ENVIRONMENTS]
```

**Environment Specification:**

- Single environment: `develop`
- Multiple environments: `develop,staging` (comma-separated)
- All environments: omit ENVIRONMENTS parameter

### Examples

Resolve deployments for develop environment.

```bash
bundle exec ruby label-resolver/bin/resolver resolve 123 develop
```

Test multiple environments simultaneously.

```bash
bundle exec ruby label-resolver/bin/resolver test 456 develop,staging
```

Debug production deployment.

```bash
bundle exec ruby label-resolver/bin/resolver debug 789 production
```

Resolve deployment targets for all configured environments.

```bash
bundle exec ruby label-resolver/bin/resolver resolve 123
```

### Workflow Integration

The resolver is typically called from GitHub Actions workflows:

Single environment deployment.

```yaml
- name: Resolve deployment targets
  uses: panicboat/deploy-actions/label-resolver@v1
  with:
    pr-number: ${{ github.event.pull_request.number }}
    repository: ${{ github.repository }}
    github-token: ${{ secrets.GITHUB_TOKEN }}
    environments: ${{ inputs.target_environment }}
```

Multiple environment deployment.

```yaml
- name: Resolve deployment targets
  uses: panicboat/deploy-actions/label-resolver@v1
  with:
    pr-number: ${{ github.event.pull_request.number }}
    repository: ${{ github.repository }}
    github-token: ${{ secrets.GITHUB_TOKEN }}
    environments: "develop,staging"
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

See the root [Configuration](../../README.md#configuration) and [Matrix Output](../../README.md#matrix-output) sections for the schema and matrix format.

## Deploy Labels

The system recognizes labels in the format `deploy:service`:

- `deploy:auth` - Deploy auth service
- `deploy:api` - Deploy api service
- `deploy:frontend` - Deploy frontend service
- `deploy:all` - Resolve targets for all existing services

## Environment Targeting

**Trunk-based Development**: The resolver uses explicit environment targeting rather than branch-based mapping:

- Environments are specified directly as parameters
- No dependency on branch names for environment determination
- Supports any deployment environment defined in configuration
- Supports targeting multiple environments in one invocation

## Target Resolution

Intersects the requested environments with each stack's configured environments and enumerates existing directories across all paths. Omitting the environment selection or providing only whitespace selects all configured environments. Targets shared across environments are generated once per directory.

`deploy:all` discovers all services from the configured paths. Targets matching exclusion conditions are omitted from the matrix. Missing paths produce a valid empty result; unknown environments, enumeration errors, and conflicting captured values cause failures.

## Error Handling

The resolver provides comprehensive error handling:

- **Invalid Environment**: Clear error when target environment doesn't exist
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

Test with real PR.

```bash
bundle exec ruby label-resolver/bin/resolver debug 123 develop
```
