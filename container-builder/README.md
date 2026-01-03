# Container Builder

Build and push container images to GitHub Container Registry.

## Overview

This composite action provides a streamlined way to build and push Docker images to GitHub Container Registry (ghcr.io). It handles Docker login, buildx setup, metadata extraction, and image building with caching support.

## Inputs

| Name | Required | Default | Description |
|------|----------|---------|-------------|
| `token` | Yes | - | GitHub token for authentication (e.g., from `actions/create-github-app-token`) |
| `image-name` | Yes | - | Name of the image (e.g., `service-name`) |
| `working-directory` | No | `.` | Directory containing the Dockerfile |
| `dockerfile-path` | No | `Dockerfile` | Path to Dockerfile relative to working-directory |
| `tags-template` | No | See below | Docker tags template (see [docker/metadata-action](https://github.com/docker/metadata-action) for syntax) |

Default `tags-template`:
```
type=sha
type=ref,event=pr
type=raw,value=latest,enable={{is_default_branch}}
```

## Usage

### Basic Example

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    steps:
      - name: Generate GitHub App token
        id: app-token
        uses: actions/create-github-app-token@v2.2.1
        with:
          app-id: ${{ vars.APP_ID }}
          private-key: ${{ secrets.APP_PRIVATE_KEY }}

      - name: Build and push container
        uses: panicboat/deploy-actions/container-builder@main
        with:
          token: ${{ steps.app-token.outputs.token }}
          image-name: my-service
```

### Advanced Example

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    steps:
      - name: Generate GitHub App token
        id: app-token
        uses: actions/create-github-app-token@v2.2.1
        with:
          app-id: ${{ vars.APP_ID }}
          private-key: ${{ secrets.APP_PRIVATE_KEY }}

      - name: Build and push container
        uses: panicboat/deploy-actions/container-builder@main
        with:
          token: ${{ steps.app-token.outputs.token }}
          image-name: api-service
          working-directory: ./services/api
          dockerfile-path: Dockerfile.prod
```

### Custom Tags Example

You can customize the tagging strategy using the `tags-template` input:

```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write

    steps:
      - name: Generate GitHub App token
        id: app-token
        uses: actions/create-github-app-token@v2.2.1
        with:
          app-id: ${{ vars.APP_ID }}
          private-key: ${{ secrets.APP_PRIVATE_KEY }}

      - name: Build and push container with custom tags
        uses: panicboat/deploy-actions/container-builder@main
        with:
          token: ${{ steps.app-token.outputs.token }}
          image-name: my-service
          tags-template: |
            type=ref,event=branch
            type=ref,event=pr
            type=semver,pattern={{version}}
            type=semver,pattern={{major}}.{{minor}}
            type=sha
```

Common tag patterns:
- `type=ref,event=branch` - Branch name (e.g., `main`, `develop`)
- `type=ref,event=tag` - Git tag
- `type=semver,pattern={{version}}` - Semantic version (e.g., `1.2.3`)
- `type=semver,pattern={{major}}.{{minor}}` - Major.minor version (e.g., `1.2`)
- `type=schedule` - For scheduled builds
- `type=raw,value=custom-tag` - Custom static tag

See [docker/metadata-action](https://github.com/docker/metadata-action#tags-input) for full documentation.

## Features

- **Automated tagging**: Generates tags based on git SHA, PR refs, and latest for default branch
- **Layer caching**: Uses GitHub Actions cache for faster builds
- **Metadata extraction**: Automatically extracts and applies Docker labels
- **Multi-platform support**: Uses Docker Buildx for advanced build features

## Image Tags

### Default Tagging Strategy

By default, the action generates tags based on the event type:

**Pull Request:**
- `sha-abc123` (git SHA)
- `pr-123` (PR number)

**Push to default branch (e.g., main):**
- `sha-abc123`
- `latest`

**Push to feature branch:**
- `sha-abc123` only

Images are pushed to: `ghcr.io/<owner>/<repo>/<image-name>`

You can customize this behavior using the `tags-template` input (see Custom Tags Example above).

## Required Permissions

The calling workflow must have the following permissions:

```yaml
permissions:
  contents: read    # To checkout the repository
  packages: write   # To push to GitHub Container Registry
```

## Migration from Reusable Workflow

If you're migrating from the `reusable--container-builder.yaml` workflow:

**Before:**
```yaml
jobs:
  build:
    uses: ./.github/workflows/reusable--container-builder.yaml
    with:
      image-name: my-service
      app-id: ${{ vars.APP_ID }}
    secrets:
      private-key: ${{ secrets.APP_PRIVATE_KEY }}
```

**After:**
```yaml
jobs:
  build:
    runs-on: ubuntu-latest
    permissions:
      contents: read
      packages: write
    steps:
      - name: Generate GitHub App token
        id: app-token
        uses: actions/create-github-app-token@v2.2.1
        with:
          app-id: ${{ vars.APP_ID }}
          private-key: ${{ secrets.APP_PRIVATE_KEY }}

      - name: Build and push container
        uses: panicboat/deploy-actions/container-builder@main
        with:
          token: ${{ steps.app-token.outputs.token }}
          image-name: my-service
```

## Notes

- For production use, pin to a specific version tag instead of `@main`
- The GitHub token must have appropriate permissions to push to ghcr.io
- Docker buildx cache is stored in GitHub Actions cache for improved build performance
