# Deploy Actions

[🇺🇸 English](README.md) | **日本語**

複数サービスを抱えるリポジトリで、PR ラベルベースのデプロイメント・オーケストレーションを駆動する GitHub Actions ツールキット。

## 概要

ファイル変更からデプロイ対象ラベルを生成し、ラベルからデプロイメント・ターゲットを解決する層を提供します。実際の `plan`/`apply` 実行は、利用側で任意の Composite Action（Terragrunt / Helm / kustomize など）に委ねる構成です。

## 構成要素

### 1. Config Manager (`action-scripts/config-manager/`)

`workflow-config.yaml` の stack 定義を検証し、設定表示・環境一覧・実在ディレクトリのサービス診断・テンプレート生成を提供します。

**特徴:**

- 詳細なエラーレポート付きの設定検証
- 定義環境の一覧とサービス診断
- stack のパスと除外条件の検証
- テンプレート生成

### 2. Label Dispatcher (`label-dispatcher/`)

PR の変更ファイルを検出し、変更があったサービスに対して `deploy:<service>` ラベルを付与します。

**特徴:**

- `git diff` からの変更検出
- ディレクトリパターンからのサービス発見
- 自動ラベル生成
- 除外処理

### 3. Label Resolver (`label-resolver/`)

`deploy:<service>` ラベルと指定環境を、後続 Action が利用する matrix に変換します。

**特徴:**

- ラベルからターゲットへの解決
- 定義環境と探索した環境からの対象選択
- デプロイメント matrix 生成
- 安全性検証

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

`environments` は任意の入力で、複数環境はカンマ区切りで指定します。省略すると定義環境と探索した環境をすべて対象にします。

```yaml
- uses: panicboat/deploy-actions/label-resolver@v1
  with:
    pr-number: ${{ github.event.pull_request.number }}
    repository: ${{ github.repository }}
    github-token: ${{ secrets.GITHUB_TOKEN }}
    environments: develop
```

## 設定

`workflow-config.yaml` のトップレベルには、空でない `stacks` 配列を定義します。同じ stack のパス、環境属性、除外条件を一つの定義で管理します。

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

### stack の定義

| フィールド | 指定 | 動作 |
|---|---|---|
| `name` | 必須 | stack の種類。属性名やプロバイダーを制限しない |
| `id` | 任意 | インスタンス識別子。省略時は `name`。設定全体で一意 |
| `paths` | 必須 | 空でない相対パス配列。全パスに `{service}` が必要 |
| `environments` | 任意 | 環境名をキー、環境属性を値とする空でないマップ |
| `attributes` | 任意 | 環境共通の対象を明示する。`attributes: {}` も有効。`environments` と併用できない |
| `exclude` | 任意 | 除外条件の配列。省略時は空配列 |

共有するプロダクトは一つの定義の `paths` に追加します。独立させる場合は、同じ `name` に異なる `id` を付けた別定義にし、それぞれにパスと属性を置きます。

`environments` のキーがその stack の環境名です。`environments` と `attributes` の両方を省略した stack は、パスに一致する実在ディレクトリの `{environment}` の位置から環境名を取得します。この場合は全パスに `{environment}` が必要で、含まないパスがあれば設定エラーになります。探索した対象に追加属性はなく、別 stack の環境・属性・除外条件は継承しません。

選択できる環境一覧は、全 stack の定義環境と実行時に探索した環境名の和集合です。除外された環境名も選択できます。環境指定を省略するとこの和集合を対象にします。各 stack は自身の定義環境または探索した環境だけを生成し、和集合にない環境指定はエラーになります。

パスに `{environment}` がなくても、`environments` があれば環境ごとの対象になります。同じディレクトリを異なる環境属性で使えます。`attributes` があれば環境共通で、環境選択数にかかわらず `environment: null` の対象を各ディレクトリにつき一度だけ生成します。この場合はパスに `{environment}` を指定できません。属性が不要な環境共通の対象には `attributes: {}` を明示します。

### Attribute Values

`attributes` と環境属性マップの文字列値では、`{service}` とパスから抽出した `{team}` などの任意 placeholder を使えます。環境属性では、パスに含まれない場合も `{environment}` を使えます。マップや配列に入れ子になった文字列にも同じ規則を適用します。マップのキーはリテラルのままで、文字列以外の値は型を保持します。環境間で属性キーを揃える必要はありません。

