# Deploy Actions

TerragruntとKubernetesを使用したマルチサービス デプロイメント オーケストレーションのための包括的なGitHub Actions自動化ツールキット。

## 概要

Deploy Actionsは、複数のサービスと環境にわたるデプロイメントを自動化するための完全なソリューションを提供します。インテリジェントな変更検出、設定の検証、デプロイメント オーケストレーションを組み合わせて、複雑なマルチサービス アーキテクチャのCI/CDワークフローを効率化します。

## 主要機能

- **インテリジェント変更検出**: ファイル変更から変更されたサービスを自動検出
- **設定管理**: デプロイメント設定の検証と管理
- **デプロイメント解決**: PRラベルからデプロイメント ターゲットへの変換
- **マルチスタック サポート**: TerragruntとKubernetesデプロイメントをサポート
- **セキュリティ ファースト**: 組み込みの安全性チェックとIAMロール管理
- **マトリックス生成**: 並列実行のためのデプロイメント マトリックスの作成

## アーキテクチャ

ツールキットは3つの主要コンポーネントで構成されています：

### 1. Config Manager (`config-manager/`)
デプロイメント環境、サービス、自動化ルールを定義するワークフロー設定ファイルを検証・管理します。

**主要機能:**
- 詳細なエラーレポート付きの設定検証
- 環境とサービスの管理
- ディレクトリ規約の検証
- テンプレート生成

### 2. Label Dispatcher (`label-dispatcher/`)
ファイル変更を分析し、変更されたサービスのデプロイメント ラベルを自動作成します。

**主要機能:**
- git diffからの変更検出
- ディレクトリ パターンからのサービス発見
- 自動ラベル生成
- 除外処理

### 3. Deploy Resolver (`deploy-resolver/`)
PRラベルとブランチ情報をGitHub Actions自動化のためのデプロイメント ターゲットに変換します。

**主要機能:**
- ラベルからターゲットへの解決
- ブランチからの環境検出
- デプロイメント マトリックス生成
- 安全性検証

## 複合アクション

ツールキットは、すぐに使用できる複合アクションを提供します：

### Label Dispatcher
```yaml
- uses: panicboat/deploy-actions/label-dispatcher@main
  with:
    base-ref: ${{ github.event.pull_request.base.ref }}
    head-ref: ${{ github.head_ref }}
    repository: ${{ github.repository }}
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

### Label Resolver
```yaml
- uses: panicboat/deploy-actions/label-resolver@main
  with:
    action-type: plan  # または apply
    pr-number: ${{ github.event.pull_request.number }}
    repository: ${{ github.repository }}
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

### Deploy Terragrunt
```yaml
- uses: panicboat/deploy-actions/deploy-terragrunt@main
  with:
    deployment-targets: ${{ steps.resolve.outputs.deployment-targets }}
    action-type: plan  # または apply
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

## 設定

ツールキットは一元化された`workflow-config.yaml`ファイルを使用します：

```yaml
# 環境設定
environments:
  - environment: develop
    aws_region: ap-northeast-1
    iam_role_plan: arn:aws:iam::ACCOUNT:role/plan-role
    iam_role_apply: arn:aws:iam::ACCOUNT:role/apply-role
  - environment: staging
    aws_region: ap-northeast-1
    iam_role_plan: arn:aws:iam::ACCOUNT:role/staging-plan-role
    iam_role_apply: arn:aws:iam::ACCOUNT:role/staging-apply-role
  - environment: production
    aws_region: ap-northeast-1
    iam_role_plan: arn:aws:iam::ACCOUNT:role/production-plan-role
    iam_role_apply: arn:aws:iam::ACCOUNT:role/production-apply-role

# ディレクトリ構造規約
directory_conventions:
  root: "{service}"
  stacks:
    - name: terragrunt
      directory: "terragrunt/{environment}"
    - name: kubernetes
      directory: "kubernetes/overlays/{environment}"

# サービス固有の設定
services:
  - name: excluded-service
    exclude_from_automation: true
    exclusion_config:
      reason: "手動デプロイが必要"
      type: "permanent"

# ブランチから環境へのマッピング
branch_patterns:
  develop: develop
  staging: staging
  production: production
```

## ディレクトリ構造サポート

ツールキットは柔軟なディレクトリ構造をサポートします：

### パターン1: サービス優先構造
```yaml
directory_conventions:
  root: "{service}"
  stacks:
    - name: terragrunt
      directory: "terragrunt/{environment}"
    - name: kubernetes
      directory: "kubernetes/overlays/{environment}"
