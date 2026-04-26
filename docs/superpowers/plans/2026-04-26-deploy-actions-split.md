# Deploy Actions Split Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** `panicboat/deploy-actions` から個人用 wrapper 6 種を新規 `panicboat/panicboat-actions` に移し、`deploy-actions` は公開向けの `label-dispatcher` / `label-resolver` / `config-manager` に絞り込む。

**Architecture:** 4 リポジトリにまたがる移行（`platform` / `panicboat-actions`(新) / `monorepo` / `deploy-actions`）。Step 0 で Terragrunt から両リポジトリを管理対象化、Step 1 で `panicboat-actions` を初期化、Step 2 で consumer ワークフローを書き換え、Step 3 で `deploy-actions` をスリム化する。git history は引き継がず、各ディレクトリは作業ツリーコピーで移植。

**Tech Stack:** GitHub Actions (Composite Action) / Terragrunt + OpenTofu / Ruby / Renovate / GitHub CLI (`gh`)

---

## File Structure

### `platform/` リポジトリ

| File | Action | Purpose |
|---|---|---|
| `github/repository/envs/develop/deploy-actions.hcl` | Create | 既存 `deploy-actions` を Terragrunt 管理に追加 |
| `github/repository/envs/develop/panicboat-actions.hcl` | Create | 新規 `panicboat-actions` のリポジトリ定義 |
| `github/repository/envs/develop/terragrunt.hcl` | Modify | 上記 2 つを `repositories` map に登録 |
| `github/branch/envs/develop/panicboat-actions.hcl` | Create | branch protection 定義（既存 `deploy-actions.hcl` と同形式） |
| `github/branch/envs/develop/terragrunt.hcl` | Modify | 上記を `repositories` map に登録 |
| `.github/workflows/reusable--terragrunt-executor.yaml` | Modify | `uses:` を `panicboat/panicboat-actions/terragrunt@main` に書き換え |
| `.github/workflows/reusable--kubernetes-builder.yaml` | Modify | `uses:` を `panicboat/panicboat-actions/kubernetes@main` に書き換え |
| `.github/workflows/claude-code-action.yaml` | Modify | `uses:` を `panicboat/panicboat-actions/claude-code-action@main` に書き換え |
| `.github/workflows/auto-approve.yaml` | Modify | `uses:` を `panicboat/panicboat-actions/auto-approve@main` に書き換え |

### `panicboat-actions/` リポジトリ（新規）

| File | Action | Purpose |
|---|---|---|
| `auto-approve/action.yaml` | Create (copy) | `deploy-actions/auto-approve/action.yaml` のコピー |
| `claude-code-action/action.yaml` | Create (copy) | 同上 |
| `claude-code-action/README.md` | Create (copy) | 同上 |
| `container-builder/action.yaml` | Create (copy) | 同上 |
| `container-builder/README.md` | Create (copy) | 同上 |
| `container-cleaner/action.yaml` | Create (copy) | 同上 |
| `container-cleaner/README.md` | Create (copy) | 同上 |
| `kubernetes/action.yaml` | Create (copy) | 同上 |
| `kubernetes/README.md` | Create (copy) | 同上 |
| `terragrunt/action.yaml` | Create (copy) | 同上 |
| `terragrunt/parse-results.js` | Create (copy) | 同上 |
| `terragrunt/validate-working-directory.js` | Create (copy) | 同上 |
| `terragrunt/verify-aws-credentials.js` | Create (copy) | 同上 |
| `.github/CODEOWNERS` | Create (copy) | `deploy-actions/.github/CODEOWNERS` のコピー |
| `.github/renovate.json` | Create (copy) | `deploy-actions/.github/renovate.json` の完全コピー（terragrunt customManagers 含む） |
| `.github/workflows/auto-approve.yaml` | Create | `deploy-actions/.github/workflows/auto-approve.yaml` をコピーし `uses:` を panicboat-actions に書き換え |
| `.github/workflows/claude-code-action.yaml` | Create | 同上 |
| `README.md` | Create | 個人用 wrapper 集である旨を明記 |
| `README-ja.md` | Create | 同上の日本語版 |

### `monorepo/` リポジトリ

| File | Action | Purpose |
|---|---|---|
| `.github/workflows/reusable--terragrunt-executor.yaml` | Modify | `uses:` を `panicboat/panicboat-actions/terragrunt@main` に書き換え |
| `.github/workflows/reusable--kubernetes-builder.yaml` | Modify | `uses:` を `panicboat/panicboat-actions/kubernetes@main` に書き換え |
| `.github/workflows/claude-code-action.yaml` | Modify | `uses:` を `panicboat/panicboat-actions/claude-code-action@main` に書き換え |
| `.github/workflows/auto-approve.yaml` | Modify | `uses:` を `panicboat/panicboat-actions/auto-approve@main` に書き換え |
| `.github/workflows/reusable--container-builder.yaml` | Modify | `uses:` を `panicboat/panicboat-actions/container-builder@main` に書き換え |
| `.github/workflows/cleanup-container-image.yaml` | Modify | `uses:` を `panicboat/panicboat-actions/container-cleaner@main` に書き換え |

### `deploy-actions/` リポジトリ

| File | Action | Purpose |
|---|---|---|
| `auto-approve/` | Delete (recursive) | panicboat-actions に移動済み |
| `claude-code-action/` | Delete (recursive) | 同上 |
| `container-builder/` | Delete (recursive) | 同上 |
| `container-cleaner/` | Delete (recursive) | 同上 |
| `kubernetes/` | Delete (recursive) | 同上 |
| `terragrunt/` | Delete (recursive) | 同上 |
| `.github/workflows/auto-approve.yaml` | Delete | panicboat-actions に移動済み |
| `.github/workflows/claude-code-action.yaml` | Delete | 同上 |
| `.github/renovate.json` | Modify | terragrunt 関連 `customManagers` 2 件を削除 |
| `README.md` | Rewrite | label-dispatcher / label-resolver / config-manager 中心に再構成 |
| `README-ja.md` | Rewrite | 同上の日本語版 |

