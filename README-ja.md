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
- ディレクトリパターンからのサービス発見
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
    pr-number: ${{ github.event.pull_request.number }}
    repository: ${{ github.repository }}
    github-token: ${{ secrets.GITHUB_TOKEN }}
    environments: develop  # 任意。カンマ区切り (例: develop,staging)
```

## 設定

`workflow-config.yaml` を読み込みます。

```yaml
environments:
  - environment: develop
    stacks:
      aws:
        aws_region: ap-northeast-1
        iam_role_plan: arn:aws:iam::ACCOUNT:role/plan-role
        iam_role_apply: arn:aws:iam::ACCOUNT:role/apply-role

stack_conventions:
  - root: "{service}"          # {service}/{environment} 以外の任意 placeholder
                               # も使用可能。抽出された値は matrix item の
                               # トップレベル（例: {team}）に展開される。
    stacks:
      - name: aws
        directory: "aws/{environment}"
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

### 2. デプロイターゲット解決

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

`label-resolver` は `outputs.targets`（および環境変数 `DEPLOYMENT_TARGETS`）として JSON 配列を出力します。各 matrix item はフラット構造です。

| Key | 由来 | 補足 |
|---|---|---|
| `service` | 固定 | `deploy:<service>` ラベルの service 名 |
| `environment` | 固定 | environment-agnostic stack では `null` |
| `stack` | 固定 | 例: `aws`, `kubernetes` |
| `working_directory` | 固定 | 実在する deploy 対象ディレクトリ |
| `stack_convention_root` | 固定 | マッチした root pattern の展開後の値 |
| (attributes のキー) | 動的 | `environments[].stacks[stack].*` で定義された値 |
| (captures のキー) | 動的 | マッチした pattern 中の任意 `{placeholder}` の抽出値（`service` / `environment` を除く） |

例として、次の `workflow-config.yaml` を考えます。

```yaml
environments:
  - environment: develop
    stacks:
      aws:
        aws_region: ap-northeast-1
        iam_role_plan: arn:aws:iam::ACCOUNT:role/plan-role
        iam_role_apply: arn:aws:iam::ACCOUNT:role/apply-role

stack_conventions:
  - root: "{team}/{service}"
    stacks:
      - name: aws
        directory: "aws/{environment}"
```

このとき `payments/api/aws/develop` が deploy 対象として解決されると、matrix item は次のようになります。

```json
{
  "service": "api",
  "environment": "develop",
  "stack": "aws",
  "working_directory": "payments/api/aws/develop",
  "stack_convention_root": "payments/api",
  "aws_region": "ap-northeast-1",
  "iam_role_plan": "arn:aws:iam::ACCOUNT:role/plan-role",
  "iam_role_apply": "arn:aws:iam::ACCOUNT:role/apply-role",
  "team": "payments"
}
```

`aws_region` / `iam_role_plan` / `iam_role_apply` は `environments[0].stacks.aws` の attributes が、`team` は `root` の `{team}` プレースホルダ抽出値がそれぞれ展開されたものです。下流の Composite Action では `${{ matrix.team }}` のように任意のキーを直接参照できます。固定キーや attributes キーと衝突する placeholder 名は `config-manager validate` の段階で拒否されます。

## 開発

### 前提条件

- Ruby 4.0.3
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
