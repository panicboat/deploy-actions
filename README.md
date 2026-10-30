# Deploy Actions

**English** | [🇯🇵 日本語](README-ja.md)

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

Detects file changes from a PR and creates `<prefix><service>` labels (`deploy:<service>` by default) for affected services.

**Highlights:**

- Change detection from `git diff`
- Service discovery from directory patterns
- Automatic label generation
- Exclusion handling

### 3. Label Resolver (`label-resolver/`)

Generates a matrix for downstream Actions from `<prefix><service>` labels and the selected environments.

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

Define a nonempty `services` array at the top level of `workflow-config.yaml`. A service owns the files under its `roots` and contains the `stacks` that run inside it. The optional top-level `profiles` map defines named attribute sets, and the optional `labels` map sets the label prefixes. Any other top-level key is a configuration error.

```yaml
labels:
  prefix: "deploy:"

profiles:
  aws-develop:
    aws_region: ap-northeast-1
    iam_role_plan: arn:aws:iam::123456789012:role/aws-plan-develop-role
    iam_role_apply: arn:aws:iam::123456789012:role/aws-apply-develop-role
  aws-production:
    aws_region: ap-northeast-1
    iam_role_plan: arn:aws:iam::210987654321:role/aws-plan-production-role
    iam_role_apply: arn:aws:iam::210987654321:role/aws-apply-production-role

services:
  - id: app
    roots:
      - "dystopia/{service}"
      - "system-components/{service}"
    ignore:
      - "**/README.md"
    stacks:
      - id: dockerfile
        path: "."
        attributes:
          type: container
          repository: registry.example.com/{service}
      - id: kustomize
        path: "kubernetes/overlays/{environment}"
        attributes:
          type: kustomize
      - id: aws
        path: "infrastructure/aws/{environment}"
        attributes:
          type: terragrunt
        environments:
          develop:
            use: [aws-develop]
          production:
            use: [aws-production]
        exclude:
          - service: demo
            environment: production
      - id: gcp
        path: "infrastructure/gcp/{environment}"
        attributes:
          type: terragrunt
        environments:
          develop:
            use: [aws-develop]
            gcp_project: foo-develop
```

### Services

| Field | Requirement | Behavior |
|---|---|---|
| `id` | Required | Identifier unique across the configuration; used in error messages and displays |
| `roots` | Required | Nonempty array of relative patterns from the repository root; every root must contain `{service}` |
| `attributes` | Optional | Attributes attached to every target of every stack in the service |
| `ignore` | Optional | Array of globs relative to the root; affects change detection only |
| `stacks` | Required | Nonempty array of stacks |

A root defines which files belong to a service. The value captured by `{service}` is the service name in labels and the matrix; the service `id` is not used for either.

Roots can contain arbitrary placeholders such as `{project}`. `{environment}` is rejected in roots because the environment belongs to a stack `path`. When environment directories sit below the service, put `{environment}` in `path` and keep the root at the service directory, so that shared directories next to the environments stay under the root.

Not supported: `{environment}` in roots, as in `envs/{environment}/{service}`, and roots without `{service}`.

### Stacks

| Field | Requirement | Behavior |
|---|---|---|
| `id` | Required | Identifier unique across all services; becomes the matrix `stack` |
| `path` | Required | Path relative to each root; `.` is the root itself |
| `attributes` | Optional | Attributes attached to every target of the stack |
| `environments` | Optional | Nonempty map from environment names to environment entries |
| `exclude` | Optional | Array of exclusion conditions; defaults to an empty array |

