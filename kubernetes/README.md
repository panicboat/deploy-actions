# Kubernetes Diff

Kustomize overlay をビルドし、base ブランチとの差分を PR コメントに投稿する composite action。内部で `int128/kustomize-action` と `int128/diff-action` を使用する。

## Inputs

| Name | Required | Description |
|------|----------|-------------|
| `github-token` | Yes | 必要な権限を持つ GitHub token |
| `service-name` | Yes | 識別用のサービス名 |
| `environment` | Yes | 環境名 (`develop`, `staging`, `production` など) |
| `path` | Yes | kustomize overlay ディレクトリへのパス |
| `pr-number` | No | コメント投稿先の PR 番号 |

## Outputs

| Name | Description |
|------|-------------|
| `has-diff` | 差分が検出されたかどうか (`true`/`false`) |

## Usage

```yaml
jobs:
  kubernetes-diff:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      pull-requests: write

    steps:
      - name: Checkout
        uses: actions/checkout@v4

      - name: Generate GitHub App token
        id: app-token
        uses: actions/create-github-app-token@v2.2.1
        with:
          app-id: ${{ vars.APP_ID }}
          private-key: ${{ secrets.APP_PRIVATE_KEY }}

      - name: Kubernetes Diff
        uses: panicboat/deploy-actions/kubernetes@main
        with:
          github-token: ${{ steps.app-token.outputs.token }}
          service-name: api
          environment: production
          path: kubernetes/overlays/production
          pr-number: ${{ github.event.pull_request.number }}
```

## Requirements

- リポジトリがチェックアウトされていること（ワークスペースに head 状態のコードが存在する必要がある）
- PR イベントコンテキストが利用可能であること（`github.event.pull_request.base.sha` を参照するため）
