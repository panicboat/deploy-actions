# Config Manager

**English** | [🇯🇵 日本語](README-ja.md)

A Ruby-based configuration validation and management tool for GitHub Actions deployment automation.

## Overview

stack 定義の読み込みと検証、設定表示、サービスの実在ディレクトリ診断を提供します。設定仕様は [Configuration](../../README.md#configuration)、出力形式は [Matrix Output](../../README.md#matrix-output) を参照してください。

## Usage

The Config Manager provides a CLI interface through `bin/config-manager`:

### Commands

`action-scripts` を作業ディレクトリとして実行します。

| Command | Result |
|---|---|
| `bundle exec ruby config-manager/bin/config-manager validate` | 設定の検証結果と stack・環境数 |
| `bundle exec ruby config-manager/bin/config-manager show` | 各 stack ID の全パス、環境属性または共通属性、除外条件 |
| `bundle exec ruby config-manager/bin/config-manager environments` | 定義した環境名の和集合 |
| `bundle exec ruby config-manager/bin/config-manager test SERVICE_NAME [ENVIRONMENT]` | 実在する全一致対象と除外状態 |
| `bundle exec ruby config-manager/bin/config-manager diagnostics` | 設定、環境変数、Git 状態、設定ファイルの診断 |
| `bundle exec ruby config-manager/bin/config-manager template` | 新しい設定を作るための YAML の表示 |
| `bundle exec ruby config-manager/bin/config-manager check_file` | 既定ファイルの存在、読み取り、YAML 構文の確認 |

### Service Diagnosis

環境を省略すると、そのサービスの全定義環境と共通対象を調べます。環境を指定すると、指定環境と共通対象を調べます。サービスの登録は不要です。パスに一致しないサービスは空の結果になります。

一致する全ディレクトリを stack ID ごとに表示し、属性と任意 placeholder の抽出値を保持します。除外された対象も `excluded: true` として表示するため、実行対象から外れる条件を確認できます。

```bash
bundle exec ruby config-manager/bin/config-manager test demo
bundle exec ruby config-manager/bin/config-manager test demo production
```

未知の環境、設定の不正、ディレクトリ列挙の失敗、同じ対象の抽出値の矛盾はエラーとして表示します。

## Architecture

### Components

- **ConfigManagerController**: Main orchestration and CLI interface
- **ValidateConfig**: Comprehensive configuration validation
- **ConfigClient**: Configuration loading and parsing
- **ConsolePresenter**: Human-readable output formatting

### Validation Flow

YAML を読み込み、設定モデルで構造と整合性を検証し、検証結果と stack・環境数を表示します。検証規則の詳細は [Configuration](../../README.md#configuration) を参照してください。

## Error Handling

Detailed error reporting with:
- **Specific Error Messages**: Pinpoint configuration issues
- **Validation Context**: Clear indication of problematic sections
- **Suggestions**: Guidance for fixing common configuration problems
- **Summary Statistics**: Overview of configuration health

## Integration

The Config Manager integrates with:
- **Label Resolver**: Provides configuration for deployment targeting
- **Label Dispatcher**: Validates service and directory configurations
- **GitHub Actions**: Environment validation for CI/CD workflows

## Development

### Running Tests

```bash
cd action-scripts
bundle exec rspec spec/config-manager/
```

### Local Testing

```bash
# Test with custom configuration
cp workflow-config.yaml test-config.yaml
./bin/config-manager validate

# Test service configuration
./bin/config-manager test myservice develop
```
