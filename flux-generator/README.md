# FluxCD Manifest Generator

**English** | [🇯🇵 日本語](README-ja.md)

[![Ruby](https://img.shields.io/badge/Ruby-3.4.4-red.svg)](https://www.ruby-lang.org/)
[![Clean Architecture](https://img.shields.io/badge/Architecture-Clean-blue.svg)](https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html)
[![GitOps](https://img.shields.io/badge/GitOps-FluxCD-purple.svg)](https://fluxcd.io/)

A sophisticated Ruby application that automatically generates complete FluxCD GitOps configurations from simple application manifest directories. Built with Clean Architecture principles for maintainability, testability, and reliability in CI/CD pipelines.

## 🎯 Purpose

The FluxCD Manifest Generator transforms your application manifests into a complete GitOps setup, enabling:

- **🔄 Continuous Deployment**: Automatic synchronization from git to Kubernetes
- **🏢 Environment Separation**: Isolated configurations for develop/staging/production
- **📝 Declarative Management**: All infrastructure as code in git
- **🚀 Multi-Application Support**: Handles multiple services per environment
- **⚡ GitHub Actions Integration**: Seamless CI/CD pipeline integration

## 🏗️ Architecture

### Clean Architecture Implementation

The application follows Clean Architecture principles with clear separation of concerns:

```
lib/
├── entities/          # 🏛️  Domain models (Environment, FluxResource, ManifestFile)
├── use_cases/         # 🎯 Business logic (GenerateFluxManifests, Setup, Validation)
├── controllers/       # 🎮 Interface adapters (CLI handling, orchestration)
└── repositories/      # 💾 Infrastructure (File I/O, data access)
```

### Dependency Flow
- **Entities**: No dependencies (pure domain logic)
- **Use Cases**: Depend only on entities
- **Controllers**: Depend on use cases and entities
- **Repositories**: Infrastructure layer accessed through interfaces

## 📁 Generated Structure

The generator creates this standardized FluxCD structure:

```
{environment}/                    # Application manifests
├── kustomization.yaml           # Environment root kustomization
├── service-a.yaml              # Individual service manifests
├── services/                   # Optional service grouping
│   ├── kustomization.yaml
│   ├── service-b.yaml
│   └── service-c.yaml
└── clusters/{environment}/     # FluxCD control plane
    ├── flux-system/
    │   ├── gotk-sync.yaml      # Git sync configuration
    │   └── kustomization.yaml   # Flux system entry point
    └── apps/
        ├── kustomization.yaml   # Apps orchestration
        ├── service-a.yaml      # App-specific Kustomizations
        └── services/
            ├── service-b.yaml
            └── service-c.yaml
```

## 🚀 Quick Start

### Local Usage

```bash
# Install dependencies
bundle install

# Generate manifests for all environments
bundle exec ruby bin/generator generate

# Generate for specific environments
bundle exec ruby bin/generator generate -e develop staging

# Generate with custom repository URL
bundle exec ruby bin/generator generate -r https://github.com/your-org/manifests

# Generate to specific directory
bundle exec ruby bin/generator generate -t /path/to/output

# Validate existing configuration
bundle exec ruby bin/generator validate

# Setup directory structure
bundle exec ruby bin/generator setup
```

### GitHub Actions Integration

```yaml
- name: Generate FluxCD manifests
  uses: panicboat/deploy-actions/flux-generator@main
  with:
    github-token: ${{ secrets.GITHUB_TOKEN }}
    target-path: ${{ github.workspace }}
    environments: 'develop,staging,production'
```

## 📋 CLI Commands

### `generate` - Generate FluxCD Manifests

Generate complete FluxCD manifest set for specified environments.

```bash
bin/generator generate [OPTIONS]
```

**Options:**
- `-e, --environments ARRAY`: Target environments (default: develop,staging,production)
- `-r, --repository-url STRING`: Git repository URL (auto-detected from GITHUB_REPOSITORY)
- `-t, --target-dir STRING`: Output directory (default: current directory)
- `-v, --verbose`: Enable verbose output

**Examples:**
```bash
# Basic usage
bin/generator generate

# Specific environments
bin/generator generate -e develop staging

# Custom repository
bin/generator generate -r https://github.com/company/app-manifests

# Output to different directory
bin/generator generate -t ../manifests-output
```

### `validate` - Validate Configuration

Validate existing environment configurations and directory structure.

```bash
bin/generator validate [OPTIONS]
```

**Validation checks:**
- ✅ Environment name validity
- ✅ Directory structure integrity
- ✅ Manifest file discovery
- ✅ FluxCD path configuration
- ✅ Kustomization file structure

### `setup` - Initialize Structure

Create directory structure and placeholder files without generating FluxCD resources.

```bash
bin/generator setup [OPTIONS]
```

**Actions performed:**
- 📁 Create environment directories
- 📁 Create FluxCD cluster directories
- 📄 Generate placeholder kustomization files
- 🔍 Detect and integrate existing manifests

### `version` - Version Information

Display version and architecture information.

```bash
bin/generator version
```

### `help_usage` - Usage Examples

Show comprehensive usage examples and integration tips.

```bash
bin/generator help_usage
```

## 🔧 Configuration

### Environment Variables

- **`GITHUB_REPOSITORY`**: Auto-detected repository URL (format: `owner/repo`)
- **`BUNDLE_GEMFILE`**: Specify custom Gemfile location

### Input Directory Structure

Place your application manifests in environment directories:

```
develop/
├── nginx-app.yaml
├── api-service.yaml
└── services/
    ├── database.yaml
    └── redis.yaml

staging/
├── nginx-app.yaml
└── api-service.yaml

production/
├── nginx-app.yaml
└── api-service.yaml
```

The generator will automatically discover these manifests and create appropriate FluxCD resources.

## 🏗️ Core Components

### Entities (Domain Models)

#### Environment
Represents target deployment environments with path calculations and validation.

```ruby
environment = Entities::Environment.from_name('develop')
environment.name           # => 'develop'
environment.flux_system_path # => './clusters/develop/flux-system'
environment.apps_path      # => './clusters/develop/apps'
```

#### FluxResource
Universal representation of Kubernetes/FluxCD resources with YAML serialization.

```ruby
git_repo = Entities::FluxResource.git_repository(
  name: 'flux-system',
  namespace: 'flux-system',
  url: 'https://github.com/company/manifests'
)
```

#### ManifestFile
Represents application manifest files with path and naming logic.

```ruby
manifest = Entities::ManifestFile.from_path('develop/services/api.yaml', 'develop')
manifest.service_name    # => 'api'
manifest.in_subdirectory? # => true
```

### Use Cases (Business Logic)

#### GenerateFluxManifests
Main orchestrator that coordinates the five generation steps:

1. **GitRepository & Root Kustomization** (`GenerateGotkSync`)
2. **Flux System Setup** (`GenerateFluxSystemKustomization`)
3. **Apps Organization** (`GenerateAppsKustomization`)
4. **Individual App Resources** (`GenerateAppResources`)
5. **Environment Structure** (`GenerateEnvironmentKustomizations`)

### Controllers (Interface Layer)

#### FluxGeneratorController
- Main entry point for manifest generation
- Repository URL auto-detection
- Error handling and user feedback

#### SetupController
- Directory structure management
- Missing environment creation
- Placeholder file generation

#### ValidationController
- Configuration validation
- Health check reporting
- Issue identification

### Repositories (Infrastructure Layer)

#### FileSystemRepository
- File system abstraction
- Directory and file operations
- YAML file discovery

#### ManifestRepository
- Manifest file operations
- Business-logic-aware filtering
- ManifestFile entity creation

## 🧪 Development

### Prerequisites

- Ruby 3.4.4+
- Bundler 2.6.7+

### Setup

```bash
# Clone repository
git clone https://github.com/panicboat/deploy-actions.git
cd deploy-actions/flux-generator

# Install dependencies
bundle install

# Run tests
bundle exec rspec

# Check syntax
find lib -name "*.rb" -exec ruby -c {} \;
```

### Testing

```bash
# Run all tests
bundle exec rspec

# Run specific test file
bundle exec rspec spec/entities/environment_spec.rb

# Run with coverage
bundle exec rspec --format documentation
```

### Code Quality

```bash
# Syntax check
ruby -c bin/generator
find lib -name "*.rb" -exec ruby -c {} \;

# Style check (if rubocop configured)
bundle exec rubocop
```

## 📚 FluxCD Resources Generated

### GitRepository Resource
```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: GitRepository
metadata:
  name: flux-system
  namespace: flux-system
spec:
  interval: 1m0s
  ref:
    branch: main
  url: https://github.com/company/manifests
```

### Kustomization Resource
```yaml
apiVersion: kustomize.toolkit.fluxcd.io/v1
kind: Kustomization
metadata:
  name: flux-system
  namespace: flux-system
spec:
  interval: 10m0s
  path: ./clusters/develop
  prune: true
  sourceRef:
    kind: GitRepository
    name: flux-system
```

### Kustomize Config
```yaml
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - service-a.yaml
  - services/
```

## 🔄 Workflows

### Generation Workflow
1. **Input Processing**: Parse CLI arguments and validate environments
2. **Repository Detection**: Auto-detect or validate git repository URL
3. **Directory Setup**: Ensure complete directory structure exists
4. **Manifest Discovery**: Scan environments for existing application manifests
5. **FluxCD Generation**: Create GitRepository and Kustomization resources
6. **Kustomization Creation**: Generate organizational kustomization files
7. **Validation**: Verify generated structure integrity
8. **Completion**: Report generation results

### Setup Workflow
1. **Structure Validation**: Check existing directory layout
2. **Missing Detection**: Identify absent environments and files
3. **Directory Creation**: Build complete FluxCD hierarchy
4. **Placeholder Generation**: Create empty kustomization files
5. **Service Discovery**: Scan for existing services and integrate them
6. **Verification**: Validate created structure

## ⚡ GitHub Actions Usage

### Basic Setup

```yaml
name: Sync FluxCD Manifests

on:
  push:
    branches: [main]
  workflow_dispatch:

jobs:
  sync:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Generate FluxCD manifests
        uses: panicboat/deploy-actions/flux-generator@main
        with:
          github-token: ${{ secrets.GITHUB_TOKEN }}
          target-path: ${{ github.workspace }}

      - name: Create Pull Request
        uses: peter-evans/create-pull-request@v7
        with:
          token: ${{ secrets.GITHUB_TOKEN }}
          commit-message: "auto: update FluxCD manifests"
          title: "Auto-update FluxCD manifests"
```

### Advanced Configuration

```yaml
- name: Generate FluxCD manifests
  uses: panicboat/deploy-actions/flux-generator@main
  with:
    github-token: ${{ secrets.GITHUB_TOKEN }}
    target-path: ${{ github.workspace }}/generated-manifests
    environments: 'develop,staging'
    deploy-actions-repository: 'company/custom-deploy-actions'
```

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b feature/amazing-feature`)
3. Commit your changes (`git commit -m 'Add amazing feature'`)
4. Push to the branch (`git push origin feature/amazing-feature`)
5. Open a Pull Request

### Development Guidelines

- Follow Clean Architecture principles
- Maintain high test coverage
- Use consistent Ruby style
- Add comprehensive documentation
- Include usage examples

## 📄 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.

## 🆘 Support

- **Issues**: [GitHub Issues](https://github.com/panicboat/deploy-actions/issues)
- **Discussions**: [GitHub Discussions](https://github.com/panicboat/deploy-actions/discussions)
- **Documentation**: [FluxCD Documentation](https://fluxcd.io/docs/)

## 🙏 Acknowledgments

- [FluxCD](https://fluxcd.io/) for the GitOps toolkit
- [Clean Architecture](https://blog.cleancoder.com/uncle-bob/2012/08/13/the-clean-architecture.html) by Uncle Bob
- [dry-rb](https://dry-rb.org/) for excellent Ruby libraries
- [Thor](https://github.com/rails/thor) for CLI framework
