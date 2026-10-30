# Label Resolver

[🇺🇸 English](README.md) | **日本語**

PR ラベルを明示的な環境指定を使って GitHub Actions 自動化のためのデプロイメントターゲットに変換する Ruby ベースのデプロイメント解決ツールです。

## 概要

Label Resolver は PR ラベルを分析し、指定された環境に対するデプロイメントターゲットを生成します。マルチサービスデプロイメント用のデプロイメントマトリクスを作成し、デプロイメント自動化の意思決定の中心的なオーケストレーターとして機能します。

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

**環境指定：**

- 単一環境: `develop`
- 複数環境: `develop,staging` (カンマ区切り)
- 全環境: 環境一覧パラメータを省略

Pull Request なしで、1 つのサービスまたは全サービスのデプロイ対象を解決します。このコマンドは GitHub API を呼ばず、`GITHUB_TOKEN` を必要としません。

```bash
bundle exec ruby label-resolver/bin/resolver targets SERVICE [ENVIRONMENTS]
```

**サービス指定：**

- 単一サービス: `[a-zA-Z0-9_-]+` に一致するサービス名
- 全サービス: `all`

ENVIRONMENTS の指定方法は `resolve` と同じです。パターンに合わないサービス名、および定義も探索もされていない環境は終了コード 1 で失敗します。

### 実行例

`develop` 環境のデプロイ対象を解決します。

```bash
bundle exec ruby label-resolver/bin/resolver resolve 123 develop
```

複数環境のデプロイ対象をまとめて解決します。

```bash
bundle exec ruby label-resolver/bin/resolver resolve 456 develop,staging
```

定義環境と探索した環境すべてのデプロイ対象を解決します。

```bash
bundle exec ruby label-resolver/bin/resolver resolve 123
```

Pull Request なしで、1 つのサービスの `develop` 環境のデプロイ対象を解決します。

```bash
bundle exec ruby label-resolver/bin/resolver targets demo develop
```

全サービスの全環境のデプロイ対象を解決します。

```bash
bundle exec ruby label-resolver/bin/resolver targets all
```

### ワークフローへの組み込み

リゾルバーは通常 GitHub Actions ワークフローから呼び出されます：

単一環境を指定する場合：

```yaml
- name: Resolve deployment targets
  uses: panicboat/deploy-actions/label-resolver@v0.1.0
  with:
    pr-number: ${{ github.event.pull_request.number }}
    repository: ${{ github.repository }}
    github-token: ${{ secrets.GITHUB_TOKEN }}
    environments: ${{ inputs.target_environment }}
```

複数環境を指定する場合：

```yaml
- name: Resolve deployment targets
  uses: panicboat/deploy-actions/label-resolver@v0.1.0
  with:
    pr-number: ${{ github.event.pull_request.number }}
    repository: ${{ github.repository }}
    github-token: ${{ secrets.GITHUB_TOKEN }}
    environments: "develop,staging"
```

### Action の出力

リゾルバーは以下の GitHub Actions 出力を提供します：

- `targets`: マトリクス戦略用のデプロイメントターゲットの JSON 配列
- `has-targets`: ターゲットが存在するかを示すブール値 (`true`/`false`)

`targets` コマンドは、除外されていない candidate から求めた同じ 2 つの出力に加えて、次の出力を提供します：

- `candidates`: 除外された対象を含む全 candidate の JSON 配列。各要素は `{"target": <matrix 項目>, "excluded": <bool>, "root": "<root>"}` の形式

存在しないサービスはエラーになりません。`targets` は `[]`、`has-targets` は `false`、`candidates` は `[]` になります。

## アーキテクチャ

### 構成要素

- **LabelResolverController**: メインオーケストレーションロジック
- **GetLabels**: PR ラベル抽出
- **GenerateMatrix**: PR のデプロイラベルから、除外されていない対象だけのデプロイメントマトリクスを生成
- **ListServiceTargets**: サービス名の検証と、1 つまたは全サービスの対象の一覧化（除外された対象を含む全 candidate を返す）
- **ListCandidates**: `GenerateMatrix` と `ListServiceTargets` が共有する、環境検証と candidate の列挙

### 処理の流れ

`resolve`：

1. **ラベル抽出**: PR からデプロイラベルを取得
2. **candidate の一覧化**: `ListCandidates` が全ての対象環境の存在を検証し、ディレクトリ構造から candidate を列挙
3. **マトリクス生成**: `GenerateMatrix` が除外されていない candidate をデプロイメントターゲットにする
4. **出力生成**: 簡素化された出力で GitHub Actions 用に結果をフォーマット

`targets`：

1. **サービス検証**: `ListServiceTargets` が `[a-zA-Z0-9_-]+` に一致しないサービス名を拒否
2. **candidate の一覧化**: `ListCandidates` が対象環境を検証し、サービス（`all` なら全サービス）の candidate を列挙
3. **出力生成**: `targets` と `has-targets` は除外されていない candidate から、`candidates` は全 candidate を除外状態と root 付きで出力

## 設定

設定仕様と matrix の形式はルートの [設定](../../README-ja.md#設定) と [matrix 出力](../../README-ja.md#matrix-出力) を参照してください。

## デプロイラベル

システムは `deploy:service` 形式のラベルを認識します：

- `deploy:auth` - auth サービスをデプロイ
- `deploy:api` - api サービスをデプロイ
- `deploy:frontend` - frontend サービスをデプロイ
- `deploy:all` - 実在する全サービスの対象を解決

prefix と追加の prefix は設定で変更できます。ルートの [Labels](../../README-ja.md#labels) を参照してください。

## 環境の指定

**トランクベース開発**: リゾルバーはブランチベースマッピングではなく明示的な環境指定を使用：

- 環境はパラメータとして直接指定
- 環境決定にブランチ名への依存なし
- 設定で定義した環境と stack のパスから探索した環境をサポート
- 複数環境への同時デプロイメントが可能

## デプロイ対象の解決

指定環境を各 stack の定義環境または探索した環境から選び、全パスの実在ディレクトリを列挙します。環境指定の省略または空白入力は定義環境と探索した環境の和集合を選択します。`attributes` を持つ環境共通の対象は各ディレクトリにつき一度だけ生成します。

`deploy:all` は設定したパスから全サービスを探索します。除外条件に一致する対象は matrix に含めません。存在しないパスは正常な空の結果になり、未知環境・列挙エラー・抽出値の矛盾は失敗になります。

## エラー処理

リゾルバーは包括的なエラーハンドリングを提供します：

- **無効な環境**: 対象環境が存在しない場合の明確なエラー
- **無効なサービス名**: `targets` は `[a-zA-Z0-9_-]+` に一致しないサービス名を拒否
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

実際の PR のデプロイ対象を解決します。

```bash
bundle exec ruby label-resolver/bin/resolver resolve 123 develop
```
