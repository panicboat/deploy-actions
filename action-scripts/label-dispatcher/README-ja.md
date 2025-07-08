# Label Dispatcher

GitHub Actions自動化のためのRubyベースのサービス変更検出・ラベル管理ツール

## 概要

Label Dispatcherはプルリクエストのファイル変更を分析し、影響を受けるサービスを検出し、デプロイラベルを自動的に管理します。コード変更に基づいてデプロイが必要なサービスを識別することで、デプロイ自動化のエントリーポイントとして機能します。

## 機能

- **変更検出**: Gitの差分を分析して変更されたファイルを識別
- **サービスマッピング**: ファイル変更をサービスデプロイにマッピング
- **ラベル管理**: PRのデプロイラベルを自動的に追加/削除
- **除外サポート**: 自動化から除外されたサービスの処理
- **GitHub統合**: シームレスなPRラベルとコメント管理
- **ディレクトリ規則**: 柔軟なサービスディレクトリ検出

## 使用方法

Label Dispatcherは`bin/dispatcher`を通じてCLIインターフェースを提供します：

### 基本コマンド

```bash
# PRのラベル配信（自動モード）
bundle exec ruby label-dispatcher/bin/dispatcher dispatch PR_NUMBER

# PRとのやり取りなしで変更検出をテスト
bundle exec ruby label-dispatcher/bin/dispatcher test

# 特定のgitリファレンスでテスト
bundle exec ruby label-dispatcher/bin/dispatcher test --base-ref=main --head-ref=feature/auth

# GitHub Actions環境のシミュレーション
bundle exec ruby label-dispatcher/bin/dispatcher simulate PR_NUMBER

# 環境設定の検証
bundle exec ruby label-dispatcher/bin/dispatcher validate_env

# 使用例の表示
bundle exec ruby label-dispatcher/bin/dispatcher help_usage
```

### ワークフロー統合

ディスパッチャーは通常GitHub Actionsワークフローから呼び出されます：

```yaml
- name: ラベル配信
  uses: panicboat/deploy-actions/label-dispatcher@main
  with:
    pr-number: ${{ github.event.pull_request.number }}
    repository: ${{ github.repository }}
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

## 核心ロジック

### 1. 変更検出

Git差分を分析して変更されたファイルを識別：
- ベースコミットとヘッドコミットを比較
- 追加、変更、削除されたファイルを識別
- デプロイに関連しない変更を除外
- APIベースとGitベースの両方の検出をサポート

### 2. サービスマッピング

ファイル変更をサービスデプロイにマッピング：
- ディレクトリ規則を使用してサービスを識別
- デフォルトとカスタムディレクトリパターンの両方をサポート
- 複数のデプロイスタック（Terragrunt、Kubernetes）を処理
- サービス固有の設定オーバーライドを適用

### 3. ラベル管理

PRラベルを自動的に管理：
- 変更されたサービスに`deploy:service-name`ラベルを追加
- 変更されなくなったサービスのラベルを削除
- PR更新全体でラベルの一貫性を維持
- バッチラベル操作をサポート

### 4. 除外処理

自動化から除外されたサービスを管理：
- 設定から除外されたサービスを識別
- 除外理由とタイプ情報を提供
- 除外詳細でPRコメントを更新
- 一時的と永続的な除外をサポート

## 設定

ディスパッチャーは設定に`workflow-config.yaml`を使用します：

```yaml
# サービス検出用のディレクトリ規則（階層構造）
directory_conventions:
  root: "{service}"
  stacks:
    - name: terragrunt
      directory: "terragrunt/{environment}"
    - name: kubernetes
      directory: "kubernetes/overlays/{environment}"

# サービス固有の設定
services:
  - name: my-service
    directory_conventions:
      terragrunt: "services/{service}/terragrunt/envs/{environment}"
      kubernetes: "services/{service}/kubernetes/overlays/{environment}"

  - name: excluded-service
    exclude_from_automation: true
    exclusion_config:
      reason: "特別な要件により手動デプロイが必要"
      type: "permanent"

  - name: legacy-service
    exclude_from_automation: true
    exclusion_config:
      reason: "移行進行中"
      type: "temporary"