属性が参照する placeholder は、その stack のすべてのパスで取得できる必要があり、解決できない参照は設定エラーになります。環境共通の属性では `{environment}` を参照できません。例えば `paths: ["teams/{team}/{service}"]` と `attributes: {repository: "ghcr.io/{team}/{service}"}` の組み合わせは、`teams/payments/api` に対して `ghcr.io/payments/api` を出力します。

### パスの照合

パスはリポジトリルートからの完全な相対パターンです。絶対パスと `..` 要素は拒否し、先頭の `./`、余分な `/`、`.` 要素は正規化します。すべてのパターンに一致する実在ディレクトリを列挙し、存在しないパスは対象を生成しません。サービスの登録は不要です。ドットで始まるサービスは対象外です。

`{team}` などの任意 placeholder を使えます。名前は `[a-z_][a-z0-9_]*`、値はパスの一要素です。同じ名前を繰り返した場合は、すべて同じ値に一致する必要があります。glob の記号はリテラルとして扱います。任意 placeholder と matrix の固定キー、または同じ stack のいずれかの環境属性・共通属性キーが衝突する定義は拒否します。

### 除外条件

`exclude` の各要素は空でない条件マップです。`service`、`environment`、その stack のいずれかのパスにある任意 placeholder を条件にできます。属性名は条件キーとして使えません。

一つのマップ内は AND、配列内は OR で完全一致を判定します。省略したキーは制約になりません。service のみ、environment のみ、任意 placeholder のみでも指定できます。照合したパスにない抽出値を要求する条件は一致しません。

条件値は空でない文字列で、`/`、`.`、`..` は使えません。service はドットで始められません。`environments` を指定した stack の環境条件は自身の定義環境だけを指定できます。環境を探索する stack では、まだ存在しないディレクトリの環境値も条件にできます。環境共通 stack では environment の省略または `null` を受け付け、environment 以外の条件値に `null` は使えません。条件値はリテラルで、placeholder は展開しません。

実行可能な設定例は [workflow-config.yaml](action-scripts/workflow-config.yaml) を参照してください。

## ワークフローへの組み込み

### 1. 変更検出

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

### 2. デプロイ対象の解決

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

`${{ steps.resolve.outputs.targets }}` を利用側のデプロイ処理に渡します。

実行レイヤ（`aws`, `kubernetes` など）は意図的に本リポジトリから除外しています。メンテナーの個人用 wrapper は [`panicboat/panicboat-actions`](https://github.com/panicboat/panicboat-actions) にあります。

## matrix 出力

`label-resolver` は `outputs.targets` と環境変数 `DEPLOYMENT_TARGETS` に JSON 配列を出力します。固定キーは次の5個で、属性と任意 placeholder の抽出値を同じ階層に展開します。

| キー | 出力元 |
|---|---|
| `service` | ラベルまたは `deploy:all` で探索したサービス名 |
| `environment` | 定義または探索した環境名。環境共通なら `null` |
| `stack` | stack の `name` |
| `stack_id` | 確定した `id` |
| `working_directory` | 実在する対象ディレクトリの相対パス |
| 属性のキー | 当該環境属性、または共通 `attributes` |
| 任意 placeholder のキー | 一致したパスの抽出値 |

上記の設定例で `teams/payments/api/aws/develop` が存在する場合、次の行を生成します。

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

対象の同一性は service・stack_id・environment・working_directory で決まります。同じ対象の重複は一行にまとめます。同じ対象を異なる抽出値マップで解釈するパスは、除外条件や記載順にかかわらずエラーになります。下流では `${{ matrix.team }}` のように任意のキーを参照できます。

## 開発

### 前提条件

- Ruby ([.ruby-version](action-scripts/.ruby-version))
- Bundler
- Git

### セットアップ

```bash
git clone https://github.com/panicboat/deploy-actions.git
cd deploy-actions/action-scripts
bundle install
bundle exec rspec
```

### 各コンポーネントの動作確認

```bash
bundle exec ruby config-manager/bin/config-manager validate
bundle exec ruby label-dispatcher/bin/dispatcher test
bundle exec ruby label-resolver/bin/resolver resolve PR_NUMBER
```

## ライセンス

MIT — `LICENSE` を参照。
