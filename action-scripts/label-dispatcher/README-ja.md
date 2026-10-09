# Label Dispatcher

[🇺🇸 English](README.md) | **日本語**

GitHub Actions デプロイメント自動化のための Ruby ベースのサービス変更検出・ラベル管理ツール

## 概要

Label Dispatcherはプルリクエストのファイル変更を分析し、影響を受けるサービスを検出し、デプロイラベルを自動的に管理します。コード変更に基づいてデプロイが必要なサービスを識別することで、デプロイ自動化のエントリーポイントとして機能します。

## 機能

- **変更検出**: Gitの差分を分析して変更されたファイルを識別
- **サービスマッピング**: ファイル変更をサービスデプロイにマッピング
- **ラベル管理**: PRのデプロイラベルを自動的に追加/削除
- **除外条件**: stack ごとの照合条件で除外
- **GitHub統合**: シームレスなPRラベル管理
- **ディレクトリ規則**: 柔軟なサービスディレクトリ検出
- **デプロイメント戦略非依存**: 任意のブランチ戦略や開発ワークフローに対応

## 使い方

`action-scripts` を作業ディレクトリとして実行します。

Label Dispatcherは`label-dispatcher/bin/dispatcher`を通じてCLIインターフェースを提供します：

### コマンド

PR の変更に基づいてラベルを更新します。

```bash
bundle exec ruby label-dispatcher/bin/dispatcher dispatch PR_NUMBER
```

PR を操作せずに変更検出を確認します。

```bash
bundle exec ruby label-dispatcher/bin/dispatcher test
```

比較する Git リファレンスを指定します。

```bash
bundle exec ruby label-dispatcher/bin/dispatcher test --base-ref=main --head-ref=feature/auth
```

GitHub Actions の実行環境をシミュレートします。

```bash
bundle exec ruby label-dispatcher/bin/dispatcher simulate PR_NUMBER
```

実行環境の設定を検証します。

```bash
bundle exec ruby label-dispatcher/bin/dispatcher validate_env
```

使用例と実行方法を表示します。

```bash
bundle exec ruby label-dispatcher/bin/dispatcher help_usage
```

### ワークフローへの組み込み

ディスパッチャーは通常GitHub Actionsワークフローから呼び出されます：

```yaml
- name: Dispatch labels
  uses: panicboat/deploy-actions/label-dispatcher@v1
  with:
    pr-number: ${{ github.event.pull_request.number }}
    repository: ${{ github.repository }}
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

### 環境変数

ディスパッチャーは GitHub Actions 用に以下の環境変数を設定します：

- `SERVICES_DETECTED`: 検出されたサービスの JSON 配列
- `LABELS_ADDED`: 追加されたラベルの JSON 配列
- `LABELS_REMOVED`: 削除されたラベルの JSON 配列
- `HAS_CHANGES`: 変更が検出されたかを示すブール値

## 変更パスの照合

変更ファイルを定義された stack のパスに照合し、サービス・環境・任意 placeholder を抽出します。`environments` を持つ stack は定義環境だけを受け付け、パスに環境名がない場合は定義環境ごとに評価します。両方の属性マップがない stack は変更パスから抽出した環境名を使います。`attributes` を持つ stack は `environment: null` の照合として扱います。

各照合に除外条件を適用し、除外されない照合が一つでもあるサービスを一度だけラベル対象にします。サービス全体のディレクトリを検出対象にする場合は、そのパスも stack に定義します。削除されたファイルも照合するため、ディレクトリの存在は要求しません。

## 設定

設定仕様はルートの [設定](../../README-ja.md#設定) を参照してください。

## アーキテクチャ

Label Dispatcherはクリーンアーキテクチャパターンに従います：

### コントローラー

- `LabelDispatcherController`: 配信プロセスの調整

### ユースケース

- `DetectChangedServices`: ファイル変更を分析してサービスにマッピング
- `ManageLabels`: PRラベル操作を処理

### インフラストラクチャ

- `GitHubClient`: GitHub APIとのやり取り
- `FileSystemClient`: Git操作とファイル分析
- `ConfigClient`: 設定管理

## 実行環境の設定

- `GITHUB_TOKEN`: GitHub API アクセスに必要
- `GITHUB_REPOSITORY`: リポジトリ名（owner/repo 形式）
- `GITHUB_ACTIONS`: GitHub Actions 出力フォーマットを有効化
- `WORKFLOW_CONFIG_PATH`: 設定ファイルのパス（オプション、デフォルトは workflow-config.yaml）

## 検出結果

検出結果にはラベル、変更ファイル、対象サービスを含みます。GitHub Actions では `deploy-labels`、`labels-added`、`labels-removed`、`services-detected`、`has-changes` を出力します。除外状態の確認には [サービス診断](../config-manager/README-ja.md#サービス診断) を使います。

## エラー処理

ディスパッチャーは包括的なエラーハンドリングを提供します：

- **API障害**: 指数バックオフで再試行
- **Git操作**: 不足しているリファレンスを適切に処理
- **設定問題**: 詳細なエラーメッセージを提供
- **権限エラー**: トークン権限の明確なガイダンス

## 開発

### 依存関係

- Ruby ([.ruby-version](../.ruby-version))
- Bundler
- Thor (CLIフレームワーク)
- Octokit (GitHub API)
- Git (システム依存関係)

### 動作確認

現在の作業ディレクトリで変更検出を確認します。

```bash
bundle exec ruby label-dispatcher/bin/dispatcher test
```

比較する Git リファレンスを指定して変更検出を確認します。

```bash
bundle exec ruby label-dispatcher/bin/dispatcher test --base-ref=main --head-ref=HEAD
```

実行環境を検証します。

```bash
bundle exec ruby label-dispatcher/bin/dispatcher validate_env
```

## 連携先

Label Dispatcherは以下と統合します：

1. **Config Manager**: 検証済み設定ファイルを使用
2. **Label Resolver**: デプロイ解決用のラベルを提供
3. **GitHub Actions**: PRイベントでトリガーされ更新
4. **Gitリポジトリ**: ファイル変更と履歴を分析

## ラベルの規約

ディスパッチャーは標準化されたラベル形式を使用します：

- `deploy:service-name` - 特定サービスのデプロイ
- `deploy:all` - 全サービスのデプロイ（特殊ケース）
- ラベルは自動的に管理・同期される

## 安全性に関する機能

- **変更検証**: 関連する変更のみがデプロイをトリガーすることを確保
- **設定検証**: 処理前の設定検証
- **権限チェック**: GitHubトークンの権限を確認
- **除外条件の適用**: 各照合の除外条件を適用
- **監査証跡**: トラブルシューティング用のすべてのラベル操作をログ記録
