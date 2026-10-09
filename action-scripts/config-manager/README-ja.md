# Config Manager

[🇺🇸 English](README.md) | **日本語**

GitHub Actions デプロイメント自動化のための Ruby ベース設定検証・管理ツールです。

## Overview

設定表示、検証、環境一覧、サービス診断を担当します。[Commands](README.md#commands) に実行方法と結果、[Service Diagnosis](README.md#service-diagnosis) に診断の説明をまとめています。

設定仕様は [Configuration](../../README.md#configuration)、出力形式は [Matrix Output](../../README.md#matrix-output) を参照してください。

## Architecture

### Components

- **ConfigManagerController**: メインオーケストレーションと CLI インターフェース
- **ValidateConfig**: 包括的設定検証
- **ConfigClient**: 設定読み込みとパース
- **ConsolePresenter**: 人間が読める出力フォーマット

### Validation Flow

検証の流れは [Validation Flow](README.md#validation-flow) を参照してください。

## Error Handling

以下を含む詳細なエラーレポート：
- **具体的なエラーメッセージ**: 設定問題の特定
- **検証コンテキスト**: 問題のあるセクションの明確な指示
- **提案**: 一般的な設定問題の修正ガイダンス
- **サマリー統計**: 設定ヘルスの概要

## Integration

Config Manager は以下と統合されます：
- **Label Resolver**: デプロイメント指定のための設定提供
- **Label Dispatcher**: サービスとディレクトリ設定の検証
- **GitHub Actions**: CI/CD ワークフローの環境検証

## Development

### Running Tests

```bash
cd action-scripts
bundle exec rspec spec/config-manager/
```

### Local Testing

```bash
# カスタム設定でのテスト
cp workflow-config.yaml test-config.yaml
./bin/config-manager validate

# サービス設定のテスト
./bin/config-manager test myservice develop
```