```

結果:
- `my-service/terragrunt/develop/`
- `my-service/kubernetes/overlays/develop/`

### パターン2: スタック優先構造
```yaml
directory_conventions:
  root: ""
  stacks:
    - name: terragrunt
      directory: "terragrunt/{service}/{environment}"
    - name: kubernetes
      directory: "kubernetes/{service}/overlays/{environment}"
```

結果:
- `terragrunt/my-service/develop/`
- `kubernetes/my-service/overlays/develop/`

## ワークフロー統合

### 1. 変更検出ワークフロー
```yaml
name: Detect Changes and Create Labels
on:
  pull_request:
    types: [opened, synchronize, reopened]

jobs:
  detect-changes:
    runs-on: ubuntu-latest
    steps:
      - name: Dispatch Labels
        uses: panicboat/deploy-actions/label-dispatcher@main
        with:
          base-ref: ${{ github.event.pull_request.base.ref }}
          head-ref: ${{ github.head_ref }}
          repository: ${{ github.repository }}
          github-token: ${{ secrets.GITHUB_TOKEN }}
```

### 2. デプロイメント ワークフロー
```yaml
name: Deploy Infrastructure
on:
  pull_request:
    types: [labeled]

jobs:
  plan:
    runs-on: ubuntu-latest
    if: contains(github.event.label.name, 'deploy:')
    steps:
      - name: Resolve Deployment Targets
        id: resolve
        uses: panicboat/deploy-actions/label-resolver@main
        with:
          action-type: plan
          pr-number: ${{ github.event.pull_request.number }}
          repository: ${{ github.repository }}
          github-token: ${{ secrets.GITHUB_TOKEN }}

      - name: Deploy with Terragrunt
        uses: panicboat/deploy-actions/deploy-terragrunt@main
        with:
          deployment-targets: ${{ steps.resolve.outputs.deployment-targets }}
          action-type: plan
          github-token: ${{ secrets.GITHUB_TOKEN }}
```

## 環境変数

### 必須
- `GITHUB_TOKEN`: GitHub APIアクセストークン
- `GITHUB_REPOSITORY`: リポジトリ名（owner/repo形式）

### オプション
- `WORKFLOW_CONFIG_PATH`: 設定ファイルのパス（デフォルト: `workflow-config.yaml`）
- `SOURCE_REPO_PATH`: ソースリポジトリチェックアウトのパス
- `GITHUB_ACTIONS`: GitHub Actions出力フォーマットを有効化
- `GITHUB_REF_NAME`: 現在のブランチ名

## 開発

### 前提条件
- Ruby 3.4+
- Bundler
- Git

### セットアップ
```bash
# リポジトリをクローン
git clone https://github.com/panicboat/deploy-actions.git
cd deploy-actions

# 依存関係をインストール
bundle install

# テストを実行
bundle exec rspec
```

### 個別コンポーネントのテスト
```bash
# config managerをテスト
bundle exec ruby config-manager/bin/config-manager validate

# label dispatcherをテスト
bundle exec ruby label-dispatcher/bin/dispatcher detect

# deploy resolverをテスト
bundle exec ruby deploy-resolver/bin/resolver resolve PR_NUMBER
```

## セキュリティ機能

- **IAMロール統合**: セキュアなAWS認証情報管理
- **PRベースデプロイメント**: 有効なPRからのみデプロイメントをトリガー
- **ブランチ検証**: 環境固有のブランチ制限
- **設定検証**: 包括的な安全性チェック
- **監査証跡**: 全デプロイメント決定の詳細ログ

## エラー処理

ツールキットは包括的なエラー処理を提供します：

- **設定エラー**: 詳細な検証メッセージ
- **API失敗**: 指数バックオフ付きのリトライロジック
- **権限問題**: 明確なIAMロールガイダンス
- **ネットワーク問題**: 優雅な劣化

## 貢献

1. リポジトリをフォーク
2. 機能ブランチを作成
3. 変更を加える
4. 新機能のテストを追加
5. テストスイートを実行
6. プルリクエストを送信

## ライセンス

このプロジェクトはMITライセンスの下でライセンスされています - 詳細はLICENSEファイルを参照してください。

## サポート

問題や質問については：
- 詳細なコンポーネント情報は[ドキュメント](./action-scripts/)を確認
- GitHubでissueを開く
- リポジトリ内のサンプルワークフローを確認