---

## Phase A: Step 0 — Terragrunt Repository Management

`platform/` リポジトリで作業します。すべてのコマンドは `platform/` のクローン直下から実行する想定です。worktree を切るかは利用者裁量。

### Task A1: Create `deploy-actions.hcl` for repository management

**Files:**
- Create: `platform/github/repository/envs/develop/deploy-actions.hcl`

- [ ] **Step 1: ファイル作成**

`platform/github/repository/envs/develop/deploy-actions.hcl` に以下を書く:

```hcl
locals {
  repository = {
    name        = "deploy-actions"
    description = "Generic deployment orchestration toolkit for multi-service GitHub Actions workflows."
    visibility  = "public"
    features = {
      issues   = true
      wiki     = false
      projects = true
    }
  }
}
```

- [ ] **Step 2: フォーマット確認**

```bash
cd platform/github/repository
make fmt
```

期待: `terraform fmt` がエラーなく終了。

- [ ] **Step 3: コミット**

```bash
cd platform
git add github/repository/envs/develop/deploy-actions.hcl
git commit -s -m "chore(github): add deploy-actions to repository management"
```

---

### Task A2: Create `panicboat-actions.hcl` for repository management

**Files:**
- Create: `platform/github/repository/envs/develop/panicboat-actions.hcl`

- [ ] **Step 1: ファイル作成**

`platform/github/repository/envs/develop/panicboat-actions.hcl` に以下を書く:

```hcl
locals {
  repository = {
    name        = "panicboat-actions"
    description = "Personal-use GitHub Actions wrappers for panicboat infrastructure."
    visibility  = "public"
    features = {
      issues   = true
      wiki     = false
      projects = true
    }
  }
}
```

- [ ] **Step 2: フォーマット確認**

```bash
cd platform/github/repository
make fmt
```

- [ ] **Step 3: コミット**

```bash
cd platform
git add github/repository/envs/develop/panicboat-actions.hcl
git commit -s -m "chore(github): add panicboat-actions to repository management"
```

---

### Task A3: Update `repository/envs/develop/terragrunt.hcl`

**Files:**
- Modify: `platform/github/repository/envs/develop/terragrunt.hcl`

- [ ] **Step 1: ファイル書き換え**

`platform/github/repository/envs/develop/terragrunt.hcl` の `locals` と `inputs.repositories` を以下のように更新:

```hcl
include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../modules"
}

locals {
  monorepo          = read_terragrunt_config("monorepo.hcl")
  platform          = read_terragrunt_config("platform.hcl")
  deploy_actions    = read_terragrunt_config("deploy-actions.hcl")
  panicboat_actions = read_terragrunt_config("panicboat-actions.hcl")
}

inputs = {
  repositories = {
    monorepo          = local.monorepo.locals.repository
    platform          = local.platform.locals.repository
    deploy-actions    = local.deploy_actions.locals.repository
    panicboat-actions = local.panicboat_actions.locals.repository
  }
  github_token = get_env("GITHUB_TOKEN")
}
```

- [ ] **Step 2: validate**

```bash
cd platform/github/repository
make validate
```

期待: validation エラーなし。

- [ ] **Step 3: plan**

```bash
cd platform/github/repository
make plan
```

期待: `deploy-actions` と `panicboat-actions` の両方が "create" として出る（まだ state にも実体にも存在しないため）。

- [ ] **Step 4: コミット**

```bash
cd platform
git add github/repository/envs/develop/terragrunt.hcl
git commit -s -m "chore(github): wire deploy-actions and panicboat-actions into repository terragrunt"
```

---

### Task A4: Create `panicboat-actions.hcl` for branch protection

**Files:**
- Create: `platform/github/branch/envs/develop/panicboat-actions.hcl`

- [ ] **Step 1: ファイル作成**

既存の `deploy-actions.hcl` と同形式で `platform/github/branch/envs/develop/panicboat-actions.hcl` を作成:

```hcl
locals {
  defaults = read_terragrunt_config("defaults.hcl")

  repository = {
    name              = "panicboat-actions"
    branch_protection = local.defaults.locals.branch_protection
  }
}
```

- [ ] **Step 2: フォーマット確認**

```bash
cd platform/github/branch
make fmt
```

- [ ] **Step 3: コミット**

```bash
cd platform
git add github/branch/envs/develop/panicboat-actions.hcl
git commit -s -m "chore(github): add panicboat-actions to branch protection"
```

---

### Task A5: Update `branch/envs/develop/terragrunt.hcl`

**Files:**
- Modify: `platform/github/branch/envs/develop/terragrunt.hcl`

- [ ] **Step 1: ファイル書き換え**

```hcl
include "root" {
  path = find_in_parent_folders("root.hcl")
}

terraform {
  source = "../../modules"
}

locals {
  monorepo          = read_terragrunt_config("monorepo.hcl")
  platform          = read_terragrunt_config("platform.hcl")
  deploy_actions    = read_terragrunt_config("deploy-actions.hcl")
  panicboat_actions = read_terragrunt_config("panicboat-actions.hcl")
}

inputs = {
  repositories = {
    monorepo          = local.monorepo.locals.repository
    platform          = local.platform.locals.repository
    deploy-actions    = local.deploy_actions.locals.repository
    panicboat-actions = local.panicboat_actions.locals.repository
  }
  github_token = get_env("GITHUB_TOKEN")
}
```

- [ ] **Step 2: plan**

```bash
cd platform/github/branch
make plan
```

期待: `panicboat-actions` 用の branch protection rule が "create" として出る。`deploy-actions` 等の既存分は変更なしであるべき。

