# Design: Split deploy-actions into Public Core and Personal Wrappers

## Background

`panicboat/deploy-actions` currently mixes two distinct kinds of GitHub Actions:

- **Public-quality**: Generic deployment orchestration (`label-dispatcher`, `label-resolver`, `config-manager`, plus the Ruby scripts under `action-scripts/`).
- **Personal use**: Thin Composite Action wrappers tailored to the author's setup (`terragrunt`, `kubernetes`, `container-builder`, `container-cleaner`, `auto-approve`, `claude-code-action`).

Mixing both in one repository blurs the responsibility boundary: the README has to explain unrelated wrappers, Renovate config carries customManagers that only apply to a subset, and external readers see a project broader than what is intended for public consumption.

## Goal

Split the personal-use wrappers into a new `panicboat/panicboat-actions` repository, leaving `deploy-actions` focused on the public-quality components.

## Target Architecture

### `panicboat/deploy-actions` (slimmed down, public-facing)

```
deploy-actions/
├── .github/
│   ├── CODEOWNERS
│   ├── renovate.json        # customManagers for terragrunt removed
│   └── workflows/           # empty (or future public CI only)
├── action-scripts/          # config-manager / label-dispatcher / label-resolver / shared / spec
│   ├── Gemfile / Gemfile.lock
│   ├── workflow-config.yaml # sample config
│   └── ...
├── label-dispatcher/        # composite action
├── label-resolver/          # composite action
├── README.md / README-ja.md # rewritten around label-dispatcher / label-resolver / config-manager
└── (removed: terragrunt/, kubernetes/, container-builder/, container-cleaner/, auto-approve/, claude-code-action/)
```

### `panicboat/panicboat-actions` (new, personal-use)

```
panicboat-actions/
├── .github/
│   ├── CODEOWNERS
│   ├── renovate.json        # full copy of deploy-actions renovate.json (customManagers included)
│   └── workflows/
│       ├── auto-approve.yaml        # references panicboat/panicboat-actions/auto-approve@main
│       └── claude-code-action.yaml  # references panicboat/panicboat-actions/claude-code-action@main
├── auto-approve/
├── claude-code-action/
├── container-builder/
├── container-cleaner/
├── kubernetes/
├── terragrunt/
└── README.md / README-ja.md # personal-use wrapper collection
```

Internal layout is flat (no `infra/` or `ci/` subgrouping).

### Visibility

- `panicboat/deploy-actions`: **public** (unchanged)
- `panicboat/panicboat-actions`: **public** (required so consumer workflows in public repos can reference `panicboat/panicboat-actions/...@main`)

### Reference rewrites in consumer repositories

