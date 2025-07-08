# Deploy Resolver

PRラベルとブランチ情報をデプロイターゲットに変換するRubyベースのデプロイ解決ツール

## 概要

Deploy ResolverはPRラベルとブランチコンテキストを分析してデプロイターゲットを決定し、デプロイ安全性を検証し、マルチサービスデプロイ用のデプロイマトリックスを生成します。デプロイ自動化の意思決定を行う中央オーケストレーターとして機能します。

## 機能

- **ラベル解決**: PR情報からデプロイラベルを抽出
- **環境検出**: ブランチパターンからターゲット環境を決定
- **ディレクトリ規約解決**: 階層ディレクトリ構造を使用したデプロイパスの解決
- **マトリックス生成**: 並列実行用のデプロイマトリックス作成
- **ブランチベースターゲティング**: ブランチをデプロイ環境にマッピング
- **GitHub Actions統合**: GitHub Actionsワークフローとのシームレスな統合

## 使用方法

Deploy Resolverは`bin/resolver`を通じてCLIインターフェースを提供します：

### 基本コマンド

```bash
# PRラベルからデプロイを解決
bundle exec ruby deploy-resolver/bin/resolver resolve PR_NUMBER

# デプロイワークフローのテスト
bundle exec ruby deploy-resolver/bin/resolver test BRANCH_NAME

# GitHub Actions環境のシミュレーション
bundle exec ruby deploy-resolver/bin/resolver simulate BRANCH_NAME

# 環境設定の検証
bundle exec ruby deploy-resolver/bin/resolver validate_env

# ステップバイステップのデバッグ
bundle exec ruby deploy-resolver/bin/resolver debug BRANCH_NAME
```

### ワークフロー統合

リゾルバーは通常GitHub Actionsワークフローから呼び出されます：

```yaml
- name: デプロイターゲットの解決
  uses: panicboat/deploy-actions/label-resolver@main
  with:
    action-type: plan  # または apply
    pr-number: ${{ github.event.pull_request.number }}
    repository: ${{ github.repository }}
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

## 核心ロジック

### 1. ラベル抽出

デプロイパターンにマッチするPRラベルを取得：
- `deploy:service-name` - 特定サービスのデプロイ
- `deploy:all` - 全サービスのデプロイ
- ラベルは設定済みサービスに対して検証される

### 2. 環境解決

現在のブランチに基づいてターゲット環境を決定：
- `develop` → `develop`環境
- `staging` → `staging`環境
- `production` → `production`環境

### 3. 安全性検証

デプロイ安全性ルールを適用：
- デプロイにマージ済みPRを要求
- PR情報の可用性を検証
- 安全性設定に対してチェック
- 直接プッシュデプロイを防止（設定可能）

### 4. マトリックス生成

並列実行用のデプロイマトリックスを作成：
- サービスをデプロイスタック別にグループ化（Terragrunt、Kubernetes）
- 環境固有のIAMロールを含む
- ディレクトリパス規則を提供
- サービス固有の設定を処理

## 設定

リゾルバーは設定に`workflow-config.yaml`を使用します：

```yaml
# ブランチから環境へのマッピング
branch_patterns:
  develop: develop
  staging: staging
  production: production

# 安全性チェック
safety_checks:
  require_merged_pr: true
  fail_on_missing_pr: true
  max_retry_attempts: 3
  allowed_direct_push_branches: []

# 環境設定
environments:
  - environment: develop
    aws_region: ap-northeast-1
    iam_role_plan: arn:aws:iam::ACCOUNT:role/plan-role
    iam_role_apply: arn:aws:iam::ACCOUNT:role/apply-role

# サービス設定
services:
  - name: my-service
    directory_conventions:
      terragrunt: "services/{service}/terragrunt/envs/{environment}"
      kubernetes: "services/{service}/kubernetes/overlays/{environment}"
```

## アーキテクチャ

Deploy Resolverはクリーンアーキテクチャパターンに従います：

### Controllers
- `DeployResolverController`: 解決プロセスの調整

### Use Cases
- `DetermineTargetEnvironment`: ブランチを環境にマッピング
- `GetLabels`: PRからデプロイラベルを抽出
- `ValidateDeploymentSafety`: 安全性ルールの適用
- `GenerateMatrix`: デプロイマトリックスの作成

### Infrastructure
- `GitHubClient`: GitHub APIとのやり取り
- `ConfigClient`: 設定ファイル管理

## 出力フォーマット

リゾルバーはGitHub Actionsフォーマットでデプロイ情報を出力します：

```bash
# 設定される環境変数
DEPLOYMENT_TARGETS='[{"service":"my-service","environment":"develop","stack":"terragrunt"}]'
HAS_TARGETS=true
TARGET_ENVIRONMENT=develop
SAFETY_STATUS=passed
```

## 環境変数

- `GITHUB_TOKEN`: GitHub APIアクセスに必要
- `GITHUB_REPOSITORY`: リポジトリ名（owner/repo形式）
- `GITHUB_REF_NAME`: 現在のブランチ名
- `WORKFLOW_CONFIG_PATH`: 設定ファイルのパス
- `SOURCE_REPO_PATH`: ソースリポジトリチェックアウトのパス

## エラーハンドリング

リゾルバーは詳細なエラーハンドリングを提供します：

- **PR未検出**: `safety_status=no_merged_pr`を返す
- **無効な設定**: エラーと詳細メッセージで終了
- **API障害**: 指数バックオフで再試行
- **ラベル不足**: 空のターゲット配列を返す

## 開発

### 依存関係

- Ruby 3.4+
- Bundler
- Thor (CLIフレームワーク)
- Octokit (GitHub API)

### テスト

```bash
# 特定ブランチでのテスト
bundle exec ruby deploy-resolver/bin/resolver test develop

# ステップバイステップのデバッグ
bundle exec ruby deploy-resolver/bin/resolver debug develop

# 環境設定の検証
bundle exec ruby deploy-resolver/bin/resolver validate_env
```

## 統合ポイント

Deploy Resolverは以下と統合します：

1. **Label Dispatcher**: ラベル検出で作成されたラベルを使用
2. **Deploy Terragrunt**: Terragruntデプロイ用のターゲットを提供
3. **Deploy GitOps**: Kubernetesデプロイ用のターゲットを提供
4. **Config Manager**: 検証済み設定ファイルを使用

## 安全性機能

- **PR要件**: 有効なPRなしのデプロイをブロック
- **ブランチ検証**: 承認済みブランチからのデプロイのみ確保
- **設定検証**: 処理前の設定検証
- **再試行ロジック**: 一時的なGitHub API障害の処理
- **監査証跡**: トラブルシューティング用のすべてのデプロイ決定をログ記録