- [ ] **Step 3: コミット**

```bash
cd platform
git add github/branch/envs/develop/terragrunt.hcl
git commit -s -m "chore(github): wire panicboat-actions into branch protection terragrunt"
```

---

### Task A6: Open Draft PR for Phase A

- [ ] **Step 1: push & PR**

ブランチが新規の場合:

```bash
cd platform
git push -u origin HEAD
gh pr create --draft --title "chore(github): manage deploy-actions and panicboat-actions via terragrunt" --body "$(cat <<'EOF'
## Summary

- 既存 `deploy-actions` と新規 `panicboat-actions` を `github/repository/` の Terragrunt 管理下に追加
- `panicboat-actions` を `github/branch/` の Terragrunt 管理下に追加

## Test plan

- [ ] `make plan`（repository, branch 両方）が想定どおりの diff を出すことを確認
- [ ] マージ後に `terragrunt import` で既存 deploy-actions を取り込み、`make plan` が clean になることを確認
- [ ] `make apply` で panicboat-actions が新規作成されることを確認
EOF
)"
```

- [ ] **Step 2: レビューが揃ったら Ready for review に変更してマージ**

---

### Task A7: Manual ops — import & apply

Phase A の PR がマージされたあと、ローカルで実行する手動オペレーションです。AWS 認証情報と `GITHUB_TOKEN` が必要。

- [ ] **Step 1: main を pull**

```bash
cd platform
git checkout main
git pull origin main
```

- [ ] **Step 2: 既存 `deploy-actions` を repository state に import**

```bash
cd platform/github/repository/envs/develop
terragrunt import 'github_repository.repository["deploy-actions"]' deploy-actions
```

期待: `Import successful!` が出る。

- [ ] **Step 3: drift 確認**

```bash
cd platform/github/repository
make plan
```

期待: `panicboat-actions` のみ "create" として残り、`deploy-actions` は "no changes" もしくは想定内の差分のみ。差分が出る場合は `deploy-actions.hcl` を実態に合わせて調整し、Phase A の PR を follow-up で更新する（または別 PR を切る）。

- [ ] **Step 4: apply**

```bash
cd platform/github/repository
make apply
```

期待: `panicboat-actions` リポジトリが GitHub 上に空で作成される。

- [ ] **Step 5: GitHub 上で空リポジトリの存在を確認**

```bash
gh repo view panicboat/panicboat-actions
```

期待: リポジトリ情報が表示される（空、`main` ブランチは未作成）。

注: branch protection の apply は Phase B で `main` ブランチが bootstrap されたあと、Task B8 で実行する。空リポジトリ状態で `make apply` すると、`main` ブランチ不在でエラーになる（または無音で失敗する）可能性があるため。

---

## Phase B: Step 1 — Initialize `panicboat-actions` Content

新規作成された空の `panicboat-actions` リポジトリに、6 ディレクトリと `.github/` 一式を投入する。Phase A Task A7 完了が前提。

### Task B1: Clone the empty repo locally

注: この時点で `panicboat-actions` は空（`main` ブランチも未作成）。Phase B では `main` ブランチを直接 bootstrap し、コンテンツ投入後に Task B8 で branch protection を apply する流れにする。

- [ ] **Step 1: clone**

```bash
cd ~/GitHub/panicboat
git clone https://github.com/panicboat/panicboat-actions.git
cd panicboat-actions
```

期待: `warning: You appear to have cloned an empty repository.` が出る。

- [ ] **Step 2: ローカル `main` ブランチを作成**

```bash
git checkout -b main
```

---

### Task B2: Copy 6 wrapper directories from deploy-actions

**Files:**
- Create: `auto-approve/`, `claude-code-action/`, `container-builder/`, `container-cleaner/`, `kubernetes/`, `terragrunt/`（すべて `deploy-actions/` から再帰コピー）

- [ ] **Step 1: コピー実行**

```bash
cd ~/GitHub/panicboat/panicboat-actions
SRC=~/GitHub/panicboat/deploy-actions
cp -R "$SRC/auto-approve" .
cp -R "$SRC/claude-code-action" .
cp -R "$SRC/container-builder" .
cp -R "$SRC/container-cleaner" .
cp -R "$SRC/kubernetes" .
cp -R "$SRC/terragrunt" .
```

- [ ] **Step 2: コピー結果を確認**

```bash
ls -la auto-approve claude-code-action container-builder container-cleaner kubernetes terragrunt
```

期待: 各ディレクトリに `action.yaml` などの想定ファイルが揃っていること。

- [ ] **Step 3: コミット**

```bash
git add auto-approve claude-code-action container-builder container-cleaner kubernetes terragrunt
git commit -s -m "feat: import composite actions from deploy-actions"
```

---

### Task B3: Copy `.github/CODEOWNERS` and `.github/renovate.json`

**Files:**
- Create: `.github/CODEOWNERS`
- Create: `.github/renovate.json`（terragrunt customManagers 含む完全コピー）

- [ ] **Step 1: コピー**

```bash
cd ~/GitHub/panicboat/panicboat-actions
mkdir -p .github
cp ~/GitHub/panicboat/deploy-actions/.github/CODEOWNERS .github/CODEOWNERS
cp ~/GitHub/panicboat/deploy-actions/.github/renovate.json .github/renovate.json
```

- [ ] **Step 2: 内容確認**

`.github/renovate.json` に以下 2 件の `customManagers` が含まれていること:

- `Track OpenTofu version pinned in terragrunt composite action`
- `Track Terragrunt version pinned in terragrunt composite action`

両方とも `fileMatch` が `^terragrunt/action\.yaml$` のままで OK（panicboat-actions 側でも同じパス）。

- [ ] **Step 3: コミット**

```bash
git add .github/CODEOWNERS .github/renovate.json
git commit -s -m "chore: copy CODEOWNERS and renovate config from deploy-actions"
```