| File | Before | After |
|---|---|---|
| `platform/.github/workflows/reusable--terragrunt-executor.yaml` | `panicboat/deploy-actions/terragrunt@main` | `panicboat/panicboat-actions/terragrunt@main` |
| `platform/.github/workflows/reusable--kubernetes-builder.yaml` | `panicboat/deploy-actions/kubernetes@main` | `panicboat/panicboat-actions/kubernetes@main` |
| `platform/.github/workflows/claude-code-action.yaml` | `panicboat/deploy-actions/claude-code-action@main` | `panicboat/panicboat-actions/claude-code-action@main` |
| `platform/.github/workflows/auto-approve.yaml` | `panicboat/deploy-actions/auto-approve@main` | `panicboat/panicboat-actions/auto-approve@main` |
| `platform/.github/workflows/auto-label--label-dispatcher.yaml` | `panicboat/deploy-actions/label-dispatcher@main` | (no change) |
| `platform/.github/workflows/auto-label--deploy-trigger.yaml` | `panicboat/deploy-actions/label-resolver@main` | (no change) |
| `monorepo/.github/workflows/reusable--terragrunt-executor.yaml` | `panicboat/deploy-actions/terragrunt@main` | `panicboat/panicboat-actions/terragrunt@main` |
| `monorepo/.github/workflows/reusable--kubernetes-builder.yaml` | `panicboat/deploy-actions/kubernetes@main` | `panicboat/panicboat-actions/kubernetes@main` |
| `monorepo/.github/workflows/claude-code-action.yaml` | `panicboat/deploy-actions/claude-code-action@main` | `panicboat/panicboat-actions/claude-code-action@main` |
| `monorepo/.github/workflows/auto-approve.yaml` | `panicboat/deploy-actions/auto-approve@main` | `panicboat/panicboat-actions/auto-approve@main` |
| `monorepo/.github/workflows/reusable--container-builder.yaml` | `panicboat/deploy-actions/container-builder@main` | `panicboat/panicboat-actions/container-builder@main` |
| `monorepo/.github/workflows/cleanup-container-image.yaml` | `panicboat/deploy-actions/container-cleaner@main` | `panicboat/panicboat-actions/container-cleaner@main` |
| `monorepo/.github/workflows/auto-label--label-dispatcher.yaml` | `panicboat/deploy-actions/label-dispatcher@main` | (no change) |
| `monorepo/.github/workflows/auto-label--deploy-trigger.yaml` | `panicboat/deploy-actions/label-resolver@main` | (no change) |

## Migration Strategy

One-shot cutover (not gradual). Git history is **not** preserved when copying directories into the new repo (clean start).

### Step 0: Bring both repositories under Terragrunt management

In `platform/github/repository/envs/develop/`:

