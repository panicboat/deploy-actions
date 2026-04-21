# Claude Code Action Refactor Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** 認可チェックと AWS ARN を `action.yaml` に集約し、呼び出し側ワークフローを `@claude` トリガー確認のみのボイラープレートにする

**Architecture:** `action.yaml` に `Authorize` ステップ（オーナー以外は `exit 1`）を追加し、`aws-role-arn` をデフォルト値付きオプションに変更する。呼び出し側は `CLOUD_CODE_ALLOWED_USERS` 変数も `aws-role-arn` も不要になり、`@claude` トリガー確認と GitHub App トークン生成のみを担う。

**Tech Stack:** GitHub Actions (YAML), actionlint (静的検証)

---

## File Map

| ファイル | 操作 | 内容 |
|---|---|---|
| `deploy-actions/claude-code-action/action.yaml` | 修正 | Authorize ステップ追加、`aws-role-arn` をオプション化 |
| `deploy-actions/.github/workflows/claude-code-action.yaml` | 新規 | 呼び出し側ワークフロー |
| `platform/.github/workflows/claude-code-action.yaml` | 修正 | `if` 条件簡略化、`aws-role-arn` 削除 |
| `monorepo/.github/workflows/claude-code-action.yaml` | 修正 | `platform` と同内容 |

---

### Task 1: deploy-actions の worktree を作成する

**Files:**
- 対象リポジトリ: `/Users/takanokenichi/GitHub/panicboat/deploy-actions`

- [ ] **Step 1: `.git/info/exclude` に worktree パスを追加**

```bash
cd /Users/takanokenichi/GitHub/panicboat/deploy-actions
grep -q '/.claude/worktrees/' .git/info/exclude || echo '/.claude/worktrees/' >> .git/info/exclude
```

- [ ] **Step 2: worktree を作成**

```bash
git worktree add -b refactor/claude-code-action .claude/worktrees/refactor/claude-code-action origin/main
```

- [ ] **Step 3: worktree に移動して確認**

```bash
cd .claude/worktrees/refactor/claude-code-action
git branch
```

Expected: `* refactor/claude-code-action`

---

### Task 2: 検証ツールをインストールして現状を確認する

**Files:**
- 対象: `deploy-actions/.claude/worktrees/refactor/claude-code-action`

- [ ] **Step 1: ツールのインストール確認**

```bash
# workflow ファイル用
actionlint --version 2>/dev/null || brew install actionlint
# composite action (action.yaml) 用
yamllint --version 2>/dev/null || brew install yamllint
```

- [ ] **Step 2: 既存の `action.yaml` を検証**

```bash
cd /Users/takanokenichi/GitHub/panicboat/deploy-actions/.claude/worktrees/refactor/claude-code-action
yamllint claude-code-action/action.yaml
```

Expected: エラーなし（既存ファイルがクリーンな状態を確認）

---

### Task 3: `action.yaml` を修正する

**Files:**
- Modify: `deploy-actions/claude-code-action/action.yaml`

- [ ] **Step 1: `action.yaml` を以下の内容で上書き**

```bash
cd /Users/takanokenichi/GitHub/panicboat/deploy-actions/.claude/worktrees/refactor/claude-code-action
```

`claude-code-action/action.yaml` を以下の内容にする：

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

- [ ] **Step 2: yamllint で検証**

```bash
yamllint claude-code-action/action.yaml
```

Expected: エラーなし

- [ ] **Step 3: コミット**

```bash
git add claude-code-action/action.yaml
git commit -s -m "feat(claude-code-action): add owner authorization and default aws-role-arn"
```

---

### Task 4: `deploy-actions` に呼び出し側ワークフローを追加する

**Files:**
- Create: `deploy-actions/.github/workflows/claude-code-action.yaml`

- [ ] **Step 1: ディレクトリを作成**

```bash
cd /Users/takanokenichi/GitHub/panicboat/deploy-actions/.claude/worktrees/refactor/claude-code-action
mkdir -p .github/workflows
```

- [ ] **Step 2: ワークフローファイルを作成**

`.github/workflows/claude-code-action.yaml` を以下の内容で作成する：

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

- [ ] **Step 3: actionlint で検証**

```bash
actionlint .github/workflows/claude-code-action.yaml
```

Expected: エラーなし

- [ ] **Step 4: コミット**

```bash
git add .github/workflows/claude-code-action.yaml
git commit -s -m "feat: add claude-code-action caller workflow"
```

---

### Task 5: `deploy-actions` の PR を作成してマージする

**Files:**
- 対象: `deploy-actions` リポジトリ

- [ ] **Step 1: `deploy-actions` の GitHub App 設定を確認**

`deploy-actions` リポジトリの Settings → Secrets and variables で以下が設定されているか確認する：
- `vars.APP_ID` — GitHub App の App ID
- `secrets.APP_PRIVATE_KEY` — GitHub App の秘密鍵

未設定の場合は `platform` と同じ値を登録してから次のステップへ進む。

- [ ] **Step 2: ブランチをプッシュ**

```bash
cd /Users/takanokenichi/GitHub/panicboat/deploy-actions/.claude/worktrees/refactor/claude-code-action
git push -u origin refactor/claude-code-action
```

- [ ] **Step 3: PR を作成**