A stack has no built-in type. Describe the kind of tool with an attribute such as `type`, and branch on it downstream (see [Matrix Output](#matrix-output)).

A stack runs in each root followed by `path`: root `aws/{service}` with path `{environment}` is the directory pattern `aws/{service}/{environment}`. `path` can contain `{environment}` and arbitrary placeholders, but not `{service}`, because the root determines the service. Different stacks can point at the same directory.

Targets are built in this order:

1. With `environments`, one target is built for each declared environment, even when `path` does not contain `{environment}`. When it does, only the declared names match, so a directory such as `modules/` never becomes a target.
2. Without `environments`, when `path` contains `{environment}`, environment names are discovered from existing directories at that position. Directories at that position that are not environments, such as `modules/`, are also discovered as environments, so declare `environments` when such directories sit beside the environment directories.
3. With neither, one target with `environment: null` is built per directory, regardless of environment selection.

`attributes` attach to every target of the stack, however it was built. In case 3 they cannot reference `{environment}`. The service's `attributes` attach to the targets of every stack in the same way.

The selectable environment list is the union of all declared names and names discovered at execution time. Excluded environments remain selectable. Omitting the environment selection targets this union. Each stack generates targets only for its own declared or discovered environments. Selecting a name absent from the union is an error.

### Profiles

A profile is a named attribute map under the top-level `profiles`. A stack references profiles with `use` inside `environments.<name>`.

An entry in `environments` is a map of attributes with one reserved key, `use`, which is an optional nonempty array of profile names. The attributes of a target are the service's `attributes`, the stack's `attributes`, the attributes of each profile listed in `use`, and the other keys of the entry (inline attributes). In the example above, the `gcp` stack runs with the AWS role of `aws-develop`, and `gcp_project` adds the project it creates resources in.

- The same attribute name in two or more of those places is a configuration error that names the stack, the environment, and the sources.
- A `use` naming an undefined profile is a configuration error that points at `services[i].stacks[j].environments.<name>.use[k]`. Unused profiles are allowed.
- `use` is valid only inside `environments.<name>`. It is rejected in a service's or stack's `attributes` and in profiles.
- Profile attributes follow the rules for environment attributes: keys cannot be fixed matrix keys, and placeholders must resolve for every stack that uses the profile.

### Attribute Values

String values in service and stack `attributes`, profiles, and environment entries support `{service}` and arbitrary placeholders captured from the root or `path`, such as `{project}`. Targets with an environment, declared or discovered, also support `{environment}`, even if `path` does not contain it. The same rules apply to strings nested in maps or arrays. Map keys remain literal, and non-string values retain their types. Environments do not need identical attribute keys.

Every placeholder referenced by an attribute must be available for every root of the service combined with the stack's `path`, and for every stack of the service when the attribute is a service attribute; unresolved references are configuration errors. For example, `roots: ["teams/{team}/{service}"]` with `attributes: {repository: "ghcr.io/{team}/{service}"}` produces `ghcr.io/payments/api` for `teams/payments/api`. If the service had another root without `{team}`, the reference would be rejected, so put roots that capture different placeholders in separate services.

### Path Matching

Roots and paths are relative patterns. Absolute paths and `..` segments are rejected. Leading `./`, extra `/` separators, and `.` segments are normalized. All existing directories matching any root followed by `path` are enumerated; missing paths generate no targets. Services do not require registration. Service names starting with a dot are excluded.

Names of arbitrary placeholders must match `[a-z_][a-z0-9_]*`, and each value occupies one path segment. Repeated occurrences of a placeholder must match the same value. Glob characters are treated literally. Definitions are rejected if a placeholder conflicts with a fixed matrix key (`stack`, `working_directory`) or with any attribute key of the stack, whether it comes from the service's or stack's `attributes`, a profile, or an environment entry. Attribute keys cannot be fixed matrix keys (`service`, `environment`, `stack`, `working_directory`).

### Exclusion Conditions

Each entry in `exclude` is a nonempty condition map. Conditions can use `service`, `environment`, or any arbitrary placeholder found in any root of the service or in the stack's `path`. Attribute names cannot be used as condition keys.

Conditions use exact matching: keys within a map are combined with AND, and entries in the array are combined with OR. Omitted keys impose no restriction. A condition requiring a captured value that the matched root does not capture does not match there. For example, `project: sandbox` excludes only the targets under a root such as `gcp/{project}/{service}`.

Condition values must be nonempty strings representing one path segment; `/`, `.`, and `..` are not allowed. Service names cannot start with a dot. When `environments` is specified, environment conditions can name only the stack's declared environments. For stacks that discover environments, an environment condition may name a directory value that does not yet exist. For stacks with neither `environments` nor `{environment}` in `path`, `environment` can be omitted or set to `null`; other condition values cannot be `null`. Condition values are literal and do not expand placeholders.

### Detection

Label Dispatcher labels a service when a changed file is below one of its roots, except in the cases below. It evaluates every changed file against every root in this order:

1. The file is skipped when it is not below the root, or when the `{service}` capture starts with a dot.
2. The file is skipped when its path relative to the root matches an `ignore` pattern.
3. When the file is below a stack's directory (root followed by `path`), candidate targets are built as Label Resolver builds them. The service is labeled unless `exclude` removes every candidate.
4. When the file is below no stack's directory, such as `modules/` or `Makefile`, the service is labeled. `exclude` does not apply to these shared files; use `ignore` to skip them.

A stack with `path: "."` has the root itself as its directory, but it does not count as a stack's directory for rule 4. Its candidates label the service as in rule 3; when `exclude` removes all of them, rule 4 still applies unless the file is below another stack's directory. A file below another stack's directory whose candidates are all excluded is still not labeled. For a stack with `environments`, a directory at the `{environment}` position that is not a declared environment is outside the stack's directory.

Choose roots narrow enough that unrelated top-level directories are not taken as services; for example, avoid a bare `{service}` root, which makes every top-level directory a service.

`ignore` patterns are globs relative to the root: for root `dystopia/{service}`, the file `dystopia/api/docs/guide.md` is matched as `docs/guide.md`. `*` does not cross `/`, and `**/` matches zero or more directories. A trailing `/**` matches every file below that directory. Files starting with a dot match, and `?`, `[...]`, and `{a,b}` work as in shell globs. `ignore` affects change detection only; Label Resolver still generates targets under ignored paths.

A shared file can label a service that has no target to resolve, for example when its only environment is excluded. The label is added and Label Resolver returns no targets.

The following configuration puts the environment directories next to a shared `modules/` directory:

```yaml
profiles:
  aws-develop:
    aws_region: ap-northeast-1
    iam_role_plan: arn:aws:iam::123456789012:role/aws-plan-develop-role
    iam_role_apply: arn:aws:iam::123456789012:role/aws-apply-develop-role
  aws-production:
    aws_region: ap-northeast-1
    iam_role_plan: arn:aws:iam::210987654321:role/aws-plan-production-role
    iam_role_apply: arn:aws:iam::210987654321:role/aws-apply-production-role

services:
  - id: infrastructure
    roots:
      - "aws/{service}"
      - "gcp/{project}/{service}"
    ignore:
      - "**/*.md"
    stacks:
      - id: terragrunt
        path: "{environment}"
        attributes:
          type: terragrunt
        environments:
          develop:
            use: [aws-develop]
          production:
            use: [aws-production]
        exclude:
          - environment: production
          - project: sandbox
```

| Changed file | Result |
|---|---|
| `aws/api/modules/main.tf` | Labels `api`: shared file |
| `gcp/sandbox/api/modules/main.tf` | Labels `api`: shared file; `exclude` does not apply |
| `aws/api/develop/main.tf` | Labels `api` |
| `aws/api/production/main.tf` | No label: the only candidate is excluded |
| `gcp/sandbox/api/develop/main.tf` | No label: the only candidate is excluded |
| `aws/api/docs/guide.md` | No label: ignored |

### YAML Anchors

Anchors, aliases, and merge keys (`<<`) are accepted and resolved before validation. Define an anchor inside `profiles` or any stack.

```yaml
profiles:
  aws-develop: &aws-develop
    aws_region: ap-northeast-1
    iam_role_plan: arn:aws:iam::123456789012:role/aws-plan-develop-role
    iam_role_apply: arn:aws:iam::123456789012:role/aws-apply-develop-role
  aws-production:
    <<: *aws-develop
    iam_role_plan: arn:aws:iam::210987654321:role/aws-plan-production-role
    iam_role_apply: arn:aws:iam::210987654321:role/aws-apply-production-role

services:
  - id: app
    roots:
      - "apps/{service}"
    stacks:
      - id: aws
        path: "aws/{environment}"
        environments: &environments
          develop:
            use: [aws-develop]
          production:
            use: [aws-production]
      - id: aws-audit
        path: "audit/{environment}"
        environments: *environments
```

The validator sees only the parsed hash. A key written next to `<<:` silently overrides the merged value, as `iam_role_plan` does above. This differs from the configuration error raised when a stack's `attributes`, a profile in `use`, and the inline attributes define the same key.

### Labels

Each prefix is used as-is, including its separator.

```yaml
labels:
  prefix: "deploy:"
  extra_prefixes: ["manual/"]
```

| Field | Requirement | Behavior |
|---|---|---|
| `prefix` | Optional | Prefix of the labels managed by Label Dispatcher; defaults to `deploy:` |
| `extra_prefixes` | Optional | Array of additional prefixes read by Label Resolver; defaults to an empty array |

Label Dispatcher adds `<prefix><service>` labels and removes labels starting with `prefix` that no longer match the changes. It never touches labels starting with an `extra_prefixes` entry, so labels added by hand with those prefixes survive later pushes. Label Resolver reads labels starting with any configured prefix and treats the rest of the label as the service name. The same service labeled with different prefixes yields one service, and `all` with any prefix targets all services. Labels whose remaining text is not a valid service name (`[a-zA-Z0-9_-]+`) are ignored.

Prefixes must be nonempty strings. No prefix may start with another prefix, because Label Dispatcher would remove the labels of the overlapping prefix. Quote prefixes ending with `:` in YAML.

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

When you change `prefix` or add `extra_prefixes`, update the `if` condition to match every configured prefix, for example `startsWith(github.event.label.name, 'deploy:') || startsWith(github.event.label.name, 'manual/')`.

The execution layer (`aws`, `kubernetes`, etc.) is intentionally not part of this repository.

## Matrix Output

`label-resolver` writes a JSON array to `outputs.targets` and the `DEPLOYMENT_TARGETS` environment variable. Each target has the following four fixed keys, with attributes and captured arbitrary placeholders flattened into the same object.

| Key | Source |
|---|---|
| `service` | Service name from a label or discovered through `<prefix>all`; the value captured by `{service}` |
| `environment` | Declared or discovered environment name, or `null` for a target shared across environments |
| `stack` | Stack `id` |
| `working_directory` | Relative path of the existing target directory |
| Attribute keys | Stack `attributes`, plus the attributes of the profiles in `use` and the inline attributes of the selected environment |
| Arbitrary placeholder keys | Values captured from the matched path |

With the first configuration above, an existing `dystopia/api/infrastructure/aws/develop` directory generates the following row.

```json
{
  "service": "api",
  "environment": "develop",
  "stack": "aws",
  "working_directory": "dystopia/api/infrastructure/aws/develop",
  "type": "terragrunt",
  "aws_region": "ap-northeast-1",
  "iam_role_plan": "arn:aws:iam::123456789012:role/aws-plan-develop-role",
  "iam_role_apply": "arn:aws:iam::123456789012:role/aws-apply-develop-role"
}
```

Target identity consists of `service`, `stack`, `environment`, and `working_directory`. Duplicate targets are merged into one row. Paths that interpret the same target with different captured value maps cause an error, regardless of exclusions or definition order.

Because the stack kind is an attribute you define, downstream steps branch on it with `matrix.target.type`. In a job named `resolve`, expose `steps.resolve.outputs.targets` as the job output `targets`, then use it in a later job:

```yaml
deploy:
  needs: resolve
  strategy:
    matrix:
      target: ${{ fromJSON(needs.resolve.outputs.targets) }}
  steps:
    - if: matrix.target.type == 'terragrunt'
      uses: ./.github/actions/terragrunt-plan
      with:
        working-directory: ${{ matrix.target.working_directory }}
        role-to-assume: ${{ matrix.target.iam_role_plan }}
    - if: matrix.target.type == 'kustomize'
      uses: ./.github/actions/kustomize-build
      with:
        working-directory: ${{ matrix.target.working_directory }}
```

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
