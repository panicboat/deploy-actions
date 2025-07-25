# FluxCD Manifest Generator

**English** | [🇯🇵 日本語](README-ja.md)

Generate complete FluxCD GitOps configurations from simple application manifests.

## Quick Start

```bash
# Install and generate
bundle install
bundle exec ruby bin/generator generate

# With custom options
bin/generator generate -e my-env custom-cluster -n generated-manifests -t my-namespace -o ./output
```

## GitHub Actions

```yaml
- name: Generate FluxCD manifests
  uses: panicboat/deploy-actions/flux-generator@main
  with:
    github-token: ${{ secrets.GITHUB_TOKEN }}
    environments: 'develop,staging,production'
    repository-name: 'my-manifests'
```

## CLI Options

| Option | Description | Default |
|--------|-------------|---------|
| `-r, --repository-url` | Git repository URL | Auto-detected |
| `-e, --environments` | Target environments (any string) | `develop,staging,production` |
| `-n, --resource-name` | GitRepository/Kustomization name | Auto-generated (e.g., `flux-a1b2c3d4`) |
| `-t, --target-namespace` | Target namespace for Kustomization resources | None |
| `-o, --output-dir` | Output directory | Current directory |
| `-v, --verbose` | Verbose output | `false` |

## Input Structure

Place your application manifests in environment directories:

```
develop/
├── web-app.yaml
└── services/
    └── database.yaml
```

## Generated Structure

Creates complete FluxCD GitOps setup:
- **GitRepository**: Source repository configuration
- **Kustomization**: FluxCD resource management
- **Directory structure**: `clusters/{environment}/{flux-system,apps}/`
- **Kustomize configs**: Manifest organization

## Development

```bash
bundle exec rspec                    # Run tests
bundle exec rubocop                  # Code style check
```

## License

MIT License
