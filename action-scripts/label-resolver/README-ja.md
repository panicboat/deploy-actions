# Label Resolver

[🇺🇸 English](README.md) | **日本語**

PR ラベルを明示的な環境指定を使って GitHub Actions 自動化のためのデプロイメントターゲットに変換する Ruby ベースのデプロイメント解決ツールです。

## 概要

Label Resolver は PR ラベルを分析し、指定された環境に対するデプロイメントターゲットを生成します。デプロイメントの安全性を検証し、マルチサービスデプロイメント用のデプロイメントマトリクスを作成し、デプロイメント自動化の意思決定の中心的なオーケストレーターとして機能します。

## 機能

- **ラベル解決**: PR 情報からデプロイメントラベルを抽出
- **明示的環境指定**: ブランチ依存なしの直接的な環境指定
- **ディレクトリ規約解決**: 階層ディレクトリ構造を使用したデプロイメントパスの解決
- **マトリクス生成**: 並列実行用のデプロイメントマトリクス作成
- **GitHub Actions 統合**: GitHub Actions ワークフローとのシームレスな統合

## 使用方法

Label Resolver は `bin/resolver` を通じて CLI インターフェースを提供します：

### 基本コマンド

```bash
# 特定の環境に対する PR ラベルからのデプロイメント解決
bundle exec ruby label-resolver/bin/resolver resolve PR番号 [環境一覧]

# デプロイメントワークフローのテスト
bundle exec ruby label-resolver/bin/resolver test PR番号 [環境一覧]

# GitHub Actions 環境のシミュレーション
bundle exec ruby label-resolver/bin/resolver simulate PR番号 [環境一覧]

# 環境設定の検証
bundle exec ruby label-resolver/bin/resolver validate_env

# ワークフローのステップバイステップデバッグ
bundle exec ruby label-resolver/bin/resolver debug PR番号 [環境一覧]
```

**環境指定：**
- 単一環境: `develop`
- 複数環境: `develop,staging` (カンマ区切り)
- 全環境: 環境一覧パラメータを省略

### 使用例

```bash
# develop 環境のデプロイメント解決
./bin/resolver resolve 123 develop

# 複数環境への同時テスト
./bin/resolver test 456 develop,staging

# production デプロイメントのデバッグ
./bin/resolver debug 789 production

# 利用可能な全環境へのデプロイ
./bin/resolver resolve 123
```

### ワークフロー統合

リゾルバーは通常 GitHub Actions ワークフローから呼び出されます：

```yaml
# 単一環境デプロイメント
- name: デプロイメントターゲットの解決
  uses: panicboat/deploy-actions/label-resolver@main
  with:
    pr_number: ${{ github.event.pull_request.number }}
    target_environments: ${{ inputs.target_environment }}

# 複数環境デプロイメント
- name: デプロイメントターゲットの解決
  uses: panicboat/deploy-actions/label-resolver@main
  with:
    pr_number: ${{ github.event.pull_request.number }}
    target_environments: "develop,staging"
```

### 環境変数

リゾルバーは GitHub Actions 用に以下の環境変数を設定します：

- `DEPLOYMENT_TARGETS`: デプロイメントターゲットの JSON 配列
- `DEPLOY_LABELS`: 見つかったデプロイラベルの JSON 配列
- `HAS_TARGETS`: デプロイメントターゲットが存在するかを示すブール値
- `SAFETY_STATUS`: 安全性検証の結果
- `MERGED_PR_NUMBER`: デプロイメント追跡用の PR 番号

### Action 出力

リゾルバーは以下の GitHub Actions 出力を提供します：

- `targets`: マトリクス戦略用のデプロイメントターゲットの JSON 配列
- `has-targets`: ターゲットが存在するかを示すブール値 (`true`/`false`)
- `safety-status`: 安全性検証の結果 (`passed`/`failed`)

## アーキテクチャ

### コンポーネント

- **LabelResolverController**: メインオーケストレーションロジック
- **DetermineTargetEnvironment**: 複数環境検証
- **GetLabels**: PR ラベル抽出
- **ValidateDeploymentSafety**: 安全性チェック（現在簡素化）
- **GenerateMatrix**: 複数環境用デプロイメントマトリクス生成

### フロー

1. **ラベル抽出**: PR からデプロイラベルを取得
2. **環境検証**: 全ての対象環境が存在することを検証
3. **安全性検証**: デプロイメント安全性チェックを実行
4. **マトリクス生成**: ディレクトリ構造に基づいて全環境のデプロイメントターゲットを作成
5. **出力生成**: 簡素化された出力で GitHub Actions 用に結果をフォーマット

## 設定

リゾルバーは設定に `workflow-config.yaml` を使用します：

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
  - root: "{service}"
    stacks:
      - name: terragrunt
        directory: "terragrunt/{environment}"
        targets: ["develop", "staging", "production"]
      - name: kubernetes
        directory: "kubernetes/overlays/{environment}"
        targets: ["develop", "staging", "production"]

services:
  - name: excluded-service
    exclude_from_automation: true
    exclusion_config:
      reason: "手動デプロイメントが必要"
      type: "permanent"
```

## デプロイラベル

システムは `deploy:service` 形式のラベルを認識します：

- `deploy:auth` - auth サービスをデプロイ
- `deploy:api` - api サービスをデプロイ
- `deploy:frontend` - frontend サービスをデプロイ
- `deploy:all` - 除外されていない全サービスをデプロイ

## 環境指定

**トランクベース開発**: リゾルバーはブランチベースマッピングではなく明示的な環境指定を使用：

- 環境はパラメータとして直接指定
- 環境決定にブランチ名への依存なし
- 設定で定義された任意のデプロイメント環境をサポート
- 複数環境への同時デプロイメントが可能

## ディレクトリ構造検出

リゾルバーはディレクトリの存在確認により利用可能なスタックを自動検出します：

```
{service}/
├── terragrunt/{environment}/     # Terragrunt スタック
└── kubernetes/overlays/{environment}/  # Kubernetes スタック
```

実際に存在するディレクトリのみがデプロイメントマトリクスに含まれます。

## エラーハンドリング

リゾルバーは包括的なエラーハンドリングを提供します：

- **無効な環境**: 対象環境が存在しない場合の明確なエラー
- **ラベル不足**: デプロイラベルのない PR の適切な処理
- **設定エラー**: ワークフロー設定の詳細な検証
- **ディレクトリ検出**: デプロイメントディレクトリ不足の警告

## 開発

### テスト実行

```bash
cd action-scripts
bundle exec rspec spec/label-resolver/
```

### ローカルテスト

```bash
# 環境設定
export GITHUB_TOKEN=your_token
export GITHUB_REPOSITORY=owner/repo

# 実際の PR でテスト
./bin/resolver debug 123 develop
```
