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

## 使い方

`action-scripts` を作業ディレクトリとして実行します。

Label Resolver は `label-resolver/bin/resolver` を通じて CLI インターフェースを提供します：

### コマンド

指定環境に対するデプロイ対象を PR ラベルから解決します。

```bash
bundle exec ruby label-resolver/bin/resolver resolve PR_NUMBER [ENVIRONMENTS]
```

デプロイ対象の解決結果を確認します。

```bash
bundle exec ruby label-resolver/bin/resolver test PR_NUMBER [ENVIRONMENTS]
```

GitHub Actions の実行環境をシミュレートします。

```bash
bundle exec ruby label-resolver/bin/resolver simulate PR_NUMBER [ENVIRONMENTS]
```

実行環境の設定を検証します。

```bash
bundle exec ruby label-resolver/bin/resolver validate_env
```

処理を段階ごとにデバッグします。

```bash
bundle exec ruby label-resolver/bin/resolver debug PR_NUMBER [ENVIRONMENTS]
```

**環境指定：**

- 単一環境: `develop`
- 複数環境: `develop,staging` (カンマ区切り)
- 全環境: 環境一覧パラメータを省略

### 実行例

`develop` 環境のデプロイ対象を解決します。

```bash
bundle exec ruby label-resolver/bin/resolver resolve 123 develop
```

複数環境のデプロイ対象をまとめて確認します。

```bash
bundle exec ruby label-resolver/bin/resolver test 456 develop,staging
```

`production` 環境のデプロイ対象の解決をデバッグします。

```bash
bundle exec ruby label-resolver/bin/resolver debug 789 production
```

定義された全環境のデプロイ対象を解決します。

```bash
bundle exec ruby label-resolver/bin/resolver resolve 123
```

### ワークフローへの組み込み

リゾルバーは通常 GitHub Actions ワークフローから呼び出されます：

単一環境を指定する場合：

```yaml
- name: Resolve deployment targets
  uses: panicboat/deploy-actions/label-resolver@v1
  with:
    pr-number: ${{ github.event.pull_request.number }}
    repository: ${{ github.repository }}
    github-token: ${{ secrets.GITHUB_TOKEN }}
    environments: ${{ inputs.target_environment }}
```

複数環境を指定する場合：

```yaml
- name: Resolve deployment targets
  uses: panicboat/deploy-actions/label-resolver@v1
  with:
    pr-number: ${{ github.event.pull_request.number }}
    repository: ${{ github.repository }}
    github-token: ${{ secrets.GITHUB_TOKEN }}
    environments: "develop,staging"
```

### 環境変数

リゾルバーは GitHub Actions 用に以下の環境変数を設定します：

- `DEPLOYMENT_TARGETS`: デプロイメントターゲットの JSON 配列
- `DEPLOY_LABELS`: 見つかったデプロイラベルの JSON 配列
- `HAS_TARGETS`: デプロイメントターゲットが存在するかを示すブール値
- `SAFETY_STATUS`: 安全性検証の結果
- `MERGED_PR_NUMBER`: デプロイメント追跡用の PR 番号

### Action の出力

リゾルバーは以下の GitHub Actions 出力を提供します：

- `targets`: マトリクス戦略用のデプロイメントターゲットの JSON 配列
- `has-targets`: ターゲットが存在するかを示すブール値 (`true`/`false`)
- `safety-status`: 安全性検証の結果 (`passed`/`failed`)

## アーキテクチャ

### 構成要素

- **LabelResolverController**: メインオーケストレーションロジック
- **DetermineTargetEnvironment**: 複数環境検証
- **GetLabels**: PR ラベル抽出
- **ValidateDeploymentSafety**: 安全性チェック（現在簡素化）
- **GenerateMatrix**: 複数環境用デプロイメントマトリクス生成

### 処理の流れ

1. **ラベル抽出**: PR からデプロイラベルを取得
2. **環境検証**: 全ての対象環境が存在することを検証
3. **安全性検証**: デプロイメント安全性チェックを実行
4. **マトリクス生成**: ディレクトリ構造に基づいて全環境のデプロイメントターゲットを作成
5. **出力生成**: 簡素化された出力で GitHub Actions 用に結果をフォーマット

## 設定

設定仕様と matrix の形式はルートの [設定](../../README-ja.md#設定) と [matrix 出力](../../README-ja.md#matrix-出力) を参照してください。

## デプロイラベル

システムは `deploy:service` 形式のラベルを認識します：

- `deploy:auth` - auth サービスをデプロイ
- `deploy:api` - api サービスをデプロイ
- `deploy:frontend` - frontend サービスをデプロイ
- `deploy:all` - 実在する全サービスの対象を解決

## 環境の指定

**トランクベース開発**: リゾルバーはブランチベースマッピングではなく明示的な環境指定を使用：

- 環境はパラメータとして直接指定
- 環境決定にブランチ名への依存なし
- 設定で定義された任意のデプロイメント環境をサポート
- 複数環境への同時デプロイメントが可能

## デプロイ対象の解決

指定環境を各 stack の定義環境に絞り、全パスの実在ディレクトリを列挙します。環境指定の省略または空白入力は全定義環境を選択します。環境共通の対象は各ディレクトリにつき一度だけ生成します。

`deploy:all` は設定したパスから全サービスを探索します。除外条件に一致する対象は matrix に含めません。存在しないパスは正常な空の結果になり、未知環境・列挙エラー・抽出値の矛盾は失敗になります。

## エラー処理

リゾルバーは包括的なエラーハンドリングを提供します：

- **無効な環境**: 対象環境が存在しない場合の明確なエラー
- **ラベル不足**: デプロイラベルのない PR の適切な処理
- **設定エラー**: ワークフロー設定の詳細な検証
- **ディレクトリ検出**: 存在しないパスは正常な空の結果

## 開発

### テストの実行

```bash
cd action-scripts
bundle exec rspec spec/label-resolver/
```

### ローカルでの動作確認

実行環境を設定します。

```bash
export GITHUB_TOKEN=your_token
export GITHUB_REPOSITORY=owner/repo
export SOURCE_REPO_PATH=your_source_path
export WORKFLOW_CONFIG_PATH=workflow-config.yaml
```

実際の PR を使ってデバッグします。

```bash
bundle exec ruby label-resolver/bin/resolver debug 123 develop
```