---

### Task B4: Add `auto-approve` workflow

**Files:**
- Create: `.github/workflows/auto-approve.yaml`

- [ ] **Step 1: コピー**

```bash
mkdir -p .github/workflows
cp ~/GitHub/panicboat/deploy-actions/.github/workflows/auto-approve.yaml .github/workflows/auto-approve.yaml
```

- [ ] **Step 2: `uses:` を書き換え**

`.github/workflows/auto-approve.yaml` 内の `panicboat/deploy-actions/auto-approve@main` を `panicboat/panicboat-actions/auto-approve@main` に置換（該当行のみ）。

確認:

```bash
grep -n 'panicboat/' .github/workflows/auto-approve.yaml
```

期待: `panicboat/panicboat-actions/auto-approve@main` のみが残ること。

- [ ] **Step 3: コミット**

```bash
git add .github/workflows/auto-approve.yaml
git commit -s -m "ci: add auto-approve workflow referencing panicboat-actions"
```

---

### Task B5: Add `claude-code-action` workflow

**Files:**
- Create: `.github/workflows/claude-code-action.yaml`

- [ ] **Step 1: コピー**

```bash
cp ~/GitHub/panicboat/deploy-actions/.github/workflows/claude-code-action.yaml .github/workflows/claude-code-action.yaml
```

- [ ] **Step 2: `uses:` を書き換え**

`.github/workflows/claude-code-action.yaml` 内の `panicboat/deploy-actions/claude-code-action@main` を `panicboat/panicboat-actions/claude-code-action@main` に置換。

確認:

```bash
grep -n 'panicboat/' .github/workflows/claude-code-action.yaml
```

期待: `panicboat/panicboat-actions/claude-code-action@main` のみ。

- [ ] **Step 3: コミット**

```bash
git add .github/workflows/claude-code-action.yaml
git commit -s -m "ci: add claude-code-action workflow referencing panicboat-actions"
```

---

### Task B6: Write README files

**Files:**
- Create: `README.md`
- Create: `README-ja.md`

- [ ] **Step 1: `README.md` を作成**

`README.md` に以下を書く:

```markdown
# panicboat-actions

**English** | [🇯🇵 日本語](README-ja.md)

Personal-use GitHub Actions composite wrappers for panicboat infrastructure.

## Overview

This repository hosts composite actions tailored to the maintainer's environments. Anyone is free to read or fork them, but the wrappers embed assumptions specific to panicboat's AWS account, IAM roles, and deployment conventions, so they are not designed for general consumption.

## Available actions

- `auto-approve/` — Auto-approve and merge bot PRs.
- `claude-code-action/` — Run Claude Code via AWS Bedrock for repository automation.
- `container-builder/` — Build and push container images to GHCR.
- `container-cleaner/` — Clean up untagged container images on GHCR.
- `kubernetes/` — Build kustomize overlays and post diff as a PR comment.
- `terragrunt/` — Execute Terragrunt plan/apply with AWS OIDC.

## Related

- [panicboat/deploy-actions](https://github.com/panicboat/deploy-actions) — Generic deployment orchestration (label-dispatcher, label-resolver, config-manager) reused as upstream.
```

- [ ] **Step 2: `README-ja.md` を作成**

`README-ja.md` に以下を書く:

```markdown
# panicboat-actions

[🇺🇸 English](README.md) | **日本語**

panicboat の環境向けに作った個人用 GitHub Actions composite wrapper 集。

## 概要

メンテナーの環境（panicboat の AWS アカウント、IAM ロール、デプロイ規約）を前提とした composite action を集めたリポジトリ。誰でも読んだり fork したりできますが、汎用的な利用は想定していません。

## 提供 Action

- `auto-approve/` — bot 由来の PR を自動 approve / merge
- `claude-code-action/` — AWS Bedrock 経由で Claude Code を実行
- `container-builder/` — GHCR にコンテナイメージを build & push
- `container-cleaner/` — GHCR の untagged コンテナイメージを掃除
- `kubernetes/` — kustomize overlay を build して PR に diff をコメント
- `terragrunt/` — AWS OIDC で Terragrunt の plan/apply を実行

## 関連

- [panicboat/deploy-actions](https://github.com/panicboat/deploy-actions) — 汎用デプロイメント・オーケストレーション（label-dispatcher / label-resolver / config-manager）。本リポジトリの上流として利用される。
```

- [ ] **Step 3: コミット**

```bash
git add README.md README-ja.md
git commit -s -m "docs: add bilingual README"
```

---

### Task B7: Bootstrap push to `main`

注: この時点で `panicboat-actions` には branch protection が未設定なので `main` への直接 push が可能。Task B8 で branch protection を apply したあとは、以降の変更は通常通り PR 経由になる。

- [ ] **Step 1: push（初回 -u、main ブランチ作成）**

```bash
git push -u origin main
```

期待: ローカル `main` がリモートの `main` として作成され、tracking 設定される。

- [ ] **Step 2: GitHub 上で確認**

```bash
gh repo view panicboat/panicboat-actions --web
```

期待: README が表示され、6 つの Composite Action ディレクトリと `.github/` が見える。

---

### Task B8: Apply branch protection

`panicboat-actions:main` が存在するようになったので、Phase A で準備済みの branch protection を apply する。`platform/` リポジトリでローカル実行。

- [ ] **Step 1: plan で再確認**

```bash
cd ~/GitHub/panicboat/platform/github/branch
make plan
```

期待: `panicboat-actions` の branch protection rule（`main` ブランチ用）が "create" として出る。

- [ ] **Step 2: apply**

```bash
make apply
```

期待: branch protection rule が作成される。エラーが出る場合は `panicboat-actions:main` の存在を再確認。

- [ ] **Step 3: GitHub 上で branch protection を確認**

