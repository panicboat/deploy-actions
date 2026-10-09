# Config Manager

[🇺🇸 English](README.md) | **日本語**

GitHub Actions デプロイメント自動化のための Ruby ベース設定検証・管理ツールです。

## 概要

stack 定義の読み込みと検証、設定表示、サービスの実在ディレクトリ診断を提供します。設定仕様は [設定](../../README-ja.md#設定)、出力形式は [matrix 出力](../../README-ja.md#matrix-出力) を参照してください。

## 使い方

Config Manager は `config-manager/bin/config-manager` を通じて CLI インターフェースを提供します。

### コマンド

`action-scripts` を作業ディレクトリとして実行します。

| コマンド | 結果 |
|---|---|
| `bundle exec ruby config-manager/bin/config-manager validate` | 設定の検証結果と stack・環境数 |
| `bundle exec ruby config-manager/bin/config-manager show` | 各 stack ID の全パス、環境属性または共通属性、除外条件 |
| `bundle exec ruby config-manager/bin/config-manager environments` | 定義した環境名の和集合 |
| `bundle exec ruby config-manager/bin/config-manager test SERVICE_NAME [ENVIRONMENT]` | 実在する全一致対象と除外状態 |
| `bundle exec ruby config-manager/bin/config-manager diagnostics` | 設定、環境変数、Git 状態、設定ファイルの診断 |
| `bundle exec ruby config-manager/bin/config-manager template` | 新しい設定を作るための YAML の表示 |
| `bundle exec ruby config-manager/bin/config-manager check_file` | 既定ファイルの存在、読み取り、YAML 構文の確認 |

### サービス診断

環境を省略すると、そのサービスの全定義環境と共通対象を調べます。環境を指定すると、指定環境と共通対象を調べます。サービスの登録は不要です。パスに一致しないサービスは空の結果になります。

一致する全ディレクトリを stack ID ごとに表示し、属性と任意 placeholder の抽出値を保持します。除外された対象も `excluded: true` として表示するため、実行対象から外れる条件を確認できます。

```bash
bundle exec ruby config-manager/bin/config-manager test demo
bundle exec ruby config-manager/bin/config-manager test demo production
```

未知の環境、設定の不正、ディレクトリ列挙の失敗、同じ対象の抽出値の矛盾はエラーとして表示します。

## アーキテクチャ

### 構成要素

- **ConfigManagerController**: メインオーケストレーションと CLI インターフェース
- **ValidateConfig**: 包括的設定検証
- **ConfigClient**: 設定読み込みとパース
- **ConsolePresenter**: 人間が読める出力フォーマット

### 検証の流れ

YAML を読み込み、設定モデルで構造と整合性を検証し、検証結果と stack・環境数を表示します。検証規則の詳細は [設定](../../README-ja.md#設定) を参照してください。

## エラー処理

以下を含む詳細なエラーレポート：

- **具体的なエラーメッセージ**: 設定問題の特定
- **検証コンテキスト**: 問題のあるセクションの明確な指示
- **提案**: 一般的な設定問題の修正ガイダンス
- **サマリー統計**: 設定ヘルスの概要

## 連携

Config Manager は以下と統合されます：

- **Label Resolver**: デプロイメント指定のための設定提供
- **Label Dispatcher**: サービスとディレクトリ設定の検証
- **GitHub Actions**: CI/CD ワークフローの環境検証

## 開発

### テストの実行

```bash
cd action-scripts
bundle exec rspec spec/config-manager/
```

### ローカルでの動作確認

```bash
cp workflow-config.yaml test-config.yaml
WORKFLOW_CONFIG_PATH=test-config.yaml bundle exec ruby config-manager/bin/config-manager validate
bundle exec ruby config-manager/bin/config-manager test myservice develop
```
