# FluxCD マニフェストジェネレーター

[🇺🇸 English](README.md) | **日本語**

[![Ruby](https://img.shields.io/badge/Ruby-3.4.4-red.svg)](https://www.ruby-lang.org/)
[![Clean Architecture](https://img.shields.io/badge/Architecture-Clean-blue.svg)](https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html)
[![GitOps](https://img.shields.io/badge/GitOps-FluxCD-purple.svg)](https://fluxcd.io/)

シンプルなアプリケーションマニフェストディレクトリから完全なFluxCD GitOps設定を自動生成する高機能なRubyアプリケーション。CI/CDパイプラインでの保守性、テスト性、信頼性を考慮したクリーンアーキテクチャで構築されています。

## 🎯 目的

FluxCD マニフェストジェネレーターは、あなたのアプリケーションマニフェストを完全なGitOpsセットアップに変換し、以下を実現します：

- **🔄 継続的デプロイメント**: gitからKubernetesへの自動同期
- **🏢 環境分離**: develop/staging/productionの独立した設定
- **📝 宣言的管理**: gitによるすべてのインフラのコード化
- **🚀 マルチアプリケーション サポート**: 環境ごとの複数サービス対応
- **⚡ GitHub Actions 統合**: シームレスなCI/CDパイプライン統合

## 🏗️ アーキテクチャ

### クリーンアーキテクチャ実装

アプリケーションは関心の分離を明確にしたクリーンアーキテクチャの原則に従っています：

```
lib/
├── entities/          # 🏛️  ドメインモデル (Environment, FluxResource, ManifestFile)
├── use_cases/         # 🎯 ビジネスロジック (GenerateFluxManifests, Setup, Validation)
├── controllers/       # 🎮 インターフェース アダプター (CLI処理, オーケストレーション)
└── repositories/      # 💾 インフラストラクチャ (ファイルI/O, データアクセス)
```

### 依存関係の流れ
- **Entities**: 依存関係なし（純粋なドメインロジック）
- **Use Cases**: エンティティのみに依存
- **Controllers**: ユースケースとエンティティに依存
- **Repositories**: インターフェースを通じてアクセスされるインフラ層

## 📁 生成される構造

ジェネレーターは以下の標準化されたFluxCD構造を作成します：

```
{environment}/                    # アプリケーションマニフェスト
├── kustomization.yaml           # 環境ルートkustomization
├── service-a.yaml              # 個別のサービスマニフェスト
├── services/                   # オプショナルなサービスグループ化
│   ├── kustomization.yaml
│   ├── service-b.yaml
│   └── service-c.yaml
└── clusters/{environment}/     # FluxCD コントロールプレーン
    ├── flux-system/
    │   ├── gotk-sync.yaml      # Git同期設定
    │   └── kustomization.yaml   # Fluxシステムエントリーポイント
    └── apps/
        ├── kustomization.yaml   # アプリケーション オーケストレーション
        ├── service-a.yaml      # アプリケーション固有のKustomization
        └── services/
            ├── service-b.yaml
            └── service-c.yaml
```

## 🚀 クイックスタート

### ローカル使用

```bash
# 依存関係のインストール
bundle install

# 全環境のマニフェスト生成
bundle exec ruby bin/generator generate

# 特定環境の生成
bundle exec ruby bin/generator generate -e develop staging

# カスタムリポジトリURLでの生成
bundle exec ruby bin/generator generate -r https://github.com/your-org/manifests

# 指定ディレクトリへの生成
bundle exec ruby bin/generator generate -t /path/to/output

# 既存設定の検証
bundle exec ruby bin/generator validate

# ディレクトリ構造のセットアップ
bundle exec ruby bin/generator setup
```

### GitHub Actions 統合

```yaml
- name: FluxCD マニフェスト生成
  uses: panicboat/deploy-actions/flux-generator@main
  with:
    github-token: ${{ secrets.GITHUB_TOKEN }}
    target-path: ${{ github.workspace }}
    environments: 'develop,staging,production'
```

## 📋 CLIコマンド

### `generate` - FluxCD マニフェスト生成

指定された環境の完全なFluxCDマニフェストセットを生成します。

```bash
bin/generator generate [OPTIONS]
```

**オプション:**
- `-e, --environments ARRAY`: 対象環境 (デフォルト: develop,staging,production)
- `-r, --repository-url STRING`: Gitリポジトリ URL (GITHUB_REPOSITORYから自動検出)
- `-t, --target-dir STRING`: 出力ディレクトリ (デフォルト: カレントディレクトリ)
- `-v, --verbose`: 詳細出力を有効化

**例:**
```bash
# 基本的な使用法
bin/generator generate

# 特定の環境
bin/generator generate -e develop staging

# カスタムリポジトリ
bin/generator generate -r https://github.com/company/app-manifests

# 異なるディレクトリへの出力
bin/generator generate -t ../manifests-output
```

### `validate` - 設定検証

既存の環境設定とディレクトリ構造を検証します。

```bash
bin/generator validate [OPTIONS]
```

**検証項目:**
- ✅ 環境名の妥当性
- ✅ ディレクトリ構造の整合性
- ✅ マニフェストファイルの発見
- ✅ FluxCDパス設定
- ✅ kustomizationファイル構造

### `setup` - 構造の初期化

FluxCDリソースを生成せずにディレクトリ構造とプレースホルダーファイルを作成します。

```bash
bin/generator setup [OPTIONS]
```

**実行される操作:**
- 📁 環境ディレクトリの作成
- 📁 FluxCDクラスターディレクトリの作成
- 📄 プレースホルダーkustomizationファイルの生成
- 🔍 既存マニフェストの検出と統合

### `version` - バージョン情報

バージョンとアーキテクチャ情報を表示します。

```bash
bin/generator version
```

### `help_usage` - 使用例

包括的な使用例と統合のヒントを表示します。

```bash
bin/generator help_usage
```

## 🔧 設定

### 環境変数

- **`GITHUB_REPOSITORY`**: 自動検出されるリポジトリURL (形式: `owner/repo`)
- **`BUNDLE_GEMFILE`**: カスタムGemfile場所の指定

### 入力ディレクトリ構造

アプリケーションマニフェストを環境ディレクトリに配置してください：

```
develop/
├── nginx-app.yaml
├── api-service.yaml
└── services/
    ├── database.yaml
    └── redis.yaml

staging/
├── nginx-app.yaml
└── api-service.yaml

production/
├── nginx-app.yaml
└── api-service.yaml
```

ジェネレーターはこれらのマニフェストを自動的に発見し、適切なFluxCDリソースを作成します。

## 🏗️ 核となるコンポーネント

### エンティティ（ドメインモデル）

#### Environment
パス計算と検証を備えた対象デプロイメント環境を表現。

```ruby
environment = Entities::Environment.from_name('develop')
environment.name           # => 'develop'
environment.flux_system_path # => './clusters/develop/flux-system'
environment.apps_path      # => './clusters/develop/apps'
```

#### FluxResource
YAMLシリアライゼーション機能を持つKubernetes/FluxCDリソースの汎用表現。

```ruby
git_repo = Entities::FluxResource.git_repository(
  name: 'flux-system',
  namespace: 'flux-system',
  url: 'https://github.com/company/manifests'
)
```

#### ManifestFile
パスと命名ロジックを持つアプリケーションマニフェストファイルを表現。

```ruby
manifest = Entities::ManifestFile.from_path('develop/services/api.yaml', 'develop')
manifest.service_name    # => 'api'
manifest.in_subdirectory? # => true
```

### ユースケース（ビジネスロジック）

#### GenerateFluxManifests
5つの生成ステップを調整するメインオーケストレーター：

1. **GitRepository & Root Kustomization** (`GenerateGotkSync`)
2. **Flux System Setup** (`GenerateFluxSystemKustomization`)
3. **Apps Organization** (`GenerateAppsKustomization`)
4. **Individual App Resources** (`GenerateAppResources`)
5. **Environment Structure** (`GenerateEnvironmentKustomizations`)

### コントローラー（インターフェース層）

#### FluxGeneratorController
- マニフェスト生成のメインエントリーポイント
- リポジトリURL自動検出
- エラーハンドリングとユーザーフィードバック

#### SetupController
- ディレクトリ構造管理
- 不足環境の作成
- プレースホルダーファイル生成

#### ValidationController
- 設定検証
- ヘルスチェック レポート
- 問題の識別

### リポジトリ（インフラストラクチャ層）

#### FileSystemRepository
- ファイルシステム抽象化
- ディレクトリとファイル操作
- YAMLファイル発見

#### ManifestRepository
- マニフェストファイル操作
- ビジネスロジック対応フィルタリング
- ManifestFileエンティティ作成

## 🧪 開発

### 前提条件

- Ruby 3.4.4+
- Bundler 2.6.7+

### セットアップ

```bash
# リポジトリのクローン
git clone https://github.com/panicboat/deploy-actions.git
cd deploy-actions/flux-generator

# 依存関係のインストール
bundle install

# テストの実行
bundle exec rspec

# 構文チェック
find lib -name "*.rb" -exec ruby -c {} \;
```

### テスト

```bash
# 全テストの実行
bundle exec rspec

# 特定テストファイルの実行
bundle exec rspec spec/entities/environment_spec.rb

# カバレッジ付き実行
bundle exec rspec --format documentation
```

### コード品質

```bash
# 構文チェック
ruby -c bin/generator
find lib -name "*.rb" -exec ruby -c {} \;

# スタイルチェック（rubocopが設定されている場合）
bundle exec rubocop
```

## 📚 生成されるFluxCDリソース

### GitRepository リソース
```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: flux-system
  namespace: flux-system
spec:
  interval: 1m0s
  ref:
    branch: main
  url: https://github.com/company/manifests
```

### Kustomization リソース
```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: flux-system
  namespace: flux-system
spec:
  interval: 10m0s
  path: ./clusters/develop
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
```

### Kustomize 設定
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - service-a.yaml
  - services/
```

## 🔄 ワークフロー

### 生成ワークフロー
1. **入力処理**: CLI引数の解析と環境の検証
2. **リポジトリ検出**: gitリポジトリURLの自動検出または検証
3. **ディレクトリセットアップ**: 完全なディレクトリ構造の確保
4. **マニフェスト発見**: 環境内の既存アプリケーションマニフェストのスキャン
5. **FluxCD生成**: GitRepositoryとKustomizationリソースの作成
6. **Kustomization作成**: 組織的なkustomizationファイルの生成
7. **検証**: 生成された構造の整合性確認
8. **完了**: 生成結果のレポート

### セットアップワークフロー
1. **構造検証**: 既存ディレクトリレイアウトのチェック
2. **不足検出**: 不在の環境とファイルの識別
3. **ディレクトリ作成**: 完全なFluxCD階層の構築
4. **プレースホルダー生成**: 空のkustomizationファイルの作成
5. **サービス発見**: 既存サービスのスキャンと統合
6. **検証**: 作成された構造の確認

## ⚡ GitHub Actions 使用法

### 基本セットアップ

```yaml
name: FluxCD マニフェスト同期

on:
  push:
    branches: [main]
  workflow_dispatch:

jobs:
  sync:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: FluxCD マニフェスト生成
        uses: panicboat/deploy-actions/flux-generator@main
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          target-path: ${{ github.workspace }}

      - name: プルリクエスト作成
        uses: peter-evans/create-pull-request@v7
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
          commit-message: "auto: FluxCD マニフェスト更新"
          title: "FluxCD マニフェスト自動更新"
```

### 高度な設定

```yaml
- name: FluxCD マニフェスト生成
  uses: panicboat/deploy-actions/flux-generator@main
  with:
    github-token: ${{ secrets.GITHUB_TOKEN }}
    target-path: ${{ github.workspace }}/generated-manifests
    environments: 'develop,staging'
    deploy-actions-repository: 'company/custom-deploy-actions'
```

## 🤝 コントリビューション

1. リポジトリをフォーク
2. フィーチャーブランチを作成 (`git checkout -b feature/amazing-feature`)
3. 変更をコミット (`git commit -m 'Add amazing feature'`)
4. ブランチにプッシュ (`git push origin feature/amazing-feature`)
5. プルリクエストを開く

### 開発ガイドライン

- クリーンアーキテクチャの原則に従う
- 高いテストカバレッジを維持
- 一貫したRubyスタイルを使用
- 包括的なドキュメントを追加
- 使用例を含める

## 📄 ライセンス

このプロジェクトはMITライセンスの下でライセンスされています - 詳細は[LICENSE](LICENSE)ファイルを参照してください。

## 🆘 サポート

- **問題**: [GitHub Issues](https://github.com/panicboat/deploy-actions/issues)
- **ディスカッション**: [GitHub Discussions](https://github.com/panicboat/deploy-actions/discussions)
- **ドキュメント**: [FluxCD ドキュメント](https://fluxcd.io/docs/)

## 🙏 謝辞

- GitOpsツールキットの[FluxCD](https://fluxcd.io/)
- Uncle Bobによる[クリーンアーキテクチャ](https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html)
- 優秀なRubyライブラリの[dry-rb](https://dry-rb.org/)
- CLIフレームワークの[Thor](https://github.com/rails/thor)