```bash
gh api repos/panicboat/panicboat-actions/branches/main/protection 2>/dev/null | head -20
```

期待: protection rule が JSON で返ってくる（404 の場合は apply が反映されていない）。

---

## Phase C: Step 2 — Rewrite Consumer Workflows

Phase B の `panicboat-actions` が main にマージされ、`@main` 参照が解決可能になった状態が前提。

### Task C1: Update `platform/` workflows

**Files:**
- Modify: `platform/.github/workflows/reusable--terragrunt-executor.yaml`
- Modify: `platform/.github/workflows/reusable--kubernetes-builder.yaml`
- Modify: `platform/.github/workflows/claude-code-action.yaml`
- Modify: `platform/.github/workflows/auto-approve.yaml`

- [ ] **Step 1: ブランチ作成**

```bash
cd ~/GitHub/panicboat/platform
git checkout main && git pull origin main
git checkout -b refactor/panicboat-actions-references origin/main
```

- [ ] **Step 2: 4 ファイルの参照置換**

各ファイルで以下の文字列を置換:

| ファイル | 旧 | 新 |
|---|---|---|
| `.github/workflows/reusable--terragrunt-executor.yaml` | `panicboat/deploy-actions/terragrunt@main` | `panicboat/panicboat-actions/terragrunt@main` |
| `.github/workflows/reusable--kubernetes-builder.yaml` | `panicboat/deploy-actions/kubernetes@main` | `panicboat/panicboat-actions/kubernetes@main` |
| `.github/workflows/claude-code-action.yaml` | `panicboat/deploy-actions/claude-code-action@main` | `panicboat/panicboat-actions/claude-code-action@main` |
| `.github/workflows/auto-approve.yaml` | `panicboat/deploy-actions/auto-approve@main` | `panicboat/panicboat-actions/auto-approve@main` |

各ファイルを Edit ツールで該当行のみ置換。

- [ ] **Step 3: 残存確認**

```bash
grep -rn 'panicboat/deploy-actions/' .github/workflows
```

期待: `label-dispatcher` と `label-resolver` の 2 件だけが残ること。

- [ ] **Step 4: コミット & PR**

```bash
git add .github/workflows/reusable--terragrunt-executor.yaml \
        .github/workflows/reusable--kubernetes-builder.yaml \
        .github/workflows/claude-code-action.yaml \
        .github/workflows/auto-approve.yaml
git commit -s -m "refactor(workflows): switch personal wrappers to panicboat-actions"
git push -u origin HEAD
gh pr create --draft --title "refactor(workflows): switch personal wrappers to panicboat-actions" --body "$(cat <<'EOF'
## Summary

terragrunt / kubernetes / claude-code-action / auto-approve の `uses:` を `panicboat/panicboat-actions/...@main` に切り替え。

## Test plan

- [ ] PR 上で全 workflow の CI が通ることを確認
- [ ] `grep -rn panicboat/deploy-actions/ .github/workflows` で label-dispatcher / label-resolver のみ残ることを確認
EOF
)"
```

- [ ] **Step 5: ready & merge**

---

### Task C2: Update `monorepo/` workflows

**Files:**
- Modify: `monorepo/.github/workflows/reusable--terragrunt-executor.yaml`
- Modify: `monorepo/.github/workflows/reusable--kubernetes-builder.yaml`
- Modify: `monorepo/.github/workflows/claude-code-action.yaml`
- Modify: `monorepo/.github/workflows/auto-approve.yaml`
- Modify: `monorepo/.github/workflows/reusable--container-builder.yaml`
- Modify: `monorepo/.github/workflows/cleanup-container-image.yaml`

- [ ] **Step 1: ブランチ作成**

```bash
cd ~/GitHub/panicboat/monorepo
git checkout main && git pull origin main
git checkout -b refactor/panicboat-actions-references origin/main
```

- [ ] **Step 2: 6 ファイルの参照置換**

| ファイル | 旧 | 新 |
|---|---|---|
| `.github/workflows/reusable--terragrunt-executor.yaml` | `panicboat/deploy-actions/terragrunt@main` | `panicboat/panicboat-actions/terragrunt@main` |
| `.github/workflows/reusable--kubernetes-builder.yaml` | `panicboat/deploy-actions/kubernetes@main` | `panicboat/panicboat-actions/kubernetes@main` |
| `.github/workflows/claude-code-action.yaml` | `panicboat/deploy-actions/claude-code-action@main` | `panicboat/panicboat-actions/claude-code-action@main` |
| `.github/workflows/auto-approve.yaml` | `panicboat/deploy-actions/auto-approve@main` | `panicboat/panicboat-actions/auto-approve@main` |
| `.github/workflows/reusable--container-builder.yaml` | `panicboat/deploy-actions/container-builder@main` | `panicboat/panicboat-actions/container-builder@main` |
| `.github/workflows/cleanup-container-image.yaml` | `panicboat/deploy-actions/container-cleaner@main` | `panicboat/panicboat-actions/container-cleaner@main` |

なお `.github/workflows/auto-label--deploy-trigger.yaml` には `panicboat/deploy-actions/container-cleaner@main` を参照するコメント行（`#     - uses: ...`）があるが、コメント済みのため対象外（必要なら同 PR で同様に書き換えてもよい）。

- [ ] **Step 3: 残存確認**

```bash
grep -rn 'panicboat/deploy-actions/' .github/workflows
```

期待: `label-dispatcher` / `label-resolver` 参照、および `auto-label--deploy-trigger.yaml` 内のコメント行（任意）のみが残る。

- [ ] **Step 4: コミット & PR**

