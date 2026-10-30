# Label Resolver

[🇺🇸 English](README.md) | **日本語**

Label Resolver は `deploy:<service>` ラベル、または直接渡したサービス名から、job の matrix に渡すデプロイターゲットの JSON 配列を作ります。環境は入力で指定し、ブランチ名からは決めないので、1 回の実行で好きな環境の組み合わせを対象にできます。

## Action

ふつうは Pull Request のラベルを解決します。`environments` は省略できます。名前を 1 つかカンマ区切りの一覧を渡し、省略すると定義された環境と探索された環境のすべてが対象になります。

```yaml
- uses: panicboat/deploy-actions/label-resolver@v0.1.0
  with:
    pr-number: ${{ github.event.pull_request.number }}
    repository: ${{ github.repository }}
    environments: "develop,staging"
```

`service` を指定すると、Pull Request なしでサービスまたは `all` を解決します。release や手動実行の workflow に向いています。このとき `pr-number` は無視され、`ref` でソースリポジトリの checkout 先を選びます。

```yaml
- uses: panicboat/deploy-actions/label-resolver@v0.1.0
  with:
    repository: ${{ github.repository }}
    service: api
    environments: production
    ref: ${{ github.event.release.tag_name }}
```

action はリポジトリを自分で checkout するので、job に checkout の step は要りません。最初に [Config Manager](../config-manager/README-ja.md) で設定を検証します。`service` も `pr-number` もなければ失敗します。

入力:

| 入力 | 必須 | 値 |
|---|---|---|
| `repository` | はい | ソースリポジトリ（`owner/repo`） |
| `pr-number` | `service` がなければ必須 | ラベルを解決する Pull Request。`service` があれば無視されます |
| `service` | いいえ | サービス名または `all`。Pull Request なしでターゲットを解決します |
| `environments` | いいえ | カンマ区切りの環境。空なら定義された環境と探索された環境のすべて |
| `ref` | いいえ | checkout するソースリポジトリの ref。既定は、起動元のリポジトリならイベントの ref、別のリポジトリならデフォルトブランチ |
| `github-token` | いいえ | リポジトリの checkout と PR の読み取りに使うトークン。既定は `${{ github.token }}` |
| `config-path` | いいえ | 設定ファイルのパス。既定は `workflow-config.yaml` |

出力:

