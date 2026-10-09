# Deploy Actions

**English** | [🇯🇵 Japanese](README-ja.md)

A GitHub Actions toolkit that drives PR-label-based deployment orchestration for multi-service repositories.

## Overview

Deploy Actions converts file changes into deployment labels and converts those labels into structured deployment targets. The toolkit handles the change-detection and target-resolution layer; the actual `plan`/`apply` execution is delegated to whatever Composite Action the consumer wires in (Terragrunt, Helm, kustomize, etc.).

## Components

### 1. Config Manager (`action-scripts/config-manager/`)

Validates stack definitions in `workflow-config.yaml` and provides configuration display, environment listing, service diagnosis using existing directories, and template generation.

**Highlights:**

- Configuration validation with detailed error reports
- Environment listing and service diagnosis
- Stack path and exclusion validation
- Template generation

### 2. Label Dispatcher (`label-dispatcher/`)

Detects file changes from a PR and creates `deploy:<service>` labels for affected services.

**Highlights:**

- Change detection from `git diff`
- Service discovery from directory patterns
- Automatic label generation
- Exclusion handling

### 3. Label Resolver (`label-resolver/`)

Generates a matrix for downstream Actions from `deploy:<service>` labels and the selected environments.

**Highlights:**

- Label-to-target resolution
- Target selection from declared and discovered environments
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

`environments` is optional. Specify multiple environments as a comma-separated list; omit it to target all declared and discovered environments.

```yaml
- uses: panicboat/deploy-actions/label-resolver@v1
  with:
    pr-number: ${{ github.event.pull_request.number }}
    repository: ${{ github.repository }}
    github-token: ${{ secrets.GITHUB_TOKEN }}
    environments: develop
```

## Configuration

Define a nonempty `stacks` array at the top level of `workflow-config.yaml`. Each stack definition contains its paths, environment attributes, and exclusion conditions.

```yaml
stacks:
  - name: terragrunt
    id: aws
    paths:
      - "dystopia/{service}/aws/{environment}"
      - "system-components/{service}/infrastructure/aws/{environment}"
      - "teams/{team}/{service}/aws/{environment}"
    environments:
      develop:
        aws_region: ap-northeast-1
      production:
        aws_region: us-west-2
    exclude:
      - service: demo
        environment: production
      - team: sandbox
  - name: container
    paths:
      - "dystopia/{service}"
      - "system-components/{service}"
    attributes:
      repository: registry.example.com/{service}
  - name: kubernetes
    paths:
      - "dystopia/{service}/kubernetes/overlays/{environment}"
      - "system-components/{service}/kubernetes/overlays/{environment}"
```

### Stack Definitions

| Field | Requirement | Behavior |
|---|---|---|
| `name` | Required | Stack type; does not restrict attribute names or providers |
| `id` | Optional | Instance identifier; defaults to `name` and must be unique across the configuration |
| `paths` | Required | Nonempty array of relative paths; every path must contain `{service}` |
| `environments` | Optional | Nonempty map from environment names to environment attributes |
| `attributes` | Optional | Explicitly selects a target shared across environments, including `attributes: {}`; cannot be combined with `environments` |
| `exclude` | Optional | Array of exclusion conditions; defaults to an empty array |

Products that share a stack use multiple entries in one definition's `paths`. For independent stacks, use separate definitions with the same `name` and different `id` values, each with its own paths and attributes.

The keys in `environments` define the stack's environment names. A stack with neither `environments` nor `attributes` discovers environment names from the `{environment}` position in existing directories matching its paths. Every path in that stack must contain `{environment}`; otherwise the configuration is invalid. Discovered targets have no additional attributes and do not inherit another stack's environments, attributes, or exclusions.

The selectable environment list is the union of all declared names and names discovered at execution time. Excluded environments remain selectable. Omitting the environment selection targets this union. Each stack generates targets only for its own declared or discovered environments. Selecting a name absent from the union is an error.

A stack with `environments` generates targets for each environment even when its paths do not contain `{environment}`. The same directory can use different environment attributes. A stack with `attributes` generates one target with `environment: null` per directory, regardless of environment selection. Its paths cannot contain `{environment}`. Use `attributes: {}` when a shared target needs no attributes.

### Attribute Values

String values in `attributes` and environment attribute maps support `{service}` and arbitrary placeholders captured from the path, such as `{team}`. Environment attributes also support `{environment}`, even if the path does not contain it. The same rules apply to strings nested in maps or arrays. Map keys remain literal, and non-string values retain their types. Environments do not need identical attribute keys.