```bash
git add .github/workflows/
git commit -s -m "refactor(workflows): switch personal wrappers to panicboat-actions"
git push -u origin HEAD
gh pr create --draft --title "refactor(workflows): switch personal wrappers to panicboat-actions" --body "$(cat <<'EOF'
## Summary

terragrunt / kubernetes / claude-code-action / auto-approve / container-builder / container-cleaner の `uses:` を `panicboat/panicboat-actions/...@main` に切り替え。

## Test plan

- [ ] PR 上で全 workflow の CI が通ることを確認
- [ ] `grep -rn panicboat/deploy-actions/ .github/workflows` で label-dispatcher / label-resolver のみ残ることを確認
EOF
)"
```

- [ ] **Step 5: ready & merge**

---

## Phase D: Step 3 — Slim Down `deploy-actions`

Phase C 両 PR がマージされ、`panicboat/deploy-actions/{terragrunt,kubernetes,claude-code-action,auto-approve,container-builder,container-cleaner}` への参照が consumer 側から消えたあとに実行。

このリポジトリの worktree（`refactor/split-personal-actions`）で作業する。本 plan / spec のコミットが既にこのブランチにあるため、Phase D はそのまま続けて積む。

### Task D1: Delete 6 wrapper directories

**Files:**
- Delete: `auto-approve/`, `claude-code-action/`, `container-builder/`, `container-cleaner/`, `kubernetes/`, `terragrunt/`

- [ ] **Step 1: 削除**

```bash
cd ~/GitHub/panicboat/deploy-actions/.claude/worktrees/refactor/split-personal-actions
git rm -r auto-approve claude-code-action container-builder container-cleaner kubernetes terragrunt
```

- [ ] **Step 2: 残存ファイル確認**

```bash
ls -la
```

期待: トップレベルに `action-scripts/`, `label-dispatcher/`, `label-resolver/`, `README.md`, `README-ja.md`, `.github/` が残ること（および他の既存メタファイル）。

- [ ] **Step 3: コミット**

```bash
git commit -s -m "refactor: remove personal-use wrappers (moved to panicboat-actions)"
```

---

### Task D2: Delete relocated workflow files

**Files:**
- Delete: `.github/workflows/auto-approve.yaml`
- Delete: `.github/workflows/claude-code-action.yaml`

- [ ] **Step 1: 削除**

```bash
git rm .github/workflows/auto-approve.yaml .github/workflows/claude-code-action.yaml
```

- [ ] **Step 2: 残存確認**

```bash
ls .github/workflows
```

期待: 空、もしくは（将来的に追加された公開向け CI のみ）。

- [ ] **Step 3: コミット**

```bash
git commit -s -m "ci: remove auto-approve and claude-code-action workflows (moved to panicboat-actions)"
```

---

### Task D3: Trim `renovate.json` customManagers

**Files:**
- Modify: `.github/renovate.json`

- [ ] **Step 1: customManagers セクションから 2 件削除**

`.github/renovate.json` の `customManagers` 配列から以下 2 件を削除する:

- `description: "Track OpenTofu version pinned in terragrunt composite action"`（fileMatch が `^terragrunt/action\.yaml$`）
- `description: "Track Terragrunt version pinned in terragrunt composite action"`（fileMatch が `^terragrunt/action\.yaml$`）

両方を削除した結果、`customManagers` 配列が空になるなら、配列ごと削除して構わない。

- [ ] **Step 2: JSON 妥当性確認**

```bash
python3 -m json.tool .github/renovate.json > /dev/null && echo "valid JSON"
```

期待: `valid JSON` と出力。

- [ ] **Step 3: 残存確認**

```bash
grep -n 'terragrunt' .github/renovate.json || echo "no terragrunt references"
```

期待: `no terragrunt references`（もしくは関連する記述が完全に消えていること）。

- [ ] **Step 4: コミット**

```bash
git add .github/renovate.json
git commit -s -m "chore(renovate): drop terragrunt custom managers (moved to panicboat-actions)"
```

---

### Task D4: Rewrite `README.md`

**Files:**
- Modify: `README.md`

- [ ] **Step 1: README.md を以下の内容で全置換**

```markdown
# Deploy Actions

**English** | [🇯🇵 日本語](README-ja.md)

A GitHub Actions toolkit that drives PR-label-based deployment orchestration for multi-service repositories.

## Overview

Deploy Actions converts file changes into deployment labels and converts those labels into structured deployment targets. The toolkit handles the change-detection and target-resolution layer; the actual `plan`/`apply` execution is delegated to whatever Composite Action the consumer wires in (Terragrunt, Helm, kustomize, etc.).

## Components

### 1. Config Manager (`action-scripts/config-manager/`)

Validates and manages the `workflow-config.yaml` that defines environments, services, and directory conventions.

**Highlights:**

- Configuration validation with detailed error reporting
- Environment and service management
- Directory-convention validation
- Template generation

### 2. Label Dispatcher (`label-dispatcher/`)

Detects file changes from a PR and creates `deploy:<service>` labels for affected services.

**Highlights:**

- Change detection from `git diff`
- Service discovery from directory patterns
- Automatic label generation
- Exclusion handling

### 3. Label Resolver (`label-resolver/`)

Translates `deploy:<service>` labels and branch context into a deployment-target matrix that downstream actions consume.

**Highlights:**

- Label-to-target resolution
- Environment detection from branch
- Deployment-matrix generation
- Safety validation

## Composite Actions

### Label Dispatcher

```yaml
- uses: panicboat/deploy-actions/label-dispatcher@main
  with:
    pr-number: ${{ github.event.pull_request.number }}
    repository: ${{ github.repository }}
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

### Label Resolver

```yaml
- uses: panicboat/deploy-actions/label-resolver@main
  with:
    action-type: plan  # or apply
    pr-number: ${{ github.event.pull_request.number }}
    repository: ${{ github.repository }}
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

## Configuration

The toolkit reads `workflow-config.yaml`:

```yaml
environments:
  - environment: develop
    aws_region: ap-northeast-1
    iam_role_plan: arn:aws:iam::ACCOUNT:role/plan-role
    iam_role_apply: arn:aws:iam::ACCOUNT:role/apply-role

