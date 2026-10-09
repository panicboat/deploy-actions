# Label Dispatcher

[🇺🇸 English](README.md) | **日本語**

GitHub Actions デプロイメント自動化のための Ruby ベースのサービス変更検出・ラベル管理ツール

## Overview

Label Dispatcherはプルリクエストのファイル変更を分析し、影響を受けるサービスを検出し、デプロイラベルを自動的に管理します。コード変更に基づいてデプロイが必要なサービスを識別することで、デプロイ自動化のエントリーポイントとして機能します。

## Features

- **変更検出**: Gitの差分を分析して変更されたファイルを識別
- **サービスマッピング**: ファイル変更をサービスデプロイにマッピング
- **ラベル管理**: PRのデプロイラベルを自動的に追加/削除
- **Exclusion Support**: stack ごとの照合条件で除外
- **GitHub統合**: シームレスなPRラベル管理
- **ディレクトリ規則**: 柔軟なサービスディレクトリ検出
- **デプロイメント戦略非依存**: 任意のブランチ戦略や開発ワークフローに対応

## Usage

Label Dispatcherは`bin/dispatcher`を通じてCLIインターフェースを提供します：

### Commands

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

# 使用例とヒントの表示
bundle exec ruby label-dispatcher/bin/dispatcher help_usage
```

### Workflow Integration

ディスパッチャーは通常GitHub Actionsワークフローから呼び出されます：

```yaml
- name: ラベル配信
  uses: panicboat/deploy-actions/label-dispatcher@v1
  with:
    pr-number: ${{ github.event.pull_request.number }}
    repository: ${{ github.repository }}
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

### Environment Variables

ディスパッチャーは GitHub Actions 用に以下の環境変数を設定します：

- `SERVICES_DETECTED`: 検出されたサービスの JSON 配列
- `LABELS_ADDED`: 追加されたラベルの JSON 配列
- `LABELS_REMOVED`: 削除されたラベルの JSON 配列
- `HAS_CHANGES`: 変更が検出されたかを示すブール値

## Change Matching

変更パスの照合とラベル生成の条件は [Change Matching](README.md#change-matching) を参照してください。

## Configuration

設定仕様はルートの [Configuration](../../README.md#configuration) を参照してください。

## Architecture

Label Dispatcherはクリーンアーキテクチャパターンに従います：

### Controllers
- `LabelDispatcherController`: 配信プロセスの調整

### Use Cases
- `DetectChangedServices`: ファイル変更を分析してサービスにマッピング
- `ManageLabels`: PRラベル操作を処理

### Infrastructure
- `GitHubClient`: GitHub APIとのやり取り
- `FileSystemClient`: Git操作とファイル分析
- `ConfigClient`: 設定管理

## Required Environment Variables

- `GITHUB_TOKEN`: GitHub API アクセスに必要
- `GITHUB_REPOSITORY`: リポジトリ名（owner/repo 形式）
- `GITHUB_ACTIONS`: GitHub Actions 出力フォーマットを有効化
- `WORKFLOW_CONFIG_PATH`: 設定ファイルのパス（オプション、デフォルトは workflow-config.yaml）

## Detection Results

検出結果と GitHub Actions の出力は [Detection Results](README.md#detection-results) を参照してください。

## Error Handling

ディスパッチャーは包括的なエラーハンドリングを提供します：

- **API障害**: 指数バックオフで再試行
- **Git操作**: 不足しているリファレンスを適切に処理
- **設定問題**: 詳細なエラーメッセージを提供
- **権限エラー**: トークン権限の明確なガイダンス

## Development

### Dependencies

- Ruby 3.4+
- Bundler
- Thor (CLIフレームワーク)
- Octokit (GitHub API)
- Git (システム依存関係)

### Testing

```bash
# 現在の作業ディレクトリでテスト
bundle exec ruby label-dispatcher/bin/dispatcher test

# 特定のリファレンスでテスト
bundle exec ruby label-dispatcher/bin/dispatcher test --base-ref=main --head-ref=HEAD

# 環境の検証
bundle exec ruby label-dispatcher/bin/dispatcher validate_env
```

## Integration Points

Label Dispatcherは以下と統合します：

1. **Config Manager**: 検証済み設定ファイルを使用
2. **Label Resolver**: デプロイ解決用のラベルを提供
3. **GitHub Actions**: PRイベントでトリガーされ更新
4. **Gitリポジトリ**: ファイル変更と履歴を分析

## Label Conventions

ディスパッチャーは標準化されたラベル形式を使用します：

- `deploy:service-name` - 特定サービスのデプロイ
- `deploy:all` - 全サービスのデプロイ（特殊ケース）
- ラベルは自動的に管理・同期される

## Safety Features

- **変更検証**: 関連する変更のみがデプロイをトリガーすることを確保
- **設定検証**: 処理前の設定検証
- **権限チェック**: GitHubトークンの権限を確認
- **Exclusion Respect**: 各照合の除外条件を適用
- **監査証跡**: トラブルシューティング用のすべてのラベル操作をログ記録