- Add `panicboat-actions.hcl` (visibility `public`, features matching existing `monorepo.hcl` / `platform.hcl`).
- Add `deploy-actions.hcl` (matches the existing repository's current settings).
- Update `terragrunt.hcl` to read both `*.hcl` files and add both entries to the `repositories` map.

In `platform/github/branch/envs/develop/`:

- Add `panicboat-actions.hcl` (same shape as existing `deploy-actions.hcl`: `branch_protection = local.defaults.locals.branch_protection`).
- Update `terragrunt.hcl` accordingly.

Execution:

1. Open a PR in `platform/` with all four file additions and two `terragrunt.hcl` updates.
2. Merge.
3. Run `terragrunt import` to bring the existing `deploy-actions` repository into Terraform state (`github_repository.repository["deploy-actions"]`).
4. Run `terragrunt plan` and resolve any drift between the existing repository's settings and the module defaults (adjust the `.hcl` or `main.tf` until plan is clean).
5. Run `terragrunt apply` — this creates the empty `panicboat-actions` repository and its branch protection.

### Step 1: Initialize `panicboat-actions` content

1. Clone the empty `panicboat-actions` repo locally.
2. Copy the following directories from `deploy-actions` (working-tree copy, no git history):
   - `auto-approve/`
   - `claude-code-action/`
   - `container-builder/`
   - `container-cleaner/`
   - `kubernetes/`
   - `terragrunt/`
3. Copy `.github/CODEOWNERS` and `.github/renovate.json` (full content, customManagers included).
4. Copy `.github/workflows/auto-approve.yaml` and `.github/workflows/claude-code-action.yaml`, rewriting their `uses:` references to `panicboat/panicboat-actions/auto-approve@main` and `panicboat/panicboat-actions/claude-code-action@main` respectively.
5. Author `README.md` / `README-ja.md` describing the repository as a personal-use wrapper collection.
6. Open a PR, get green CI, merge to make `main` available for `@main` references.

### Step 2: Rewrite consumer workflow references

- One PR in `platform/` updating four files (terragrunt / kubernetes / claude-code-action / auto-approve references).
- One PR in `monorepo/` updating six files (the four above plus container-builder / container-cleaner).

The two PRs can be opened and merged in parallel. They depend on Step 1 being complete.

### Step 3: Slim down `deploy-actions`

A single PR in `deploy-actions/` that:

1. Deletes the six moved directories: `auto-approve/`, `claude-code-action/`, `container-builder/`, `container-cleaner/`, `kubernetes/`, `terragrunt/`.
2. Deletes `.github/workflows/auto-approve.yaml` and `.github/workflows/claude-code-action.yaml`.
3. Removes the two `customManagers` entries from `.github/renovate.json` whose `fileMatch` targets `^terragrunt/action\.yaml$`.
4. Rewrites `README.md` / `README-ja.md` to focus on `label-dispatcher`, `label-resolver`, and `config-manager`.

Step 3 must be merged after Step 2 to avoid breaking active CI runs.

### Order constraints

- Step 0 → must complete before Step 1 (the new repo must exist).
- Step 1 → must merge to `main` before Step 2 (consumer references must resolve).
- Step 2 → must merge before Step 3 (otherwise consumers still pointing at deleted paths will break).
- Step 3's four sub-tasks ship together in one PR.

## Renovate / Workflow Split Details

### `.github/renovate.json`

`panicboat-actions/.github/renovate.json`: full copy of the current `deploy-actions/.github/renovate.json`, including:

- `Track OpenTofu version pinned in terragrunt composite action` (`fileMatch: ^terragrunt/action\.yaml$`)
- `Track Terragrunt version pinned in terragrunt composite action` (`fileMatch: ^terragrunt/action\.yaml$`)

`deploy-actions/.github/renovate.json`: same as today minus the two customManagers above. All other keys (`extends`, `packageRules`, `schedule`, etc.) stay identical between the two repos.

### `.github/workflows/`

`panicboat-actions/.github/workflows/` contains:

- `auto-approve.yaml` (copied, `uses:` rewritten)
- `claude-code-action.yaml` (copied, `uses:` rewritten)

`deploy-actions/.github/workflows/` is emptied of those two files. The directory may remain empty or hold future public-facing CI.

### `.github/CODEOWNERS`

Both repositories carry the same content (the existing `deploy-actions/.github/CODEOWNERS`).

## Risks and Rollback

### Risks

1. **Window between Step 2 and Step 3.** A new PR opened after Step 2 merges but before Step 3 merges, that references `panicboat/deploy-actions/terragrunt@main` (or any moved action), would still resolve correctly until Step 3 lands. Conversely, a PR that depends on the new path before Step 1 lands would fail. Mitigation: keep Steps 1-3 tight in time (same day), and do not merge unrelated workflow changes during the window.

2. **`terraform import` drift.** Existing `deploy-actions` settings may differ from the module defaults in `platform/github/repository/modules/main.tf`. Mitigation: after import, run `terragrunt plan` and resolve drift by adjusting the `.hcl` (preferred) or the module (only if the new defaults should apply project-wide).

3. **Renovate enablement lag on the new repo.** The Renovate App may not pick up `panicboat-actions` immediately. Mitigation: confirm the App's repository selection setting after Step 1.

4. **`@main` floating reference.** Existing operational risk; not new. A force-push or bad merge to `panicboat-actions:main` would propagate immediately to consumers, identical to today's exposure with `deploy-actions:main`.

### Rollback

Each Step is an independent PR (or `terragrunt apply`) and revertible:

- **Step 0**: `terragrunt destroy` for `panicboat-actions` (and remove its `.hcl` plus `terragrunt.hcl` entry); for `deploy-actions`, `terraform state rm` the imported resource and revert the PR.
- **Step 1**: force-push `panicboat-actions:main` back to the initial empty state, or delete the repository (which Step 0's destroy covers).
- **Step 2**: revert the platform / monorepo PRs; consumers fall back to `panicboat/deploy-actions/...@main` as long as Step 3 has not merged.
- **Step 3**: revert PR restores the deleted directories, workflows, and renovate.json customManagers.

For an emergency rollback discovered after Step 3, the order is reverse: Step 3 revert PR → Step 2 revert PRs.