```bash
gh pr create \
  --repo panicboat/deploy-actions \
  --title "refactor: centralize authorization and aws-role-arn in action.yaml" \
  --body "## Summary
- \`action.yaml\` に \`Authorize\` ステップを追加（オーナー以外は \`exit 1\`）
- \`aws-role-arn\` をオプション化しデフォルト ARN を設定
- \`deploy-actions\` 自身の呼び出し側ワークフローを追加

## Test plan
- [ ] yamllint / actionlint でエラーなし確認済み
- [ ] \`vars.APP_ID\` と \`secrets.APP_PRIVATE_KEY\` が設定済み
- [ ] マージ後、他リポジトリの呼び出し側ワークフローを更新する"
```

- [ ] **Step 4: PR をマージ**

```bash
gh pr merge --repo panicboat/deploy-actions --squash
```

> **重要:** `platform` と `monorepo` の変更は、このマージ完了後に行うこと（呼び出し側は `@main` を参照するため）

- [ ] **Step 5: worktree を削除**

```bash
cd /Users/takanokenichi/GitHub/panicboat/deploy-actions
git worktree remove .claude/worktrees/refactor/claude-code-action
git worktree prune
```

---

### Task 6: `platform` の worktree を作成して呼び出し側を更新する

**Files:**
- 対象リポジトリ: `/Users/takanokenichi/GitHub/panicboat/platform`
- Modify: `platform/.github/workflows/claude-code-action.yaml`

- [ ] **Step 1: `.git/info/exclude` に worktree パスを追加**

```bash
cd /Users/takanokenichi/GitHub/panicboat/platform
grep -q '/.claude/worktrees/' .git/info/exclude || echo '/.claude/worktrees/' >> .git/info/exclude
```

- [ ] **Step 2: worktree を作成**

```bash
git worktree add -b refactor/claude-code-action .claude/worktrees/refactor/claude-code-action origin/main
```

- [ ] **Step 3: ワークフローファイルを更新**

`.claude/worktrees/refactor/claude-code-action/.github/workflows/claude-code-action.yaml` を以下の内容にする：

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

- [ ] **Step 4: actionlint で検証**

```bash
cd /Users/takanokenichi/GitHub/panicboat/platform/.claude/worktrees/refactor/claude-code-action
actionlint .github/workflows/claude-code-action.yaml
```

Expected: エラーなし

- [ ] **Step 5: コミットして PR を作成・マージ**

```bash
git add .github/workflows/claude-code-action.yaml
git commit -s -m "refactor: simplify claude-code-action caller workflow"
git push -u origin refactor/claude-code-action
gh pr create \
  --repo panicboat/platform \
  --title "refactor: simplify claude-code-action caller workflow" \
  --body "## Summary
- \`if\` 条件から \`CLOUD_CODE_ALLOWED_USERS\` 参照を削除（認可は \`action.yaml\` 側に移管）
- \`aws-role-arn\` を削除（\`action.yaml\` のデフォルト値を使用）

## Test plan
- [ ] actionlint でエラーなし確認済み
- [ ] deploy-actions の変更がマージ済みであること"
gh pr merge --repo panicboat/platform --squash
```

- [ ] **Step 6: worktree を削除**

```bash
cd /Users/takanokenichi/GitHub/panicboat/platform
git worktree remove .claude/worktrees/refactor/claude-code-action
git worktree prune
```

---

### Task 7: `monorepo` の worktree を作成して呼び出し側を更新する

**Files:**
- 対象リポジトリ: `/Users/takanokenichi/GitHub/panicboat/monorepo`
- Modify: `monorepo/.github/workflows/claude-code-action.yaml`

- [ ] **Step 1: `.git/info/exclude` に worktree パスを追加**

```bash
cd /Users/takanokenichi/GitHub/panicboat/monorepo
grep -q '/.claude/worktrees/' .git/info/exclude || echo '/.claude/worktrees/' >> .git/info/exclude
```

- [ ] **Step 2: worktree を作成**

```bash
git worktree add -b refactor/claude-code-action .claude/worktrees/refactor/claude-code-action origin/main
```

- [ ] **Step 3: ワークフローファイルを更新**

`.claude/worktrees/refactor/claude-code-action/.github/workflows/claude-code-action.yaml` を以下の内容にする（`platform` と同一）：

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

- [ ] **Step 4: actionlint で検証**

```bash
cd /Users/takanokenichi/GitHub/panicboat/monorepo/.claude/worktrees/refactor/claude-code-action
actionlint .github/workflows/claude-code-action.yaml
```

Expected: エラーなし

- [ ] **Step 5: コミットして PR を作成・マージ**

```bash
git add .github/workflows/claude-code-action.yaml
git commit -s -m "refactor: simplify claude-code-action caller workflow"
git push -u origin refactor/claude-code-action
gh pr create \
  --repo panicboat/monorepo \
  --title "refactor: simplify claude-code-action caller workflow" \
  --body "## Summary
- \`if\` 条件から \`CLOUD_CODE_ALLOWED_USERS\` 参照を削除（認可は \`action.yaml\` 側に移管）
- \`aws-role-arn\` を削除（\`action.yaml\` のデフォルト値を使用）

## Test plan
- [ ] actionlint でエラーなし確認済み
- [ ] deploy-actions の変更がマージ済みであること"
gh pr merge --repo panicboat/monorepo --squash
```

- [ ] **Step 6: worktree を削除**

```bash
cd /Users/takanokenichi/GitHub/panicboat/monorepo
git worktree remove .claude/worktrees/refactor/claude-code-action
git worktree prune
```

---

## Merge Order

```
Task 5 (deploy-actions) → Task 6 (platform) → Task 7 (monorepo)
```

Task 6・7 は Task 5 のマージ完了後に実行すること。`panicboat/deploy-actions/claude-code-action@main` を参照するため。
