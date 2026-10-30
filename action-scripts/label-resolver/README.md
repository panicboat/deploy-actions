# Label Resolver

**English** | [🇯🇵 日本語](README-ja.md)

Label Resolver turns `deploy:<service>` labels, or a service name you pass directly, into a JSON array of deployment targets for a job matrix. Environments come from its input and never from branch names, so one run can target any mix of environments.

## Action

The usual call resolves the labels of a pull request. `environments` is optional: give one name or a comma-separated list, or omit it to target all declared and discovered environments.

```yaml
- uses: panicboat/deploy-actions/label-resolver@v0.1.0
  with:
    pr-number: ${{ github.event.pull_request.number }}
    repository: ${{ github.repository }}
    environments: "develop,staging"
```

Set `service` to resolve a service without a pull request. This suits release or manual workflows. `pr-number` is then ignored, and `ref` selects the ref of the source repository to check out.

```yaml
- uses: panicboat/deploy-actions/label-resolver@v0.1.0
  with:
    repository: ${{ github.repository }}
    service: api
    environments: production
    ref: ${{ github.event.release.tag_name }}
```

The action checks out the repository itself, so the job needs no checkout step. It validates the configuration with [Config Manager](../config-manager/README.md) first, and it fails when neither `service` nor `pr-number` is set.

Inputs:

| Input | Required | Value |
|---|---|---|
| `repository` | Yes | Source repository (`owner/repo`) |
| `pr-number` | Unless `service` is set | Pull request whose labels are resolved; ignored when `service` is set |
| `service` | No | [Service name](../config-manager/README.md#service-names); resolves its targets without a pull request |
| `environments` | No | Comma-separated environments; empty means all declared and discovered environments |
| `ref` | No | Ref of the source repository to check out; defaults to the event's ref for the triggering repository and to the default branch for another repository |
| `github-token` | No | Token for checking out the repository and reading the PR; defaults to `${{ github.token }}` |
| `config-path` | No | Path to the configuration file; defaults to `workflow-config.yaml` |

Outputs:

| Output | Value |
|---|---|
| `targets` | JSON array of deployment targets (see [Matrix Output](#matrix-output)) |
| `has-targets` | `true` or `false` |

## From Labels to Targets

The resolver reads the pull request's labels that start with any [configured prefix](../label-dispatcher/README.md#labels), `deploy:` by default, and treats the rest of the label as the service name. The same service labeled with different prefixes yields one service. Labels whose remaining text is not a [valid service name](../config-manager/README.md#service-names) are ignored. `all` is an ordinary name, so `deploy:all` targets only a directory named `all`.

A pull request without deploy labels gives empty `targets` and `has-targets: false`.

A workflow triggered by `labeled` must filter on the prefixes it uses. When you change `prefix` or add `extra_prefixes`, update the `if` condition to match every configured prefix, for example `startsWith(github.event.label.name, 'deploy:') || startsWith(github.event.label.name, 'manual/')`.

## How Targets Are Built

The resolver lists all existing directories matching any root followed by `path`. Missing paths generate no targets and are a valid empty result. Services do not require registration, and a directory at `{service}` whose name is not a [valid service name](../config-manager/README.md#service-names) is skipped without looking inside it. For each stack, targets are built in this order:

1. With `environments`, one target is built for each declared environment, even when `path` does not contain `{environment}`. When it does, only the declared names match, so a directory such as `modules/` never becomes a target.
2. Without `environments`, when `path` contains `{environment}`, environment names are discovered from existing directories at that position. Directories at that position that are not environments, such as `modules/`, are also discovered as environments, so declare `environments` when such directories sit beside the environment directories.
3. With neither, one target with `environment: null` is built per directory, regardless of environment selection. It is shared across environments.

The attributes of the service and the stack attach to every target, however it was built. See [Attribute Values](../config-manager/README.md#attribute-values) for what they can reference.

Targets matching a stack's [exclusion conditions](../config-manager/README.md#exclusion-conditions) are left out of `targets`.

### Selecting Environments

The selectable environment list is the union of all declared names and names discovered at execution time. Excluded environments remain selectable. Omitting the selection, or giving only whitespace, targets this union. Each stack generates targets only for its own declared or discovered environments. Selecting a name absent from the union is an error.

## Matrix Output

`targets` is a JSON array. Each target has four fixed keys, with attributes and captured arbitrary placeholders flattened into the same object.

| Key | Source |
|---|---|
| `service` | Service name from a label or the `service` input; the value captured by `{service}` |
| `environment` | Declared or discovered environment name, or `null` for a target shared across environments |
| `stack` | Stack `id` |
| `working_directory` | Relative path of the existing target directory |
| Attribute keys | The service's and stack's `attributes`, plus the attributes of the profiles in `use` and the inline attributes of the selected environment |
| Arbitrary placeholder keys | Values captured from the matched path |

With the [full example configuration](../config-manager/README.md#configuration-format), an existing `dystopia/api/infrastructure/aws/develop` directory generates the following row.

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
  runs-on: ubuntu-latest
  strategy:
    matrix:
      target: ${{ fromJSON(needs.resolve.outputs.targets) }}
  steps:
    - uses: actions/checkout@v7
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

## Commands

Run these from the `action-scripts` directory.

| Command | Result |
|---|---|
| `bundle exec ruby label-resolver/bin/resolver resolve PR_NUMBER [ENVIRONMENTS]` | Resolves the PR's labels into targets; `ENVIRONMENTS` is comma-separated, and empty means all |
| `bundle exec ruby label-resolver/bin/resolver targets SERVICE [ENVIRONMENTS]` | Resolves the targets of one service without a PR; `ENVIRONMENTS` is the same as for `resolve` |

`resolve` needs `GITHUB_TOKEN` and `GITHUB_REPOSITORY` to read the labels:

```bash
export GITHUB_TOKEN=your_token
export GITHUB_REPOSITORY=owner/repo
export SOURCE_REPO_PATH=your_source_path
export WORKFLOW_CONFIG_PATH=workflow-config.yaml

bundle exec ruby label-resolver/bin/resolver resolve 123 develop
bundle exec ruby label-resolver/bin/resolver resolve 456 develop,staging
bundle exec ruby label-resolver/bin/resolver resolve 123
```

`targets` does not call the GitHub API and needs neither variable:

```bash
bundle exec ruby label-resolver/bin/resolver targets demo develop
```

`targets` takes a [valid service name](../config-manager/README.md#service-names), and any other name fails with status 1. A valid name with no matching directory is not an error: the `targets` output is `[]` and `has-targets` is `false`. The `all` name is looked up like any other. Both commands write only `targets` and `has-targets`, which leave out excluded targets. To see the excluded targets, use [`config-manager test`](../config-manager/README.md#commands).

Both commands fail with status 1 on an invalid configuration, an environment that is neither declared nor discovered, a directory that cannot be listed, and conflicting captured values. See [Environment Variables](../config-manager/README.md#environment-variables) for the variables they read.

## Code Layout

`LabelResolverController` backs the two commands. For `resolve`, `GetLabels` reads the deploy labels of the PR, and `GenerateMatrix` calls `ListCandidates`, which validates the environments and lists the candidates from the directory structure, then keeps those that are not excluded. For `targets`, `ListServiceTargets` validates the service name, calls `ListCandidates`, and returns the targets that are not excluded.

## Testing

```bash
cd action-scripts
bundle exec rspec spec/label-resolver/
```