directory_conventions:
  - root: "{service}"
    stacks:
      - name: terragrunt
        directory: "terragrunt/{environment}"
      - name: kubernetes
        directory: "kubernetes/overlays/{environment}"

services:
  - name: excluded-service
    exclude_from_automation: true
    exclusion_config:
      reason: "Manual deployment required"
      type: "permanent"

branch_patterns:
  develop: develop
  staging: staging
  production: production
```

See `action-scripts/workflow-config.yaml` for a runnable sample.

## Workflow integration

### 1. Change-detection workflow

```yaml
name: Detect Changes and Create Labels
on:
  pull_request:
    types: [opened, synchronize, reopened]

jobs:
  detect-changes:
    runs-on: ubuntu-latest
    steps:
      - uses: panicboat/deploy-actions/label-dispatcher@main
        with:
          pr-number: ${{ github.event.pull_request.number }}
          repository: ${{ github.repository }}
          github-token: ${{ secrets.GITHUB_TOKEN }}
```

### 2. Deployment-target resolution

```yaml
name: Deploy
on:
  pull_request:
    types: [labeled]

jobs:
  plan:
    runs-on: ubuntu-latest
    if: contains(github.event.label.name, 'deploy:')
    steps:
      - id: resolve
        uses: panicboat/deploy-actions/label-resolver@main
        with:
          action-type: plan
          pr-number: ${{ github.event.pull_request.number }}
          repository: ${{ github.repository }}
          github-token: ${{ secrets.GITHUB_TOKEN }}

      # Then run your own deploy step using ${{ steps.resolve.outputs.deployment-targets }}
```

The execution layer (`terragrunt`, `kubernetes`, etc.) is intentionally not part of this repository — the maintainer's personal wrappers live at [`panicboat/panicboat-actions`](https://github.com/panicboat/panicboat-actions).

## Development

### Prerequisites

- Ruby 3.4+
- Bundler
- Git

### Setup

```bash
git clone https://github.com/panicboat/deploy-actions.git
cd deploy-actions/action-scripts
bundle install
bundle exec rspec
```

### Testing individual components

```bash
bundle exec ruby config-manager/bin/config-manager validate
bundle exec ruby label-dispatcher/bin/dispatcher detect
bundle exec ruby label-resolver/bin/resolver resolve PR_NUMBER
```

## License

MIT — see `LICENSE`.
```

- [ ] **Step 2: コミット**

```bash
git add README.md
git commit -s -m "docs: rewrite README around label-dispatcher / label-resolver / config-manager"
```

---

### Task D5: Rewrite `README-ja.md`

**Files:**
- Modify: `README-ja.md`

- [ ] **Step 1: README-ja.md を以下の内容で全置換**

```markdown
# Deploy Actions

[🇺🇸 English](README.md) | **日本語**

複数サービスを抱えるリポジトリで、PR ラベルベースのデプロイメント・オーケストレーションを駆動する GitHub Actions ツールキット。

## 概要

ファイル変更からデプロイ対象ラベルを生成し、ラベルからデプロイメント・ターゲットを解決する層を提供します。実際の `plan`/`apply` 実行は、利用側で任意の Composite Action（Terragrunt / Helm / kustomize など）に委ねる構成です。

## コンポーネント

### 1. Config Manager (`action-scripts/config-manager/`)

`workflow-config.yaml` を検証・管理。環境・サービス・ディレクトリ規約を定義します。

**特徴:**

- 詳細なエラーレポート付きの設定検証
- 環境とサービスの管理
- ディレクトリ規約の検証
- テンプレート生成

### 2. Label Dispatcher (`label-dispatcher/`)

PR の変更ファイルを検出し、変更があったサービスに対して `deploy:<service>` ラベルを付与します。

**特徴:**

- `git diff` からの変更検出
- ディレクトリ パターンからのサービス発見
- 自動ラベル生成
- 除外処理

### 3. Label Resolver (`label-resolver/`)

`deploy:<service>` ラベルとブランチ情報を、後続 Action が利用するデプロイメント・ターゲットの matrix に変換します。

**特徴:**

- ラベルからターゲットへの解決
- ブランチからの環境検出
- デプロイメント matrix 生成
- 安全性検証

## Composite Actions

### Label Dispatcher

```yaml
- uses: panicboat/deploy-actions/label-dispatcher@main
  with:
    pr-number: ${{ github.event.pull_request.number }}
    repository: ${{ github.repository }}
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

### Label Resolver

```yaml
- uses: panicboat/deploy-actions/label-resolver@main
  with:
    action-type: plan  # or apply
    pr-number: ${{ github.event.pull_request.number }}
    repository: ${{ github.repository }}
    github-token: ${{ secrets.GITHUB_TOKEN }}
```

## 設定

`workflow-config.yaml` を読み込みます。

```yaml
environments:
  - environment: develop
    aws_region: ap-northeast-1
    iam_role_plan: arn:aws:iam::ACCOUNT:role/plan-role
    iam_role_apply: arn:aws:iam::ACCOUNT:role/apply-role

directory_conventions:
  - root: "{service}"
    stacks:
      - name: terragrunt
        directory: "terragrunt/{environment}"
      - name: kubernetes
        directory: "kubernetes/overlays/{environment}"

services:
  - name: excluded-service
    exclude_from_automation: true
    exclusion_config:
      reason: "手動デプロイが必要"
      type: "permanent"

branch_patterns:
  develop: develop
  staging: staging
  production: production
```

実行可能なサンプルは `action-scripts/workflow-config.yaml` を参照してください。

## ワークフロー統合

### 1. 変更検出

