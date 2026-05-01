# Deploy Actions

[🇺🇸 English](README.md) | **日本語**

複数サービスを抱えるリポジトリで、PR ラベルベースのデプロイメント・オーケストレーションを駆動する GitHub Actions ツールキット。

## 概要

ファイル変更からデプロイ対象ラベルを生成し、ラベルからデプロイメント・ターゲットを解決する層を提供します。実際の `plan`/`apply` 実行は、利用側で任意の Composite Action（Terragrunt / Helm / kustomize など）に委ねる構成です。

## コンポーネント

### 1. Config Manager (`action-scripts/config-manager/`)

`workflow-config.yaml` を検証・管理。環境・サービス・ディレクトリ規約を定義します。

**特徴:**

- 詳細なエラーレポート付きの設定検証
- 環境とサービスの管理
- ディレクトリ規約の検証
- テンプレート生成

### 2. Label Dispatcher (`label-dispatcher/`)

PR の変更ファイルを検出し、変更があったサービスに対して `deploy:<service>` ラベルを付与します。

**特徴:**

- `git diff` からの変更検出
- ディレクトリ パターンからのサービス発見
- 自動ラベル生成
- 除外処理

### 3. Label Resolver (`label-resolver/`)

`deploy:<service>` ラベルとブランチ情報を、後続 Action が利用するデプロイメント・ターゲットの matrix に変換します。

**特徴:**

- ラベルからターゲットへの解決
- ブランチからの環境検出
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

```yaml
- uses: panicboat/deploy-actions/label-resolver@v1
  with:
    action-type: plan  # or apply
    pr-number: ${{ github.event.pull_request.number }}
    repository: ${{ github.repository }}
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

## 設定

`workflow-config.yaml` を読み込みます。

```yaml
environments:
  - environment: develop
    stacks:
      terragrunt:
        aws_region: ap-northeast-1
        iam_role_plan: arn:aws:iam::ACCOUNT:role/plan-role
        iam_role_apply: arn:aws:iam::ACCOUNT:role/apply-role
      kubernetes: {}

stack_conventions:
  - root: "{service}"
    stacks:
      - name: terragrunt
        directory: "terragrunt/{environment}"
        required_attributes: [aws_region, iam_role_plan, iam_role_apply]
      - name: kubernetes
        directory: "kubernetes/overlays/{environment}"

services:
  - name: excluded-service
    exclude_from_automation: true
    exclusion_config:
      reason: "手動デプロイが必要"
      type: "permanent"
```

実行可能なサンプルは `action-scripts/workflow-config.yaml` を参照してください。

## ワークフロー統合

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

### 2. デプロイ ターゲット解決

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
          action-type: plan
          pr-number: ${{ github.event.pull_request.number }}
          repository: ${{ github.repository }}
          github-token: ${{ secrets.GITHUB_TOKEN }}

      # 以降は ${{ steps.resolve.outputs.deployment-targets }} を任意の deploy step に流す
```

実行レイヤ（`terragrunt`, `kubernetes` など）は意図的に本リポジトリから除外しています。メンテナーの個人用 wrapper は [`panicboat/panicboat-actions`](https://github.com/panicboat/panicboat-actions) にあります。

## 開発

### 前提条件

- Ruby 3.4+
- Bundler
- Git

### セットアップ

```bash
git clone https://github.com/panicboat/deploy-actions.git
cd deploy-actions/action-scripts
bundle install
bundle exec rspec
```

### コンポーネント別テスト

```bash
bundle exec ruby config-manager/bin/config-manager validate
bundle exec ruby label-dispatcher/bin/dispatcher detect
bundle exec ruby label-resolver/bin/resolver resolve PR_NUMBER
```

## License

MIT — `LICENSE` を参照。