| 出力 | 値 |
|---|---|
| `targets` | デプロイターゲットの JSON 配列（[Matrix Output](#matrix-output) を参照） |
| `has-targets` | `true` または `false` |
| `candidates` | `service` を指定したときの、除外されたものも含む全候補の JSON 配列。各要素は `{"target": <matrix item>, "excluded": <bool>, "root": "<root>"}` |

## From Labels to Targets

resolver は Pull Request のラベルのうち、[設定された prefix](../label-dispatcher/README-ja.md#labels)（既定は `deploy:`）のいずれかで始まるものを読み、残りの部分をサービス名として扱います。同じサービスに別の prefix のラベルが付いていても 1 つのサービスとして扱います。どの prefix でも `all` なら、設定されたパスから見つかる全サービスが対象です。残りの部分が正しいサービス名（`[a-zA-Z0-9_-]+`）でないラベルは無視します。

デプロイラベルのない Pull Request では、`targets` は空、`has-targets` は `false` になります。

`labeled` で起動する workflow では、使っている prefix で絞り込みます。`prefix` を変えたり `extra_prefixes` を足したりしたら、`if` の条件を設定したすべての prefix に合わせて更新します。たとえば `startsWith(github.event.label.name, 'deploy:') || startsWith(github.event.label.name, 'manual/')` です。

## How Targets Are Built

resolver は、いずれかの root に `path` を続けたパターンに一致する実在のディレクトリをすべて列挙します。存在しないパスからターゲットは作られず、結果が空でも正常です。サービスの事前登録は不要です。stack ごとに、次の順でターゲットを作ります。

1. `environments` があれば、`path` に `{environment}` がなくても、定義された環境ごとに 1 つのターゲットを作ります。`path` に `{environment}` があれば定義された名前だけが一致するので、`modules/` のようなディレクトリはターゲットになりません。
2. `environments` がなく `path` に `{environment}` があれば、その位置の実在ディレクトリから環境名を探索します。`modules/` のように環境でないディレクトリも環境として探索されるので、そうしたディレクトリが環境ディレクトリと並ぶなら `environments` を定義します。
3. どちらもなければ、環境の選択にかかわらず、ディレクトリごとに `environment: null` のターゲットを 1 つ作ります。環境をまたいで共有されるターゲットです。

サービスと stack の属性は、作られ方によらずすべてのターゲットに付きます。参照できる値は [Attribute Values](../config-manager/README-ja.md#attribute-values) を参照してください。

stack の[除外条件](../config-manager/README-ja.md#exclusion-conditions)に一致するターゲットは `targets` から外れます。

### Selecting Environments

選択できる環境は、定義された名前と実行時に探索された名前の和集合です。除外された環境も選択できます。選択を省略するか空白だけを渡すと、この和集合が対象になります。各 stack は、自身が定義または探索した環境についてだけターゲットを作ります。和集合にない名前を選ぶとエラーです。

## Matrix Output

`targets` は JSON 配列です。各ターゲットには 4 つの固定キーがあり、属性と任意のプレースホルダーの取得値が同じオブジェクトに平坦に入ります。

| キー | 由来 |
|---|---|
| `service` | ラベルまたは `<prefix>all` で見つかったサービス名。`{service}` で取得した値 |
| `environment` | 定義または探索された環境名。環境をまたいで共有するターゲットでは `null` |
| `stack` | stack の `id` |
| `working_directory` | 実在するターゲットディレクトリの相対パス |
| 属性キー | サービスと stack の `attributes`、選択された環境の `use` の profile の属性、インライン属性 |
| 任意のプレースホルダーのキー | 一致したパスから取得した値 |

[全体の設定例](../config-manager/README-ja.md#configuration-format)で `dystopia/api/infrastructure/aws/develop` ディレクトリがあると、次の行が作られます。

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

ターゲットは `service`、`stack`、`environment`、`working_directory` で識別します。重複するターゲットは 1 行にまとめます。同じターゲットを異なる取得値のマップで解釈するパスがあると、除外の有無や定義の順序によらずエラーになります。

stack の種類は自分で定義する属性なので、後続の step は `matrix.target.type` で分岐します。`resolve` という job で `steps.resolve.outputs.targets` を job の output `targets` として公開し、後の job で使います。

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

`action-scripts` ディレクトリで実行します。

| コマンド | 結果 |
|---|---|
| `bundle exec ruby label-resolver/bin/resolver resolve PR_NUMBER [ENVIRONMENTS]` | PR のラベルをターゲットに解決します。`ENVIRONMENTS` はカンマ区切りで、空ならすべて |
| `bundle exec ruby label-resolver/bin/resolver targets SERVICE [ENVIRONMENTS]` | PR なしで 1 つのサービスまたは `all` のターゲットを解決します。`ENVIRONMENTS` は `resolve` と同じ |

`resolve` はラベルを読むために `GITHUB_TOKEN` と `GITHUB_REPOSITORY` を必要とします。

```bash
export GITHUB_TOKEN=your_token
export GITHUB_REPOSITORY=owner/repo
export SOURCE_REPO_PATH=your_source_path
export WORKFLOW_CONFIG_PATH=workflow-config.yaml

bundle exec ruby label-resolver/bin/resolver resolve 123 develop
bundle exec ruby label-resolver/bin/resolver resolve 456 develop,staging
bundle exec ruby label-resolver/bin/resolver resolve 123
```

`targets` は GitHub API を呼ばず、どちらの変数も必要としません。

```bash
bundle exec ruby label-resolver/bin/resolver targets demo develop
bundle exec ruby label-resolver/bin/resolver targets all
```

`targets` に渡せるのは `[a-zA-Z0-9_-]+` に一致する名前か `all` で、それ以外の名前は終了コード 1 で失敗します。正しい名前で一致するディレクトリがないのはエラーにならず、出力の `targets` は `[]`、`has-targets` は `false`、`candidates` は `[]` になります。出力の `targets` と `has-targets` は除外されなかった候補から作られ、`candidates` は全候補を除外状態と root とともに並べます。`resolve` コマンドが書き出すのは `targets` と `has-targets` だけです。

どちらのコマンドも、不正な設定、定義も探索もされていない環境、列挙できないディレクトリ、取得値の食い違いがあると終了コード 1 で失敗します。読む環境変数は [Environment Variables](../config-manager/README-ja.md#environment-variables) を参照してください。

## Code Layout

2 つのコマンドの入口は `LabelResolverController` です。`resolve` では、`GetLabels` が PR のデプロイラベルを読み、`GenerateMatrix` が `ListCandidates` を呼んで、除外されなかった候補を残します。`ListCandidates` は環境を検証し、ディレクトリ構造から候補を列挙します。`targets` では、`ListServiceTargets` がサービス名を検証して `ListCandidates` を呼び、ターゲットと、除外状態と root を付けた全候補を返します。

## Testing

```bash
cd action-scripts
bundle exec rspec spec/label-resolver/
```
