# Label Dispatcher

**English** | [🇯🇵 日本語](README-ja.md)

Label Dispatcher finds the services a pull request changes and keeps `deploy:<service>` labels on the pull request in sync. Those labels are the input to [Label Resolver](../label-resolver/README.md).

## Action

```yaml
- uses: panicboat/deploy-actions/label-dispatcher@v0.1.0
  with:
    pr-number: ${{ github.event.pull_request.number }}
    repository: ${{ github.repository }}
    github-token: ${{ secrets.DEPLOY_LABEL_TOKEN }}
```

The action checks out `repository` itself with full history, so the job needs no checkout step. It validates the configuration with [Config Manager](../config-manager/README.md) before it looks at any labels.

Inputs:

| Input | Required | Value |
|---|---|---|
| `pr-number` | Yes | Pull request to label |
| `repository` | Yes | Source repository (`owner/repo`) |
| `github-token` | Yes | Token with `pull-requests: write`, for checking out the repository and changing labels |
| `config-path` | No | Path to the configuration file inside the repository; defaults to `workflow-config.yaml` |

Labels added with `GITHUB_TOKEN` do not start other workflows, so pass a GitHub App token or a personal access token when a `labeled` workflow runs the resolver.

Outputs:

| Output | Value |
|---|---|
| `labels-added` | JSON array of the labels the PR did not have before the run |
| `labels-removed` | JSON array of the labels the run took off the PR and did not add back |
| `services-detected` | JSON array of the services detected from the changes |
| `has-changes` | `true` when at least one service was detected, otherwise `false` |

## Change Detection

A service gets a label when a changed file sits below one of its roots. The dispatcher compares the pull request's base and head with a three-dot diff, then evaluates every changed file against every root in this order:

1. The file is skipped when it is not below the root, or when the `{service}` capture is not a [valid service name](../config-manager/README.md#service-names).
2. The file is skipped when its path relative to the root matches an `ignore` pattern.
3. When the file is below a stack's directory (root followed by `path`), candidate targets are built as [Label Resolver builds them](../label-resolver/README.md#how-targets-are-built). The service is labeled unless `exclude` removes every candidate.
4. When the file is below no stack's directory, such as `modules/` or `Makefile`, the service is labeled. `exclude` does not apply to these shared files, so use `ignore` to skip them.

Matching works on paths alone, so directories do not need to exist and deleted files are matched too. A stack's path resolves to a directory, which means a file whose own path equals that directory's path is not below it.

Candidates depend on how the stack gets its environments. A stack with `environments` accepts only its declared names, and a path without `{environment}` is evaluated for each declared environment. A stack that discovers environments uses the name captured from the changed path. A stack with neither is evaluated with `environment: null`.

Three cases change the outcome of rules 3 and 4:

- A stack with `path: "."` has the root itself as its directory, but it does not count as a stack's directory for rule 4. Its candidates label the service as in rule 3. When `exclude` removes all of them, rule 4 still applies unless the file is below another stack's directory.
- A file below another stack's directory whose candidates are all excluded is still not labeled.
- For a stack with `environments`, a directory at the `{environment}` position that is not a declared environment is outside the stack's directory.

Choose roots narrow enough that unrelated top-level directories are not taken as services. A bare `{service}` root, for example, makes every top-level directory with a valid service name a service.

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

### Ignoring Files

`ignore` patterns are globs relative to the root: for root `dystopia/{service}`, the file `dystopia/api/docs/guide.md` is matched as `docs/guide.md`. `*` does not cross `/`, and `**/` matches zero or more directories. A trailing `/**` matches every file below that directory. Files starting with a dot match, and `?`, `[...]`, and `{a,b}` work as in shell globs.

`ignore` affects change detection only. Label Resolver still generates targets under ignored paths.

## Labels

Each run removes every label on the pull request that starts with the prefix, creates any required label missing from the repository, and adds the required labels. Removing the labels first means each push fires `labeled` again, and that event starts the resolver. Labels are added one at a time, so a push that labels two services fires `labeled` twice, and each resolver run reads the labels on the pull request at that moment.

The `labels` key sets the prefixes. This fragment goes at the top level of `workflow-config.yaml`, next to `services`:

```yaml
labels:
  prefix: "deploy:"
  extra_prefixes: ["manual/"]
```

| Field | Requirement | Behavior |
|---|---|---|
| `prefix` | Optional | Prefix of the labels managed by Label Dispatcher; defaults to `deploy:` |
| `extra_prefixes` | Optional | Array of additional prefixes read by Label Resolver; defaults to an empty array |

Each prefix is used as-is, including its separator, so quote prefixes ending with `:` in YAML. Prefixes must be nonempty strings. No prefix may start with another prefix, because Label Dispatcher would remove the labels of the overlapping prefix.

A label added by hand with `prefix` is removed on the next push. Labels starting with an `extra_prefixes` entry are never touched, so `manual/api` survives later pushes.

Only a [valid service name](../config-manager/README.md#service-names) gets a label. A directory such as `a.b` is not a service, so a change below it labels nothing. A directory named `all` is an ordinary service and gets `<prefix>all`, which [Label Resolver reads](../label-resolver/README.md#from-labels-to-targets) as that one service.

## Commands

Run these from the `action-scripts` directory.

| Command | Result |
|---|---|
| `bundle exec ruby label-dispatcher/bin/dispatcher dispatch PR_NUMBER` | Detects changes from the PR's base and head and syncs the PR labels |
| `bundle exec ruby label-dispatcher/bin/dispatcher test [--base-ref=REF] [--head-ref=REF]` | Prints the labels a change would get, without calling GitHub |

`dispatch` needs `GITHUB_TOKEN` and `GITHUB_REPOSITORY`. See [Environment Variables](../config-manager/README.md#environment-variables) for the other variables.

`test` picks what to compare from its options:

```bash
bundle exec ruby label-dispatcher/bin/dispatcher test
bundle exec ruby label-dispatcher/bin/dispatcher test --base-ref=main
bundle exec ruby label-dispatcher/bin/dispatcher test --base-ref=main --head-ref=feature/auth
```

Without refs it uses staged and unstaged changes, which leaves out untracked files. With `--base-ref` alone it diffs the base ref against the working tree. With both options it runs the same three-dot diff as `dispatch`. `--head-ref` alone is an error, and a ref that does not exist stops the command with an error, without falling back to working-tree changes.

Both commands print the labels and the changed files, listing the first 10 when there are more, and `dispatch` also prints the labels it added and removed. To see which targets are excluded, use [`config-manager test`](../config-manager/README.md#commands).

Errors exit with status 1. GitHub API requests go through Octokit's default retry middleware, which retries idempotent requests up to twice without a delay. A failure after that stops the command with the API's error message.

## Code Layout

`LabelDispatcherController` backs the two commands. `DispatchLabels` gets the PR's base and head SHAs and calls `DetectChangedServices`, which lists the changed files and maps them to services, and `ManageLabels`, which syncs the labels. `GitHubClient` wraps Octokit, `GitClient` runs `git diff --name-only`, `ConfigClient` loads the configuration, `RepositoryRoot` locates the repository that `git diff` runs in, and `Composition` builds the clients and the presenter from the environment variables.

## Testing

```bash
cd action-scripts
bundle exec rspec spec/label-dispatcher/
```