```

## アーキテクチャ

Label Dispatcherはクリーンアーキテクチャパターンに従います：

### Controllers
- `LabelDispatcherController`: 配信プロセスの調整

### Use Cases
- `DetectChangedServices`: ファイル変更を分析してサービスにマッピング
- `ManageLabels`: PRラベル操作とコメントを処理

### Infrastructure
- `GitHubClient`: GitHub APIとのやり取り
- `FileSystemClient`: Git操作とファイル分析
- `ConfigClient`: 設定管理

## 出力フォーマット

ディスパッチャーはGitHub Actionsフォーマットで結果を出力します：

```bash
# 設定される環境変数
SERVICES_DETECTED='["service1","service2"]'
LABELS_ADDED='["deploy:service1","deploy:service2"]'
LABELS_REMOVED='["deploy:old-service"]'
HAS_CHANGES=true
```

## 環境変数

- `GITHUB_TOKEN`: GitHub APIアクセスに必要
- `GITHUB_REPOSITORY`: リポジトリ名（owner/repo形式）
- `GITHUB_ACTIONS`: GitHub Actions出力フォーマットを有効化
- `WORKFLOW_CONFIG_PATH`: 設定ファイルのパス

## サービス検出ロジック

ディスパッチャーは以下のロジックを使用してサービスを検出します：

1. **ファイル分析**: PRで変更されたファイルを調査
2. **パターンマッチング**: ファイルパスをディレクトリ規則と照合
3. **サービス抽出**: マッチしたパターンからサービス名を抽出
4. **設定検索**: サービス固有の設定を適用
5. **除外フィルタリング**: 除外されたサービスを結果から削除

### 検出例

`services/auth/terragrunt/envs/develop/main.tf`でのファイル変更の場合：
- パターンマッチ: `services/{service}/terragrunt/envs/{environment}`
- サービス抽出: `auth`
- `auth`サービスの設定を適用
- ラベル追加: `deploy:auth`

## エラーハンドリング

ディスパッチャーは包括的なエラーハンドリングを提供します：

- **API障害**: 指数バックオフで再試行
- **Git操作**: 不足しているリファレンスを適切に処理
- **設定問題**: 詳細なエラーメッセージを提供
- **権限エラー**: トークン権限の明確なガイダンス

## 開発

### 依存関係

- Ruby 3.4+
- Bundler
- Thor (CLIフレームワーク)
- Octokit (GitHub API)
- Git (システム依存関係)

### テスト

```bash
# 現在の作業ディレクトリでテスト
bundle exec ruby label-dispatcher/bin/dispatcher test

# 特定のリファレンスでテスト
bundle exec ruby label-dispatcher/bin/dispatcher test --base-ref=main --head-ref=HEAD

# 環境の検証
bundle exec ruby label-dispatcher/bin/dispatcher validate_env
```

## 統合ポイント

Label Dispatcherは以下と統合します：

1. **Config Manager**: 検証済み設定ファイルを使用
2. **Deploy Resolver**: デプロイ解決用のラベルを提供
3. **GitHub Actions**: PRイベントでトリガーされ更新
4. **Gitリポジトリ**: ファイル変更と履歴を分析

## ラベル規則

ディスパッチャーは標準化されたラベル形式を使用します：

- `deploy:service-name` - 特定サービスのデプロイ
- `deploy:all` - 全サービスのデプロイ（特殊ケース）
- ラベルは自動的に管理・同期される

## コメント管理

ディスパッチャーは以下の内容でPRコメントを更新します：

- **検出されたサービス**: デプロイされるサービスの一覧
- **除外されたサービス**: 理由付きで自動化から除外されたサービス
- **ファイル変更**: 関連するファイル変更の要約
- **設定状態**: 検証と処理の状態

## 安全性機能

- **変更検証**: 関連する変更のみがデプロイをトリガーすることを確保
- **設定検証**: 処理前の設定検証
- **権限チェック**: GitHubトークンの権限を確認
- **除外の尊重**: サービス除外設定を遵守
- **監査証跡**: トラブルシューティング用のすべてのラベル操作をログ記録
