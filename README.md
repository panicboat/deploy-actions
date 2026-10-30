# Deploy Actions

**English** | [🇯🇵 日本語](README-ja.md)

Deploy Actions is a pair of GitHub Actions that work out what a pull request needs to deploy in a multi-service repository. They turn changed files into `deploy:<service>` labels, then turn those labels into a JSON list of targets for a job matrix. Running `plan`, `apply`, or a build stays with your own steps (Terragrunt, Helm, kustomize, and so on), and that layer is not part of this repository.

## How It Works

A push to a pull request passes through two workflows:

1. Label Dispatcher compares the pull request's base and head, matches the changed files against `workflow-config.yaml`, and syncs one `deploy:<service>` label per affected service.
2. Adding a label fires the `labeled` event, which starts the second workflow. Label Resolver reads the labels, finds the directories each service deploys from, and outputs one target per directory and environment.

Your job then runs once per target. Config Manager validates `workflow-config.yaml` at the start of both actions, and you can run it locally to see the targets of a service.

## Getting Started

Put a `workflow-config.yaml` at the root of the repository you deploy from:

```yaml
services:
  - id: app
    roots:
      - "apps/{service}"
    stacks:
      - id: kustomize
        path: "kubernetes/overlays/{environment}"
        attributes:
          type: kustomize
```

A service owns the files under its `roots`, and the directory name at `{service}` becomes the service name. A [service name](action-scripts/config-manager/README.md#service-names) contains only ASCII letters, digits, `_`, and `-`, and a directory with any other name, such as `a.b` or `.github`, is not a service. A stack is a directory inside the service to deploy from. With this configuration, changing `apps/api/src/main.rb` labels the pull request `deploy:api`, and an existing `apps/api/kubernetes/overlays/develop` directory produces this target:

```json
{
  "service": "api",
  "environment": "develop",
  "stack": "kustomize",
  "working_directory": "apps/api/kubernetes/overlays/develop",
  "type": "kustomize"
}
```

Then add a workflow that dispatches the labels:

```yaml
name: Detect Changes
on:
  pull_request:
    types: [opened, synchronize, reopened]

jobs:
  dispatch:
    runs-on: ubuntu-latest
    steps:
      - uses: panicboat/deploy-actions/label-dispatcher@v0.1.0
        with:
          pr-number: ${{ github.event.pull_request.number }}
          repository: ${{ github.repository }}
          github-token: ${{ secrets.DEPLOY_LABEL_TOKEN }}
```

`DEPLOY_LABEL_TOKEN` stands for a GitHub App token or a personal access token with `pull-requests: write`. GitHub does not start workflows for events caused by `GITHUB_TOKEN`, so labels added with it would never start the workflow below.

And a workflow that resolves the labels and runs your deployment step for each target:

```yaml
name: Deploy
on:
  pull_request:
    types: [labeled]

jobs:
  resolve:
    if: startsWith(github.event.label.name, 'deploy:')
    runs-on: ubuntu-latest
    outputs:
      targets: ${{ steps.resolve.outputs.targets }}
      has-targets: ${{ steps.resolve.outputs.has-targets }}
    steps:
      - id: resolve
        uses: panicboat/deploy-actions/label-resolver@v0.1.0
        with:
          pr-number: ${{ github.event.pull_request.number }}
          repository: ${{ github.repository }}
          environments: develop

  deploy:
    needs: resolve
    if: needs.resolve.outputs.has-targets == 'true'
    runs-on: ubuntu-latest
    strategy:
      matrix:
        target: ${{ fromJSON(needs.resolve.outputs.targets) }}
    steps:
      - uses: actions/checkout@v7
      - uses: ./.github/actions/kustomize-build
        with:
          working-directory: ${{ matrix.target.working_directory }}
```

## Reference

Each tool's README holds the detailed rules:

- [Config Manager](action-scripts/config-manager/README.md): every field of `workflow-config.yaml`, its validation rules, and the environment variables the tools read.
- [Label Dispatcher](action-scripts/label-dispatcher/README.md): which changes label a service, `ignore`, label prefixes, and the action's inputs and outputs.
- [Label Resolver](action-scripts/label-resolver/README.md): how targets are built, environment selection, the matrix format, resolving a service without a pull request, and the action's inputs and outputs.

[action-scripts/workflow-config.yaml](action-scripts/workflow-config.yaml) is a working configuration with several stacks and profiles.

## Development

The actions are defined in `label-dispatcher/action.yaml` and `label-resolver/action.yaml`, and the Ruby code they call lives in `action-scripts/`. You need Ruby ([.ruby-version](action-scripts/.ruby-version)), Bundler, and Git.

```bash
git clone https://github.com/panicboat/deploy-actions.git
cd deploy-actions/action-scripts
bundle install
bundle exec rspec
```

## License

MIT. See [LICENSE](LICENSE).
