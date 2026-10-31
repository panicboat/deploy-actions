# Deploy Actions

[🇺🇸 English](README.md) | **日本語**

Deploy Actions は、複数のサービスを持つリポジトリで、Pull Request が何をデプロイすべきかを割り出す 2 つの GitHub Actions です。変更されたファイルから `deploy:<service>` ラベルを付け、そのラベルから JSON のターゲット一覧を作って job の matrix に渡します。`plan` や `apply`、ビルドの実行は Terragrunt、Helm、kustomize などを呼ぶ自前の step に任せます。その層はこのリポジトリに含まれません。

## How It Works

Pull Request への push は 2 つの workflow を通ります。

1. Label Dispatcher が Pull Request の base と head を比較し、変更ファイルを `workflow-config.yaml` と照合して、影響を受けるサービスごとに `deploy:<service>` ラベルを同期します。
2. ラベルが付くと `labeled` イベントが発生し、2 つ目の workflow が動きます。Label Resolver はラベルを読み、各サービスのデプロイ元ディレクトリを探して、ディレクトリと環境の組ごとに 1 つのターゲットを出力します。

あとは自前の job がターゲットごとに 1 回ずつ動きます。Config Manager は両方の action の冒頭で `workflow-config.yaml` を検証します。ローカルで実行すれば、サービスのターゲットを確認することもできます。

## Getting Started

デプロイ元リポジトリのルートに `workflow-config.yaml` を置きます。

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

サービスは `roots` の下にあるファイルを持ち、`{service}` の位置のディレクトリ名がサービス名になります。[サービス名](action-scripts/config-manager/README-ja.md#service-names)に使えるのは ASCII の英字、数字、`_`、`-` だけで、`a.b` や `.github` のようにそれ以外の文字を含むディレクトリはサービスではありません。stack はサービスの中のデプロイ元ディレクトリです。この設定では、`apps/api/src/main.rb` を変更すると Pull Request に `deploy:api` が付き、`apps/api/kubernetes/overlays/develop` ディレクトリがあれば次のターゲットが作られます。

```json
{
  "service": "api",
  "environment": "develop",
  "stack": "kustomize",
  "working_directory": "apps/api/kubernetes/overlays/develop",
  "type": "kustomize"
}
```

次に、ラベルを同期する workflow を追加します。

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

`DEPLOY_LABEL_TOKEN` には、`pull-requests: write` を持つ GitHub App のトークンか個人アクセストークンを渡します。GitHub は `GITHUB_TOKEN` が起こしたイベントでは workflow を起動しないため、`GITHUB_TOKEN` で付けたラベルでは次の workflow が動きません。

最後に、ラベルを解決してターゲットごとにデプロイの step を実行する workflow を追加します。

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

詳しいルールは各ツールの README にあります。

- [Config Manager](action-scripts/config-manager/README-ja.md): `workflow-config.yaml` の全フィールド、検証ルール、各ツールが読む環境変数。
- [Label Dispatcher](action-scripts/label-dispatcher/README-ja.md): どの変更でサービスにラベルが付くか、`ignore`、ラベルの prefix、action の入力。
- [Label Resolver](action-scripts/label-resolver/README-ja.md): ターゲットの作られ方、環境の選択、matrix の形式、Pull Request なしでのサービスの解決、action の入出力。

複数の stack と profile を使った実例は [action-scripts/workflow-config.yaml](action-scripts/workflow-config.yaml) にあります。

## Development

action の定義は `label-dispatcher/action.yaml` と `label-resolver/action.yaml` にあり、そこから呼ぶ Ruby のコードは `action-scripts/` にあります。Ruby（[.ruby-version](action-scripts/.ruby-version)）、Bundler、Git が必要です。

```bash
git clone https://github.com/panicboat/deploy-actions.git
cd deploy-actions/action-scripts
bundle install
bundle exec rspec
```

## License

MIT です。[LICENSE](LICENSE) を参照してください。
