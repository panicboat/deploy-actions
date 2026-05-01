# Deploy Actions

**English** | [🇯🇵 日本語](README-ja.md)

A GitHub Actions toolkit that drives PR-label-based deployment orchestration for multi-service repositories.

## Overview

Deploy Actions converts file changes into deployment labels and converts those labels into structured deployment targets. The toolkit handles the change-detection and target-resolution layer; the actual `plan`/`apply` execution is delegated to whatever Composite Action the consumer wires in (Terragrunt, Helm, kustomize, etc.).

## Components

### 1. Config Manager (`action-scripts/config-manager/`)

Validates and manages the `workflow-config.yaml` that defines environments, services, and directory conventions.

**Highlights:**

- Configuration validation with detailed error reporting
- Environment and service management
- Directory-convention validation
- Template generation

### 2. Label Dispatcher (`label-dispatcher/`)

Detects file changes from a PR and creates `deploy:<service>` labels for affected services.

**Highlights:**

- Change detection from `git diff`
- Service discovery from directory patterns
- Automatic label generation
- Exclusion handling

### 3. Label Resolver (`label-resolver/`)

Translates `deploy:<service>` labels and branch context into a deployment-target matrix that downstream actions consume.

**Highlights:**

- Label-to-target resolution
- Environment detection from branch
- Deployment-matrix generation
- Safety validation

## Composite Actions

### Label Dispatcher

```yaml
- uses: panicboat/deploy-actions/label-dispatcher@v1
  with:
    pr-number: ${{ github.event.pull_request.number }}
    repository: ${{ github.repository }}
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

### Label Resolver

```yaml
- uses: panicboat/deploy-actions/label-resolver@v1
  with:
    action-type: plan  # or apply
    pr-number: ${{ github.event.pull_request.number }}
    repository: ${{ github.repository }}
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

## Configuration

The toolkit reads `workflow-config.yaml`:

```yaml
environments:
  - environment: develop
    stacks:
      terragrunt:
        aws_region: ap-northeast-1
        iam_role_plan: arn:aws:iam::ACCOUNT:role/plan-role
        iam_role_apply: arn:aws:iam::ACCOUNT:role/apply-role
      kubernetes: {}

stack_conventions:
  - root: "{service}"
    stacks:
      - name: terragrunt
        directory: "terragrunt/{environment}"
        required_attributes: [aws_region, iam_role_plan, iam_role_apply]
      - name: kubernetes
        directory: "kubernetes/overlays/{environment}"

services:
  - name: excluded-service
    exclude_from_automation: true
    exclusion_config:
      reason: "Manual deployment required"
      type: "permanent"
```

See `action-scripts/workflow-config.yaml` for a runnable sample.

## Workflow integration

### 1. Change-detection workflow

```yaml
name: Detect Changes and Create Labels
on:
  pull_request:
    types: [opened, synchronize, reopened]

jobs:
  detect-changes:
    runs-on: ubuntu-latest
    steps:
      - uses: panicboat/deploy-actions/label-dispatcher@v1
        with:
          pr-number: ${{ github.event.pull_request.number }}
          repository: ${{ github.repository }}
          github-token: ${{ secrets.GITHUB_TOKEN }}
```

### 2. Deployment-target resolution

```yaml
name: Deploy
on:
  pull_request:
    types: [labeled]

jobs:
  plan:
    runs-on: ubuntu-latest
    if: contains(github.event.label.name, 'deploy:')
    steps:
      - id: resolve
        uses: panicboat/deploy-actions/label-resolver@v1
        with:
          action-type: plan
          pr-number: ${{ github.event.pull_request.number }}
          repository: ${{ github.repository }}
          github-token: ${{ secrets.GITHUB_TOKEN }}

      # Then run your own deploy step using ${{ steps.resolve.outputs.deployment-targets }}
```

The execution layer (`terragrunt`, `kubernetes`, etc.) is intentionally not part of this repository — the maintainer's personal wrappers live at [`panicboat/panicboat-actions`](https://github.com/panicboat/panicboat-actions).

## Development

### Prerequisites

- Ruby 3.4+
- Bundler
- Git

### Setup

```bash
git clone https://github.com/panicboat/deploy-actions.git
cd deploy-actions/action-scripts
bundle install
bundle exec rspec
```

### Testing individual components

```bash
bundle exec ruby config-manager/bin/config-manager validate
bundle exec ruby label-dispatcher/bin/dispatcher detect
bundle exec ruby label-resolver/bin/resolver resolve PR_NUMBER
```

## License

MIT — see `LICENSE`.
