# Config Manager

GitHub Actions デプロイ自動化のためのRubyベースの設定検証・管理ツール

## 概要

Config Managerは、デプロイ環境、サービス、自動化ルールを定義するワークフロー設定ファイルを検証・管理します。包括的な設定検証、診断ツール、デプロイ自動化設定のテンプレートを提供します。

## 機能

- **設定検証**: 詳細なエラーレポート付きの`workflow-config.yaml`ファイル検証
- **環境管理**: AWS IAMロールと連携した設定済み環境の一覧表示・テスト
- **サービス設定**: サービス固有のデプロイ設定と除外設定の管理
- **ディレクトリ規約**: 階層ディレクトリ構造設定の検証
- **テンプレート生成**: 例付きの設定テンプレート生成
- **診断ツール**: デプロイ設定の包括的なヘルスチェック

## 使用方法

Config Managerは`bin/config-manager`を通じてCLIインターフェースを提供します：

### 基本コマンド

```bash
# 設定ファイルの検証
bundle exec ruby config-manager/bin/config-manager validate

# 解析済み設定の表示
bundle exec ruby config-manager/bin/config-manager show

# 全環境の一覧表示
bundle exec ruby config-manager/bin/config-manager environments

# 全サービスの一覧表示
bundle exec ruby config-manager/bin/config-manager services

# 特定サービス設定のテスト
bundle exec ruby config-manager/bin/config-manager test SERVICE_NAME ENVIRONMENT

# 診断チェックの実行
bundle exec ruby config-manager/bin/config-manager diagnostics

# 設定テンプレートの生成
bundle exec ruby config-manager/bin/config-manager template
```

### 設定ファイル

ツールは作業ディレクトリに以下の構造の`workflow-config.yaml`ファイルを想定しています：

```yaml
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

directory_conventions:
  root: "{service}"
  stacks:
    - name: terragrunt
      directory: "terragrunt/{environment}"
    - name: kubernetes
      directory: "kubernetes/overlays/{environment}"

services:
  - name: my-service
    directory_conventions:
      terragrunt: "services/{service}/terragrunt/envs/{environment}"
      kubernetes: "services/{service}/kubernetes/overlays/{environment}"

  - name: excluded-service
    exclude_from_automation: true
    exclusion_config:
      reason: "手動デプロイが必要"
      type: "permanent"

branch_patterns:
  develop: develop
  staging: staging
  production: production
```

## アーキテクチャ

Config Managerはクリーンアーキテクチャパターンに従います：

- **Controllers**: CLIコマンドの処理とユースケースの調整
- **Use Cases**: 設定検証のビジネスロジック実装
- **Infrastructure**: ファイルシステムと設定読み込み
- **Presenters**: コンソールとGitHub Actions向けの出力フォーマット

## 統合

このツールは複合GitHub Actionsから使用されるように設計されています。典型的なワークフロー：

1. **Checkout**: Actionがdeploy-actionsリポジトリをチェックアウト
2. **設定コピー**: ソースリポジトリの設定ファイルを`workflow-config.yaml`にコピー
3. **検証**: Config Managerが設定を検証
4. **処理**: 他のツールが検証済み設定を使用

## 環境変数

- `WORKFLOW_CONFIG_PATH`: 設定ファイルのパス (デフォルト: `workflow-config.yaml`)
- `GITHUB_ACTIONS`: GitHub Actions出力フォーマットを有効化
- `GITHUB_TOKEN`: GitHub API操作に必要
- `GITHUB_REPOSITORY`: GitHub操作用のリポジトリ名

## エラーハンドリング

ツールは詳細なエラーメッセージと適切な終了コードを提供します：

- **終了コード 0**: 成功
- **終了コード 1**: 設定検証失敗またはファイルが見つからない
- **終了コード 2**: 環境/依存関係の問題

## 開発

### 依存関係

- Ruby 3.4+
- Bundler
- Thor (CLIフレームワーク)
- YAML (設定解析)

### テスト

```bash
# 設定ファイルの存在確認
bundle exec ruby config-manager/bin/config-manager check_file

# 特定環境でのテスト
bundle exec ruby config-manager/bin/config-manager test my-service develop

# 完全な診断実行
bundle exec ruby config-manager/bin/config-manager diagnostics
```

## 出力フォーマット

ツールは2つの出力フォーマットをサポートします：

- **Console**: カラーと絵文字付きの人間可読フォーマット
- **GitHub Actions**: `::error::`と`::warning::`アノテーション付きの構造化フォーマット

フォーマットは`GITHUB_ACTIONS`環境変数に基づいて自動選択されます。
