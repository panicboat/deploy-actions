# Container Cleaner

container-builder で生成されるコンテナイメージを自動的にクリーンアップするアクションです。

## 概要

このアクションは container-builder のタグ構成（`sha`, `pr-*`, `latest`）に最適化されており、以下のルールで古いイメージを削除します:

- ✅ **`latest` タグ**: 常に保持
- ✅ **`pr-*` タグ**: 指定日数以上経過したら削除（デフォルト: 7日）
- ✅ **`sha-*` タグ**: すべて削除
- ✅ **`untagged` イメージ**: すべて削除

## 特徴

- **シンプル**: イメージ名を指定するだけで動作
- **最適化**: container-builder のタグ構成に特化
- **安全**: Dry-runモードで削除対象を事前確認可能
- **信頼性**: マルチアーキテクチャイメージの検証を自動実行

## 使用方法

### 基本的な使用例

```yaml
- name: Build and push container image
  uses: panicboat/deploy-actions/container-builder@main
  with:
    token: ${{ secrets.GITHUB_TOKEN }}
    image-name: my-service

- name: Clean old container images
  uses: panicboat/deploy-actions/container-cleaner@main
  with:
    token: ${{ secrets.GITHUB_TOKEN }}
    image-name: my-service
```

これだけで以下が実現されます:
- `latest` タグ: 保持
- `pr-*` タグ: 7日以上経過したら削除
- `sha-*` タグ: すべて削除
- `untagged`: すべて削除

### PRタグの保持期間を変更

```yaml
- name: Clean old container images
  uses: panicboat/deploy-actions/container-cleaner@main
  with:
    token: ${{ secrets.GITHUB_TOKEN }}
    image-name: my-service
    pr-retention-days: 14  # 14日に変更
```

### Dry-runで削除対象を事前確認

```yaml
- name: Check what would be deleted
  uses: panicboat/deploy-actions/container-cleaner@main
  with:
    token: ${{ secrets.GITHUB_TOKEN }}
    image-name: my-service
    dry-run: true
```

### スケジュール実行の例

```yaml
name: Cleanup Old Images
on:
  schedule:
    # 毎週月曜日の午前2時（UTC）に実行
    - cron: '0 2 * * 1'
  workflow_dispatch:  # 手動実行も可能

jobs:
  cleanup:
    runs-on: ubuntu-latest
    permissions:
      packages: write  # パッケージ削除には書き込み権限が必要
    steps:
      - name: Clean old container images
        uses: panicboat/deploy-actions/container-cleaner@main
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
          image-name: my-service
```

## パラメータ

| パラメータ | 説明 | 必須 | デフォルト |
|-----------|------|------|-----------|
| `token` | GitHub認証トークン（`packages:delete`権限が必要） | ✅ | - |
| `image-name` | イメージ名（例: `service-name`） | ✅ | - |
| `pr-retention-days` | PRタグの保持期間（日数） | - | `7` |
| `dry-run` | 削除せずに対象を表示するのみ（`true`/`false`） | - | `false` |

## 削除ルール（固定）

以下のルールは固定で、パラメータによる変更はできません:

- **`latest` タグ**: 常に保持（削除対象外）
- **`pr-*` タグ**: `pr-retention-days` で指定した日数以上経過したら削除
- **`sha-*` タグ**: 日数に関係なくすべて削除
- **`untagged`**: すべて削除
- **マルチアーキテクチャ検証**: 常に有効

## 権限設定

このアクションを使用するには、`packages:write`または`packages:delete`権限が必要です:

```yaml
permissions:
  packages: write
```

## ベストプラクティス

1. **初回はDry-runで確認**
   ```yaml
   dry-run: true
   ```
   本番環境で使用する前に、削除対象を必ず確認してください。

2. **container-builderの直後に実行**
   ```yaml
   - uses: panicboat/deploy-actions/container-builder@main
     with:
       token: ${{ secrets.GITHUB_TOKEN }}
       image-name: my-service

   - uses: panicboat/deploy-actions/container-cleaner@main
     with:
       token: ${{ secrets.GITHUB_TOKEN }}
       image-name: my-service
   ```
   イメージビルド後に古いイメージを削除することで、ストレージを効率的に管理できます。

3. **定期的なクリーンアップ**
   ```yaml
   on:
     schedule:
       - cron: '0 2 * * 1'  # 毎週月曜日午前2時（UTC）
   ```
   スケジュール実行でストレージコストを削減できます。

## トラブルシューティング

### エラー: "Resource not accessible by integration"

`packages:write`権限が不足しています。ワークフローに以下を追加してください:

```yaml
permissions:
  packages: write
```

### 削除されるべきイメージが残っている

1. `dry-run: true`で削除対象を確認
2. PRタグの場合、`pr-retention-days` の設定値を確認
3. `latest` タグは常に保持される仕様です

## 参考リンク

- [dataaxiom/ghcr-cleanup-action](https://github.com/marketplace/actions/ghcr-io-cleanup-action)
- [GitHub Packages Documentation](https://docs.github.com/en/packages)
