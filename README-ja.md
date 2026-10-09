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
- 定義された環境からの対象選択
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

`environments` は任意の入力で、複数環境はカンマ区切りで指定します。省略すると全定義環境を対象にします。

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
      repository: registry.example.com/app
```

### stack の定義

| フィールド | 指定 | 動作 |
|---|---|---|
| `name` | 必須 | stack の種類。属性名やプロバイダーを制限しない |
| `id` | 任意 | インスタンス識別子。省略時は `name`。設定全体で一意 |
| `paths` | 必須 | 空でない相対パス配列。全パスに `{service}` が必要 |
| `environments` | 任意 | 環境名をキー、環境属性を値とする空でないマップ |
| `attributes` | 任意 | 環境共通の属性。`environments` と併用できない |
| `exclude` | 任意 | 除外条件の配列。省略時は空配列 |

共有するプロダクトは一つの定義の `paths` に追加します。独立させる場合は、同じ `name` に異なる `id` を付けた別定義にし、それぞれにパスと属性を置きます。

`environments` のキーがその stack の環境名です。環境一覧は全 stack の和集合になり、環境指定を省略すると全定義環境が対象になります。各 stack は自身の定義環境だけを生成し、未知の環境指定はエラーになります。属性の値と型はそのまま出力され、環境間の属性キーを揃える必要はありません。

パスに `{environment}` がなくても、`environments` があれば環境ごとの対象になります。同じディレクトリを異なる環境属性で使えます。`environments` がなければ環境共通で、`environment: null` の対象を各ディレクトリにつき一度だけ生成します。この場合の属性は `attributes` から取得し、パスに `{environment}` は指定できません。

### パスの照合

パスはリポジトリルートからの完全な相対パターンです。絶対パスと `..` 要素は拒否し、先頭の `./`、余分な `/`、`.` 要素は正規化します。すべてのパターンに一致する実在ディレクトリを列挙し、存在しないパスは対象を生成しません。サービスの登録は不要です。ドットで始まるサービスは対象外です。

`{team}` などの任意 placeholder を使えます。名前は `[a-z_][a-z0-9_]*`、値はパスの一要素です。同じ名前を繰り返した場合は、すべて同じ値に一致する必要があります。glob の記号はリテラルとして扱います。任意 placeholder と matrix の固定キー、または同じ stack のいずれかの環境属性・共通属性キーが衝突する定義は拒否します。

### 除外条件

`exclude` の各要素は空でない条件マップです。`service`、`environment`、その stack のいずれかのパスにある任意 placeholder を条件にできます。属性名は条件キーとして使えません。

一つのマップ内は AND、配列内は OR で完全一致を判定します。省略したキーは制約になりません。service のみ、environment のみ、任意 placeholder のみでも指定できます。照合したパスにない抽出値を要求する条件は一致しません。

条件値は空でない文字列で、`/`、`.`、`..` は使えません。service はドットで始められません。環境条件は自身の定義環境だけを指定できます。環境共通 stack では environment の省略または `null` を受け付け、environment 以外の条件値に `null` は使えません。

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
| `environment` | 定義した環境名。環境共通なら `null` |
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