Every placeholder referenced by an attribute must be available for every path in that stack; unresolved references are configuration errors. Shared attributes cannot reference `{environment}`. For example, `paths: ["teams/{team}/{service}"]` with `attributes: {repository: "ghcr.io/{team}/{service}"}` produces `ghcr.io/payments/api` for `teams/payments/api`.

### Path Matching

Paths are complete relative patterns from the repository root. Absolute paths and `..` segments are rejected. Leading `./`, extra `/` separators, and `.` segments are normalized. All existing directories matching any pattern are enumerated; missing paths generate no targets. Services do not require registration. Service names starting with a dot are excluded.

Arbitrary placeholders such as `{team}` are supported. Names must match `[a-z_][a-z0-9_]*`, and each value occupies one path segment. Repeated occurrences of a placeholder must match the same value. Glob characters are treated literally. Definitions are rejected if an arbitrary placeholder conflicts with a fixed matrix key or with any environment or shared attribute key in the same stack.

### Exclusion Conditions

Each entry in `exclude` is a nonempty condition map. Conditions can use `service`, `environment`, or any arbitrary placeholder found in the stack's paths. Attribute names cannot be used as condition keys.

Conditions use exact matching: keys within a map are combined with AND, and entries in the array are combined with OR. Omitted keys impose no restriction. A condition can specify only a service, only an environment, or only an arbitrary placeholder. A condition requiring a captured value absent from the matched path does not match.

Condition values must be nonempty strings representing one path segment; `/`, `.`, and `..` are not allowed. Service names cannot start with a dot. When `environments` is specified, environment conditions can name only the stack's declared environments. For stacks that discover environments, an environment condition may name a directory value that does not yet exist. For stacks shared across environments, `environment` can be omitted or set to `null`; other condition values cannot be `null`. Condition values are literal and do not expand placeholders.

See [workflow-config.yaml](action-scripts/workflow-config.yaml) for a working configuration example.

## Workflow Integration

### 1. Change Detection

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

### 2. Target Resolution

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
          pr-number: ${{ github.event.pull_request.number }}
          repository: ${{ github.repository }}
          github-token: ${{ secrets.GITHUB_TOKEN }}
```

Pass `${{ steps.resolve.outputs.targets }}` to your deployment step.

The execution layer (`aws`, `kubernetes`, etc.) is intentionally not part of this repository — the maintainer's personal wrappers live at [`panicboat/panicboat-actions`](https://github.com/panicboat/panicboat-actions).

## Matrix Output

`label-resolver` writes a JSON array to `outputs.targets` and the `DEPLOYMENT_TARGETS` environment variable. Each target has the following five fixed keys, with attributes and captured arbitrary placeholders flattened into the same object.

| Key | Source |
|---|---|
| `service` | Service name from a label or discovered through `deploy:all` |
| `environment` | Declared or discovered environment name, or `null` for a target shared across environments |
| `stack` | Stack `name` |
| `stack_id` | Resolved `id` |
| `working_directory` | Relative path of the existing target directory |
| Attribute keys | Selected environment attributes or shared `attributes` |
| Arbitrary placeholder keys | Values captured from the matched path |

With the configuration above, an existing `teams/payments/api/aws/develop` directory generates the following row.

```json
{
  "service": "api",
  "environment": "develop",
  "stack": "terragrunt",
  "stack_id": "aws",
  "working_directory": "teams/payments/api/aws/develop",
  "aws_region": "ap-northeast-1",
  "team": "payments"
}
```

Target identity consists of `service`, `stack_id`, `environment`, and `working_directory`. Duplicate targets are merged into one row. Paths that interpret the same target with different captured value maps cause an error, regardless of exclusions or definition order. Downstream steps can reference arbitrary keys such as `${{ matrix.team }}`.

## Development

### Prerequisites

- Ruby ([.ruby-version](action-scripts/.ruby-version))
- Bundler
- Git

### Setup

```bash
git clone https://github.com/panicboat/deploy-actions.git
cd deploy-actions/action-scripts
bundle install
bundle exec rspec
```

### Component Testing

```bash
bundle exec ruby config-manager/bin/config-manager validate
bundle exec ruby label-dispatcher/bin/dispatcher test
bundle exec ruby label-resolver/bin/resolver resolve PR_NUMBER
```

## License

MIT — see `LICENSE`.
