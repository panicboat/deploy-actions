# Deploy Actions

[🇺🇸 English](README.md) | **日本語**

複数サービスを抱えるリポジトリで、PR ラベルベースのデプロイメント・オーケストレーションを駆動する GitHub Actions ツールキット。

## Overview

ファイル変更からデプロイ対象ラベルを生成し、ラベルからデプロイメント・ターゲットを解決する層を提供します。実際の `plan`/`apply` 実行は、利用側で任意の Composite Action（Terragrunt / Helm / kustomize など）に委ねる構成です。

## Components

### 1. Config Manager (`action-scripts/config-manager/`)

`workflow-config.yaml` の stack 定義を検証し、実在するサービスの設定を診断します。

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

```yaml
- uses: panicboat/deploy-actions/label-resolver@v1
  with:
    pr-number: ${{ github.event.pull_request.number }}
    repository: ${{ github.repository }}
    github-token: ${{ secrets.GITHUB_TOKEN }}
    environments: develop  # 任意。カンマ区切り (例: develop,staging)
```

## Configuration

設定仕様、共有・独立する stack、placeholder、除外条件は [Configuration](README.md#configuration) を参照してください。

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

      # 以降は ${{ steps.resolve.outputs.targets }} を任意の deploy step に流す
```

実行レイヤ（`aws`, `kubernetes` など）は意図的に本リポジトリから除外しています。メンテナーの個人用 wrapper は [`panicboat/panicboat-actions`](https://github.com/panicboat/panicboat-actions) にあります。

## Matrix Output

固定キー、属性・抽出値の展開、対象の同一性は [Matrix Output](README.md#matrix-output) を参照してください。

## Development

### Prerequisites

- Ruby 4.0.3
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
bundle exec ruby label-dispatcher/bin/dispatcher detect
bundle exec ruby label-resolver/bin/resolver resolve PR_NUMBER
```

## License

MIT — `LICENSE` を参照。
