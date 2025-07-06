# Deploy Actions

Reusable GitHub Actions workflows and scripts for automated deployment workflows.

## 🎯 Overview

This repository provides reusable workflows and scripts that can be called from other repositories to automate deployment processes, including:

- **Label Dispatcher**: Automatically detects changed services and applies deployment labels
- **Deploy Trigger**: Extracts deployment targets from PR labels and generates deployment matrices  
- **Terragrunt Executor**: Manages infrastructure deployments via Terragrunt
- **Kubernetes Executor**: Manages application deployments via Kubernetes

## 🏗️ Architecture

```
deploy-actions/
├── .github/workflows/          # Reusable workflows
│   ├── reusable--label-dispatcher.yaml
│   ├── reusable--deploy-trigger.yaml
│   ├── reusable--terragrunt-executor.yaml
│   └── reusable--kubernetes-executor.yaml
├── scripts/                    # Core automation scripts
│   ├── label-dispatcher/
│   ├── deploy-trigger/
│   ├── config-manager/
│   └── shared/
├── actions/                    # Custom actions
└── README.md
```

## 🚀 Usage

### From another repository:

```yaml
jobs:
  dispatch-labels:
    uses: organization/deploy-actions/.github/workflows/reusable--label-dispatcher.yaml@v1
    with:
      pr-number: ${{ github.event.pull_request.number }}
      repository: ${{ github.repository }}
      config-path: '.github/config/workflow-config.yaml'
    secrets:
      github-token: ${{ secrets.GITHUB_TOKEN }}
```

## 🔒 Security

- This repository only receives generated GitHub tokens, never private keys
- All sensitive operations are performed in the calling repository
- Follows principle of least privilege

## 📚 Documentation

- [Migration Plan](../monorepo/MIGRATION_PLAN.md) - Detailed migration documentation
- [Configuration Guide](docs/CONFIGURATION.md) - How to configure workflows
- [Troubleshooting](docs/TROUBLESHOOTING.md) - Common issues and solutions

## 🔄 Versioning

Use semantic versioning tags when calling workflows:
- `@v1` - Latest stable v1.x release
- `@v1.2.0` - Specific version
- `@main` - Development (not recommended for production)

---

**Created**: 2025-07-06  
**Migration from**: monorepo/.github/scripts  
**Status**: Under migration