```yaml
name: Detect Changes and Create Labels
on:
  pull_request:
    types: [opened, synchronize, reopened]

jobs:
  detect-changes:
    runs-on: ubuntu-latest
    steps:
      - uses: panicboat/deploy-actions/label-dispatcher@main
        with:
          pr-number: ${{ github.event.pull_request.number }}
          repository: ${{ github.repository }}
          github-token: ${{ secrets.GITHUB_TOKEN }}
```

### 2. デプロイ ターゲット解決

```yaml
name: Deploy
on:
  pull_request:
    types: [labeled]

jobs:
  plan:
    runs-on: ubuntu-latest
    if: contains(github.event.label.name, 'deploy:')
    steps:
      - id: resolve
        uses: panicboat/deploy-actions/label-resolver@main
        with:
          action-type: plan
          pr-number: ${{ github.event.pull_request.number }}
          repository: ${{ github.repository }}
          github-token: ${{ secrets.GITHUB_TOKEN }}

      # 以降は ${{ steps.resolve.outputs.deployment-targets }} を任意の deploy step に流す
```

実行レイヤ（`terragrunt`, `kubernetes` など）は意図的に本リポジトリから除外しています。メンテナーの個人用 wrapper は [`panicboat/panicboat-actions`](https://github.com/panicboat/panicboat-actions) にあります。

## 開発

### 前提条件

- Ruby 3.4+
- Bundler
- Git

### セットアップ

```bash
git clone https://github.com/panicboat/deploy-actions.git
cd deploy-actions/action-scripts
bundle install
bundle exec rspec
```

### コンポーネント別テスト

```bash
bundle exec ruby config-manager/bin/config-manager validate
bundle exec ruby label-dispatcher/bin/dispatcher detect
bundle exec ruby label-resolver/bin/resolver resolve PR_NUMBER
```

## License

MIT — `LICENSE` を参照。
```

- [ ] **Step 2: コミット**

```bash
git add README-ja.md
git commit -s -m "docs: rewrite README-ja around label-dispatcher / label-resolver / config-manager"
```

---

### Task D6: Push & open PR

- [ ] **Step 1: push**

```bash
git push -u origin HEAD
```

- [ ] **Step 2: PR 作成**

```bash
gh pr create --draft --title "refactor: slim down to label-dispatcher / label-resolver / config-manager" --body "$(cat <<'EOF'
## Summary

- 6 個の personal-use composite action（auto-approve / claude-code-action / container-builder / container-cleaner / kubernetes / terragrunt）を `panicboat-actions` へ移したのに伴いディレクトリを削除
- `.github/workflows/{auto-approve,claude-code-action}.yaml` を削除（同様に panicboat-actions へ移動）
- `.github/renovate.json` から terragrunt 関連 customManagers を削除
- README / README-ja を label-dispatcher / label-resolver / config-manager 中心に書き直し

## Test plan

- [ ] `panicboat-actions` 側 `@main` への切替が consumer 側 PR (`platform`, `monorepo`) でマージ済みであること
- [ ] `gh search code` で `panicboat/deploy-actions/(terragrunt|kubernetes|claude-code-action|auto-approve|container-builder|container-cleaner)@main` 参照が外部リポジトリに残っていないことを確認（自社管理の範囲）
- [ ] CI が緑になることを確認（spec / RSpec）
EOF
)"
```

- [ ] **Step 3: ready & merge**

---

## Phase E: Verification

### Task E1: Cross-repo CI verification

- [ ] **Step 1: `platform/` 直近 PR の CI が緑**

```bash
cd ~/GitHub/panicboat/platform
gh pr list --limit 5
gh pr checks <merged-PR-number>
```

期待: 全 check 緑。

- [ ] **Step 2: `monorepo/` 直近 PR の CI が緑**

```bash
cd ~/GitHub/panicboat/monorepo
gh pr list --limit 5
gh pr checks <merged-PR-number>
```

期待: 全 check 緑。

- [ ] **Step 3: `panicboat-actions/` の CI が緑**

```bash
cd ~/GitHub/panicboat/panicboat-actions
gh run list --limit 5
```

期待: `auto-approve`, `claude-code-action` workflow が成功している（または該当イベントが起きていなければ idle）。

- [ ] **Step 4: Renovate 動作確認**

GitHub 上で `panicboat-actions` リポジトリに Renovate ボットの "Configure Renovate" PR / Dashboard issue が出ているか確認。出ていない場合は Renovate App の対象リポジトリ設定で `panicboat-actions` を追加する。

期待: Dashboard issue が作成済みになる。

---

### Task E2: Worktree cleanup

Phase D PR がマージされたあと、worktree を整理。

- [ ] **Step 1: worktree 削除**

```bash
cd ~/GitHub/panicboat/deploy-actions
git worktree remove .claude/worktrees/refactor/split-personal-actions
git worktree prune
```

期待: worktree ディレクトリが削除される。

- [ ] **Step 2: ローカルブランチ削除**

```bash
git branch -d refactor/split-personal-actions
```

注: マージ済であれば `-d` で削除可能。

---

## Notes / Risks

- **Phase C と Phase D の間隔**: Phase C 完了から Phase D 完了までの窓では、`panicboat/deploy-actions/{moved-action}@main` を新規参照する PR が出ると、Phase D マージ前であれば動くが Phase D マージ後は壊れる。Phase C → Phase D を同日内に通すこと。
- **`terragrunt import` 失敗時**: 既存 deploy-actions の visibility / features などが想定と乖離している場合、Task A7 Step 3 の `make plan` で diff が出る。`deploy-actions.hcl` を実態に合わせて follow-up PR で修正してから apply。
- **`panicboat-actions` 側の Renovate**: 初回は Configure Renovate PR がマージされるまで動かない。
- **`@main` 参照**: 全て floating reference のため、`panicboat-actions:main` が壊れると即座に consumer に伝播。タグ運用に切り替えたい場合は Phase 完了後の別 task として扱う（今回は対象外）。
