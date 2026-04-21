# Claude Code Action Refactor Design

## Overview

`platform` と `monorepo` の `claude-code-action.yaml` が重複しており、セキュリティ設定（許可ユーザー）と AWS 設定（IAM ロール ARN）が呼び出し側に分散している問題を解決する。

## Problem

- `CLOUD_CODE_ALLOWED_USERS` をリポジトリ変数として各リポジトリに定義しなければならない
- `aws-role-arn` が呼び出し側ワークフローにハードコードされており、変更時に全リポジトリを修正する必要がある
- 個人アカウントのため Organization Variables は使用不可

## Decisions

| 項目 | 決定内容 | 理由 |
|---|---|---|
| 認可方式 | `github.repository_owner == github.actor` | イベント種別によらず使える。個人アカウントでの利用なのでオーナーのみで十分 |
| 認可チェックの場所 | `action.yaml` 内の先頭ステップ（`exit 1`） | 呼び出し側から認可ロジックを除去できる。不届者の呼び出しは明示的にエラーにする |
| `aws-role-arn` の管理 | `action.yaml` のデフォルト値として集約 | 変更箇所を1か所に限定する |
| Reusable Workflow | 作成しない | テスト時のクロスリポジトリ参照が煩雑になるため |

## Architecture

```
caller workflows (platform / monorepo / deploy-actions)
  └─ panicboat/deploy-actions/claude-code-action@main  (composite action)
        ├─ Authorize step (exit 1 if not owner)
        ├─ Generate GitHub App token
        ├─ Configure AWS Credentials
        └─ Run Claude Code (anthropics/claude-code-action)
```

## Changes

### `deploy-actions/claude-code-action/action.yaml`

- 先頭に `Authorize` ステップを追加
  - `github.actor != github.repository_owner` の場合は `exit 1`
- `aws-role-arn` を `required: false` に変更し、現在の ARN をデフォルト値として設定

### `platform/.github/workflows/claude-code-action.yaml`

- `if` 条件から `CLOUD_CODE_ALLOWED_USERS` の参照を削除し、`@claude` トリガー確認のみに変更
- `aws-role-arn` の行を削除

### `monorepo/.github/workflows/claude-code-action.yaml`

- `platform` と同様の変更

### `deploy-actions/.github/workflows/claude-code-action.yaml`（新規）

- `platform` / `monorepo` と同一内容のワークフローを新規作成

## Final File Contents

### `action.yaml`（変更後）

```yaml
name: Claude Code Action
description: Run Claude Code action with AWS Bedrock integration

inputs:
  token:
    description: 'GitHub token for authentication'
    required: true
  aws-role-arn:
    description: 'AWS IAM role ARN for Bedrock access'
    required: false
    default: 'arn:aws:iam::559744160976:role/ai-assistant-develop-github-actions-role'
  aws-region:
    description: 'AWS region'
    required: false
    default: 'us-west-2'
  trigger-phrase:
    description: 'Phrase to trigger Claude'
    required: false
    default: '@claude'
  model:
    description: 'Claude model to use'
    required: false
    default: 'us.anthropic.claude-sonnet-4-6'

runs:
  using: composite
  steps:
    - name: Authorize
      shell: bash
      run: |
        if [ "${{ github.repository_owner }}" != "${{ github.actor }}" ]; then
          echo "::error::${{ github.actor }} is not authorized to run Claude Code"
          exit 1
        fi

    - name: Checkout code
      uses: actions/checkout@v6.0.2
      with:
        token: ${{ inputs.token }}
        fetch-depth: 1

    - name: Configure AWS Credentials
      uses: aws-actions/configure-aws-credentials@v6.1.0
      with:
        role-to-assume: ${{ inputs.aws-role-arn }}
        aws-region: ${{ inputs.aws-region }}

    - name: Run Claude Code
      uses: anthropics/claude-code-action@v1.0.101
      with:
        github_token: ${{ inputs.token }}
        trigger_phrase: ${{ inputs.trigger-phrase }}
        claude_args: --model ${{ inputs.model }}
        use_bedrock: "true"
      env:
        ANTHROPIC_BEDROCK_BASE_URL: https://bedrock-runtime.${{ inputs.aws-region }}.amazonaws.com
        ANTHROPIC_MAX_RETRIES: "3"
        ANTHROPIC_TIMEOUT: "120"
        ANTHROPIC_REQUEST_DELAY: "5"
        CLAUDE_CODE_MAX_OUTPUT_TOKENS: 8192
```

### 呼び出し側ワークフロー（3リポジトリ共通）

```yaml
name: Claude Code Action

permissions:
  contents: write
  pull-requests: write
  issues: write
  id-token: write

on:
  issues:
    types: [opened, assigned]
  issue_comment:
    types: [created]
  pull_request_review:
    types: [submitted]
  pull_request_review_comment:
    types: [created]

jobs:
  claude-code-action:
    runs-on: ubuntu-latest
    timeout-minutes: 60
    if: |
      contains(github.event.comment.body, '@claude') || contains(github.event.issue.body, '@claude')
    steps:
      - name: Generate GitHub App token
        id: app-token
        uses: actions/create-github-app-token@v3.1.1
        with:
          app-id: ${{ vars.APP_ID }}
          private-key: ${{ secrets.APP_PRIVATE_KEY }}
          owner: ${{ github.repository_owner }}

      - name: Run Claude Code
        uses: panicboat/deploy-actions/claude-code-action@main
        with:
          token: ${{ steps.app-token.outputs.token }}
          trigger-phrase: "@claude"
```

## Prerequisites

`deploy-actions` リポジトリに新規ワークフローを追加するため、以下の設定が必要：

- `vars.APP_ID` — GitHub App の App ID（`platform`・`monorepo` と同じ値）
- `secrets.APP_PRIVATE_KEY` — GitHub App の秘密鍵（`platform`・`monorepo` と同じ値）

## Security Considerations

- `@claude` を含まないイベントではジョブ自体が起動しない（`if` 条件でフィルタ）
- オーナー以外の呼び出しは `action.yaml` 内でエラーになる（`exit 1`）
- `aws-role-arn` はデフォルト値として `action.yaml` に集約され、呼び出し側に露出しない
- `CLOUD_CODE_ALLOWED_USERS` 変数の設定忘れによるセキュリティリスクがなくなる
