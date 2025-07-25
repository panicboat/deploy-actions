# FluxCD マニフェスト生成ツール

[🇺🇸 English](README.md) | **日本語**

シンプルなアプリケーションマニフェストから完全なFluxCD GitOps設定を生成します。

## クイックスタート

```bash
# インストールして実行
bundle install
bundle exec ruby bin/generator generate

# カスタムオプション付き
bin/generator generate -e my-env custom-cluster -n generated-manifests -t my-namespace -o ./output
```

## GitHub Actions

```yaml
- name: FluxCD マニフェスト生成
  uses: panicboat/deploy-actions/flux-generator@main
  with:
    github-token: ${{ secrets.GITHUB_TOKEN }}
    environments: 'develop,staging,production'
    repository-name: 'my-manifests'
```

## CLIオプション

| オプション | 説明 | デフォルト |
|------------|------|------------|
| `-r, --repository-url` | GitリポジトリURL | 自動検出 |
| `-e, --environments` | 対象環境（任意の文字列） | `develop,staging,production` |
| `-n, --resource-name` | GitRepository/Kustomization名 | 自動生成（例: `flux-a1b2c3d4`） |
| `-t, --target-namespace` | Kustomizationリソースのターゲット名前空間 | なし |
| `-o, --output-dir` | 出力ディレクトリ | カレントディレクトリ |
| `-v, --verbose` | 詳細出力 | `false` |

## 入力構造

アプリケーションマニフェストを環境ディレクトリに配置：

```
develop/
├── web-app.yaml
└── services/
    └── database.yaml
```

## 生成される構造

完全なFluxCD GitOpsセットアップを作成：
- **GitRepository**: ソースリポジトリ設定
- **Kustomization**: FluxCDリソース管理
- **ディレクトリ構造**: `clusters/{environment}/{flux-system,apps}/`
- **Kustomize設定**: マニフェスト整理

## 開発

```bash
bundle exec rspec                    # テスト実行
bundle exec rubocop                  # コードスタイルチェック
```

## ライセンス

MIT License
