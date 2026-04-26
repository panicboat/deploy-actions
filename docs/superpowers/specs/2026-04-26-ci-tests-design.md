# CI Tests Introduction Design

## Background

`deploy-actions` リポジトリには `action-scripts/` 配下に RSpec のテスト群（13 spec files、213 examples）が整備されているが、`.github/workflows/` が存在せず、PR/push 時に自動実行されていない。テスト失敗や `workflow-config.yaml` のスキーマ不正がレビュー時に検出されず、merge 後に気づくリスクがある。

## Goal

PR 作成・更新のたびに以下を自動実行し、結果を GitHub の Checks に表示する。

- RSpec によるユニットテスト
- `workflow-config.yaml` のスキーマ検証

## Non-goals

- RuboCop による Ruby Lint（既存コードに 905 offenses あり、別件で導入）
- Branch protection の必須チェック化（後で GitHub UI から手動設定）
- main への push トリガーの追加
- JS スクリプト（`label-dispatcher/*.js`, `label-resolver/*.js`）への lint / 構文チェック
- カバレッジ計測の導入
- リリース / デプロイ用 workflow の追加

## Architecture

`.github/workflows/check.yaml` を 1 ファイル新設し、`pull_request` で 2 つのジョブを並列実行する。

```
.github/workflows/check.yaml
├─ job: rspec            # bundle exec rspec
└─ job: validate-config  # bundle exec ruby config-manager/bin/config-manager validate
```

すべてのジョブは `runs-on: ubuntu-latest` で `action-scripts/` を作業ディレクトリとし、共通の前段ステップ（checkout → setup-ruby + bundler-cache）を持つ。並列のため失敗箇所が一目でわかり、最遅のジョブ時間で完了する。

## Triggers and Path Filter

```yaml
on:
  pull_request:
    paths:
      - 'action-scripts/**'
      - 'label-dispatcher/**'
      - 'label-resolver/**'
      - '.github/workflows/check.yaml'
```

- `pull_request` のみ。main への push では走らない
- 上記いずれにも触れていない PR（README のみの変更で作成された PR など）は workflow が起動しない。既に対象パスを含む PR では、後から追加した README-only の commit でも workflow は起動する（GitHub Actions は PR 全体の累積差分で評価するため）
- `label-dispatcher/` `label-resolver/` を含むのは、これらのアクションが `workflow-config.yaml` のスキーマと整合する必要があり、関連変更時にも検証を回したいため

同一 PR で push が連続した場合、古い実行をキャンセルする:

```yaml
concurrency:
  group: check-${{ github.ref }}
  cancel-in-progress: true
```

## Files

### New

- `.github/workflows/check.yaml` — workflow 定義
- `action-scripts/.ruby-version` — `3.4.5`（現在のローカル環境に合わせる）

### Unchanged

- `action-scripts/Gemfile` — rspec / webmock / vcr / factory_bot は既に揃っている
- `action-scripts/spec/Rakefile` — CI からは生コマンドで呼ぶため変更しない
- `action-scripts/workflow-config.yaml` — そのまま検証対象として使用

## Workflow Definition

```yaml
name: check

on:
  pull_request:
    paths:
      - 'action-scripts/**'
      - 'label-dispatcher/**'
      - 'label-resolver/**'
      - '.github/workflows/check.yaml'

concurrency:
  group: check-${{ github.ref }}
  cancel-in-progress: true

defaults:
  run:
    working-directory: action-scripts

jobs:
  rspec:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4
      - uses: ruby/setup-ruby@0cb964fd540e0a24c900370abf38a33466142735 # v1
        with:
          ruby-version-file: action-scripts/.ruby-version
          bundler-cache: true
          working-directory: action-scripts
      - run: bundle exec rspec

  validate-config:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@34e114876b0b11c390a56381ad16ebd13914f8d5 # v4
      - uses: ruby/setup-ruby@0cb964fd540e0a24c900370abf38a33466142735 # v1
        with:
          ruby-version-file: action-scripts/.ruby-version
          bundler-cache: true
          working-directory: action-scripts
      - run: bundle exec ruby config-manager/bin/config-manager validate
```

### Notes on YAML Semantics

- `defaults.run.working-directory` は `run:` ステップにのみ適用され、`uses:` ステップ（actions/checkout, ruby/setup-ruby）には影響しない
- `ruby/setup-ruby` の `working-directory` 入力は Gemfile の探索位置を示す独立パラメータなので、各ジョブで明示する
- `ruby-version-file` のパスはリポジトリルートからの相対パス

## Job Behavior

| Job | コマンド | 失敗条件 |
|-----|---------|---------|
| rspec | `bundle exec rspec` | spec 失敗時。`.rspec` の `--require spec_helper` が効くため設定不要 |
| validate-config | `bundle exec ruby config-manager/bin/config-manager validate` | YAML パースエラー、スキーマ違反、必須属性欠落など |

`spec_helper.rb` で `WebMock.disable_net_connect!` 設定済のため、CI 環境でも外部通信は発生しない。VCR カセット未録画でも spec 内で stub されているもののみ通信する設計。

## Testing

`workflow_dispatch` を入れない方針なので、検証は本ブランチを push してドラフト PR を立てることで行う。

検証項目:
1. 2 ジョブが並列起動する
2. すべて green になる
3. パスフィルタ動作確認: 対象パスを一切触らない PR を別途作って、workflow がそもそも起動しないことを確認（既存 PR への README 追加 commit ではない点に注意）
4. concurrency 動作確認: 連続 push で古い実行が cancel される

## Security

- `actions/checkout` (v4) と `ruby/setup-ruby` (v1) のみ使用。サードパーティ製アクションは導入しない
- 各 action は full commit SHA でピン止めし、`# v<major>` コメントで読み手向けに対応するタグを併記する。バージョン更新は Renovate などで追跡する
- secrets を参照するステップはなし（GITHUB_TOKEN も明示的には使わない）
- `pull_request` イベントのみ使用するため、フォークからの PR で secrets が露出する `pull_request_target` のリスクなし

## Future Work

- Branch protection で `rspec` / `validate-config` を必須チェックに登録
- RuboCop 導入（`.rubocop_todo.yml` でグランドファザー化 + 段階的解消）
- カバレッジ計測（SimpleCov）の追加
- JS スクリプトに対する lint / 構文チェック
- main への push 時にも走らせるか検討（リグレッション検出のため）
