# Config Manager

**English** | [🇯🇵 日本語](README-ja.md)

Config Manager checks `workflow-config.yaml` and shows which targets a service produces. Both composite actions run its `validate` command first, so an invalid configuration fails the step before any label changes or target resolution. The configuration format is documented [on this page](#configuration-format).

## Commands

Run these from the `action-scripts` directory. Neither command contacts GitHub.

| Command | Result |
|---|---|
| `bundle exec ruby config-manager/bin/config-manager validate` | Prints whether the configuration is valid, with the number of services, stacks, and declared environments |
| `bundle exec ruby config-manager/bin/config-manager test SERVICE [ENVIRONMENT]` | Prints every target of the service and whether it is excluded |

`validate` exits with status 1 on an invalid configuration. It reads only the file and does not list directories, so it also runs outside a git checkout, and environments discovered from directories do not appear in its counts. Each error names the position of the problem, such as `services[0].stacks[1].environments.develop.use[0]: profile 'aws' is not defined`.

`test` shows what a service deploys given the directories that exist:

```bash
bundle exec ruby config-manager/bin/config-manager test demo
bundle exec ruby config-manager/bin/config-manager test demo production
```

Without an environment it covers all declared and discovered environments plus the targets shared across environments. With an environment it covers that environment plus the shared targets. Services do not need registering, and a valid name that matches no directory prints an empty result. Each target is printed with its stack `id`, expanded attribute values, and captured placeholders. Excluded targets are printed too, with `excluded: true`, so you can see what is left out of deployment. A name that is not a [valid service name](#service-names), an unknown environment, an invalid configuration, a directory that cannot be listed, and conflicting captured values for the same target are errors and exit with status 1.

To try a configuration change without editing the original, point `WORKFLOW_CONFIG_PATH` at a copy:

```bash
cp workflow-config.yaml test-config.yaml
WORKFLOW_CONFIG_PATH=test-config.yaml bundle exec ruby config-manager/bin/config-manager validate
WORKFLOW_CONFIG_PATH=test-config.yaml bundle exec ruby config-manager/bin/config-manager test myservice develop
```

### Environment Variables

All three tools read these variables.

| Variable | Value |
|---|---|
| `WORKFLOW_CONFIG_PATH` | Configuration file, relative to the current directory; defaults to `workflow-config.yaml` |
| `SOURCE_REPO_PATH` | Repository root, used when it holds `.git`; otherwise the search starts at the current directory itself and returns the nearest directory that holds `.git` |
| `GITHUB_TOKEN` | GitHub API token; required by `dispatcher dispatch` and `resolver resolve` |
| `GITHUB_REPOSITORY` | Repository in `owner/repo` format; required by `dispatcher dispatch` and `resolver resolve` |
| `GITHUB_ACTIONS` | When set, the tools write step outputs and report errors as `::error::` annotations |
| `GITHUB_OUTPUT` | Step output file; required when `GITHUB_ACTIONS` is set |

## Configuration Format

`workflow-config.yaml` has a required `services` array, which must not be empty, and two optional keys: `profiles` defines named attribute sets, and `labels` sets the label prefixes (see [Labels](../label-dispatcher/README.md#labels)). Any other top-level key is a configuration error.

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

A service owns the files under its `roots` and contains the `stacks` that run inside it.

| Field | Requirement | Behavior |
|---|---|---|
| `id` | Required | Identifier unique across the configuration |
| `roots` | Required | Nonempty array of relative patterns from the repository root; every root must contain `{service}` |
| `attributes` | Optional | Attributes attached to every target of every stack in the service |
| `ignore` | Optional | Array of globs relative to the root; affects change detection only (see [Ignoring Files](../label-dispatcher/README.md#ignoring-files)) |
| `stacks` | Required | Nonempty array of stacks |

The value captured by `{service}` is the service name in labels and the matrix. The service `id` appears in neither.

Roots can contain arbitrary placeholders such as `{project}`. `{environment}` is rejected in roots, as in `envs/{environment}/{service}`, because the environment belongs to a stack's `path`. When environment directories sit below the service, put `{environment}` in `path` and keep the root at the service directory, so that shared directories next to the environments stay under the root.

### Service Names

A service name matches `[a-zA-Z0-9_-]+`: ASCII letters, digits, `_`, and `-`. `all` is a name like any other.

A directory at the `{service}` position with any other name, such as `a.b` or `.github`, is not a service. A change below it labels nothing, it produces no targets, and environments below it are not discovered. The tools do not look inside it, so it may be unreadable. Other placeholders, such as `{team}`, have no such rule.

### Stacks

A stack runs in each root followed by its `path`: root `aws/{service}` with path `{environment}` is the directory pattern `aws/{service}/{environment}`. Different stacks can point at the same directory.

| Field | Requirement | Behavior |
|---|---|---|
| `id` | Required | Identifier unique across all services; becomes the matrix `stack` |
| `path` | Required | Path relative to each root; `.` is the root itself |
| `attributes` | Optional | Attributes attached to every target of the stack |
| `environments` | Optional | Nonempty map from environment names to environment entries |
| `exclude` | Optional | Array of exclusion conditions; defaults to an empty array |

`path` can contain `{environment}` and arbitrary placeholders. It cannot contain `{service}`, because the root determines the service.

A stack has no built-in type. Describe the kind of tool with an attribute such as `type`, and branch on it downstream (see [Matrix Output](../label-resolver/README.md#matrix-output)). [How Targets Are Built](../label-resolver/README.md#how-targets-are-built) explains how `environments` and `{environment}` decide the targets of a stack.

### Profiles

A profile is a named attribute map under the top-level `profiles`. A stack references profiles with `use` inside `environments.<name>`.

An entry in `environments` is a map of attributes with one reserved key, `use`, which is an optional nonempty array of profile names. The attributes of a target are the service's `attributes`, the stack's `attributes`, the attributes of each profile listed in `use`, and the other keys of the entry (inline attributes). In the example above, the `gcp` stack runs with the AWS role of `aws-develop`, and `gcp_project` adds the project it creates resources in.

The same attribute name in two or more of those places is a configuration error that names the stack, the environment, and the sources. A `use` naming an undefined profile is a configuration error that points at `services[i].stacks[j].environments.<name>.use[k]`, while unused profiles are allowed. `use` is valid only inside `environments.<name>`, and it is rejected in a service's or stack's `attributes` and in profiles.

Profile attributes follow the rules for environment attributes: keys cannot be fixed matrix keys, and placeholders must resolve for every stack that uses the profile.

### Attribute Values

String values in service and stack `attributes`, profiles, and environment entries support `{service}` and arbitrary placeholders captured from the root or `path`, such as `{project}`. Targets with an environment, declared or discovered, also support `{environment}`, even if `path` does not contain it. A stack with neither `environments` nor `{environment}` in `path` produces targets without an environment, so its attributes cannot reference `{environment}`.

The same rules apply to strings nested in maps or arrays. Map keys remain literal, and non-string values retain their types. Environments do not need identical attribute keys.

Every placeholder referenced by an attribute must be available for every root of the service combined with the stack's `path`, and for every stack of the service when the attribute is a service attribute. Unresolved references are configuration errors. For example, `roots: ["teams/{team}/{service}"]` with `attributes: {repository: "ghcr.io/{team}/{service}"}` produces `ghcr.io/payments/api` for `teams/payments/api`. If the service had another root without `{team}`, the reference would be rejected, so put roots that capture different placeholders in separate services.

### Path Patterns

Roots and paths are relative patterns. Absolute paths and `..` segments are rejected. A leading `./`, extra `/` separators, and `.` segments are normalized.

Names of arbitrary placeholders must match `[a-z_][a-z0-9_]*`, and each value occupies one path segment. Repeated occurrences of a placeholder must match the same value. Glob characters are treated literally.

A definition is rejected if a placeholder conflicts with a fixed matrix key (`stack`, `working_directory`) or with any attribute key of the stack, whether it comes from the service's or stack's `attributes`, a profile, or an environment entry. Attribute keys cannot be fixed matrix keys (`service`, `environment`, `stack`, `working_directory`).

### Exclusion Conditions

Each entry in `exclude` is a nonempty condition map. Conditions can use `service`, `environment`, or any arbitrary placeholder found in any root of the service or in the stack's `path`. Attribute names cannot be used as condition keys.

Conditions use exact matching: keys within a map are combined with AND, and entries in the array are combined with OR. Omitted keys impose no restriction. A condition requiring a captured value that the matched root does not capture does not match there. For example, `project: sandbox` excludes only the targets under a root such as `gcp/{project}/{service}`.

Condition values must be nonempty strings representing one path segment, so `/`, `.`, and `..` are not allowed. A `service` condition must be a [valid service name](#service-names), so `service: a.b` is a configuration error. Values are literal and do not expand placeholders.

The `environment` condition depends on how the stack gets its environments. With `environments`, it can name only the stack's declared environments. A stack that discovers environments can name a directory value that does not exist yet. A stack with neither `environments` nor `{environment}` in `path` can omit `environment` or set it to `null`. Other condition values cannot be `null`.

### YAML Anchors

Anchors, aliases, and merge keys (`<<`) are accepted and resolved before validation. Define an anchor inside `profiles` or any stack, because a separate top-level key for anchors would be rejected as unknown.

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

The validator sees only the parsed hash, so a key written next to `<<:` silently overrides the merged value, as `iam_role_plan` does above. A stack's `attributes`, a profile in `use`, and inline attributes that define the same key raise a configuration error instead.

## Code Layout

`ConfigManagerController` backs the two commands. `ValidateConfig` loads the file through `ConfigClient`, which parses the YAML and checks it with `WorkflowConfigParser`. `TestService` lists targets with the shared `ListCandidates` use case. `ConsolePresenter` formats the output for a terminal, and `GitHubActionsPresenter` formats it inside a workflow.

## Testing

```bash
cd action-scripts
bundle exec rspec spec/config-manager/
```
