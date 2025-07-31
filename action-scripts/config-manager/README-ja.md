# Config Manager

[🇺🇸 English](README.md) | **日本語**

GitHub Actions デプロイメント自動化のための Ruby ベース設定検証・管理ツールです。

## 概要

Config Manager は、デプロイメント環境、サービス、自動化ルールを定義するワークフロー設定ファイルを検証・管理します。トランクベース開発に最適化されたデプロイメント自動化セットアップのための包括的な設定検証、診断ツール、テンプレートを提供します。

## 機能

- **設定検証**: 詳細なエラーレポートを伴う `workflow-config.yaml` ファイルの検証
- **環境管理**: AWS IAM ロールを使用した設定済み環境の一覧表示とテスト
- **サービス設定**: サービス固有のデプロイメント設定と除外の管理
- **ディレクトリ規約**: 階層ディレクトリ構造設定の検証
- **テンプレート生成**: 最適化された設定テンプレートの生成
- **診断ツール**: デプロイメントセットアップの包括的ヘルスチェック

## 使用方法

Config Manager は `bin/config-manager` を通じて CLI インターフェースを提供します：

### 基本コマンド

```bash
# 設定ファイルの検証
bundle exec ruby config-manager/bin/config-manager validate

# パース済み設定の表示
bundle exec ruby config-manager/bin/config-manager show

# 全環境の一覧
bundle exec ruby config-manager/bin/config-manager environments

# 全サービスの一覧
bundle exec ruby config-manager/bin/config-manager services

# 自動化から除外されたサービスの一覧
bundle exec ruby config-manager/bin/config-manager excluded_services

# 特定のサービス設定のテスト
bundle exec ruby config-manager/bin/config-manager test サービス名 環境名

# 診断チェックの実行
bundle exec ruby config-manager/bin/config-manager diagnostics

# 設定テンプレートの生成
bundle exec ruby config-manager/bin/config-manager template
```

### 使用例

```bash
# 現在の設定の検証
./bin/config-manager validate

# develop 環境での auth サービスのテスト
./bin/config-manager test auth develop

# 全設定詳細の表示
./bin/config-manager show

# 新しい設定テンプレートの生成
./bin/config-manager template > new-workflow-config.yaml
```

## 設定構造

Config Manager は以下の構造の `workflow-config.yaml` ファイルを管理します：

### 環境

ブランチ依存なしのデプロイメント環境を定義：

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
```

### ディレクトリ規約

サービス発見のための階層ディレクトリ構造：

```yaml
directory_conventions:
  - root: "{service}"
    stacks:
      - name: terragrunt
        directory: "terragrunt/{environment}"
        targets: ["develop", "staging", "production"]
      - name: kubernetes
        directory: "kubernetes/overlays/{environment}"
        targets: ["develop", "staging", "production"]
```

### サービス

サービス固有の設定と除外：

```yaml
services:
  - name: excluded-service
    exclude_from_automation: true
    exclusion_config:
      reason: "特別な要件により手動デプロイメントが必要"
      type: "permanent"

  - name: special-service
    directory_conventions:
      terragrunt: "custom/{service}/infra/{environment}"
```

## 検証ルール

Config Manager は包括的な検証を実施します：

### 環境検証
- 全環境に `environment`、`aws_region`、`iam_role_plan`、`iam_role_apply` が必要
- AWS リージョンは標準形式に従う必要（`us-west-2`、`ap-northeast-1` など）
- IAM ロール ARN は有効な AWS ARN 形式である必要
- 必須環境：`develop`、`staging`、`production`

### ディレクトリ規約検証
- ルートパターンには `{service}` プレースホルダーが必要（空の場合を除く）
- スタックディレクトリには `{environment}` プレースホルダーが必要
- 必須スタック：`terragrunt`（最低限）
- ディレクトリ規約は配列である必要

### サービス検証
- サービス名はドット（`.`）で始まることはできない
- サービス固有のディレクトリ規約には `{service}` プレースホルダーが必要
- 除外されたサービスには理由付きの `exclusion_config` が必要

## テンプレート生成

最適化された設定テンプレートを生成：

```bash
./bin/config-manager template
```

生成されるテンプレートには以下が含まれます：
- ブランチフィールドのない環境設定
- モダンなディレクトリ規約
- サービス除外の例
- 包括的なドキュメント

## 診断ツール

デプロイメント自動化の包括的ヘルスチェック：

```bash
./bin/config-manager diagnostics
```

チェック項目：
- 設定ファイル検証
- 環境変数の可用性
- Git リポジトリ状態
- 設定ファイルの場所
- ディレクトリ構造の整合性

## アーキテクチャ

### コンポーネント

- **ConfigManagerController**: メインオーケストレーションと CLI インターフェース
- **ValidateConfig**: 包括的設定検証
- **ConfigClient**: 設定読み込みとパース
- **ConsolePresenter**: 人間が読める出力フォーマット

### 検証フロー

1. **構造検証**: YAML 構造と必須セクション
2. **環境検証**: AWS 認証情報とリージョン検証
3. **サービス検証**: サービス設定と除外
4. **ディレクトリ検証**: ディレクトリ規約とプレースホルダー
5. **サマリー生成**: 検証結果と統計

## エラーハンドリング

以下を含む詳細なエラーレポート：
- **具体的なエラーメッセージ**: 設定問題の特定
- **検証コンテキスト**: 問題のあるセクションの明確な指示
- **提案**: 一般的な設定問題の修正ガイダンス
- **サマリー統計**: 設定ヘルスの概要

## 統合

Config Manager は以下と統合されます：
- **Label Resolver**: デプロイメント指定のための設定提供
- **Label Dispatcher**: サービスとディレクトリ設定の検証
- **GitHub Actions**: CI/CD ワークフローの環境検証

## 開発

### テスト実行

```bash
cd action-scripts
bundle exec rspec spec/config-manager/
```

### ローカルテスト

```bash
# カスタム設定でのテスト
cp workflow-config.yaml test-config.yaml
./bin/config-manager validate

# サービス設定のテスト
./bin/config-manager test myservice develop
```
