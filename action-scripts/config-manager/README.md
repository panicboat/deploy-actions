# Config Manager

**English** | [🇯🇵 Japanese](README-ja.md)

A Ruby-based configuration validation and management tool for GitHub Actions deployment automation.

## Overview

Loads and validates stack definitions, displays configuration, and diagnoses services using existing directories. See [Configuration](../../README.md#configuration) for the schema and [Matrix Output](../../README.md#matrix-output) for the output format.

## Usage

The Config Manager provides a CLI interface through `config-manager/bin/config-manager`:

### Commands

Run commands from the `action-scripts` directory.

| Command | Result |
|---|---|
| `bundle exec ruby config-manager/bin/config-manager validate` | Validation result and stack/declared environment counts |
| `bundle exec ruby config-manager/bin/config-manager show` | All paths, environment or shared attributes, and exclusions for each stack ID |
| `bundle exec ruby config-manager/bin/config-manager environments` | Union of declared and discovered environment names |
| `bundle exec ruby config-manager/bin/config-manager test SERVICE_NAME [ENVIRONMENT]` | All existing matching targets and their exclusion status |
| `bundle exec ruby config-manager/bin/config-manager diagnostics` | Diagnostics for configuration, environment variables, Git state, and the configuration file |
| `bundle exec ruby config-manager/bin/config-manager template` | Display of YAML for creating a configuration |
| `bundle exec ruby config-manager/bin/config-manager check_file` | Existence, readability, and YAML syntax checks for the default file |

### Service Diagnosis

Omitting the environment inspects all declared and discovered environments and shared targets for the service. Selecting an environment inspects that environment and shared targets. Services do not require registration. A service that matches no paths produces an empty result.

All matching directories are displayed by stack ID, with expanded attribute values and captured arbitrary placeholders. Excluded targets are also displayed with `excluded: true`, so you can inspect why they are omitted from deployment.

```bash
bundle exec ruby config-manager/bin/config-manager test demo
bundle exec ruby config-manager/bin/config-manager test demo production
```

Unknown environments, invalid configuration, directory enumeration failures, and conflicting captured values for the same target are reported as errors.

## Architecture

### Components

- **ConfigManagerController**: Main orchestration and CLI interface
- **ValidateConfig**: Comprehensive configuration validation
- **ConfigClient**: Configuration loading and parsing
- **ConsolePresenter**: Human-readable output formatting

### Validation Flow

Loads YAML, validates structure and consistency through the configuration model, and displays the validation result with stack/declared environment counts. Validation and configuration display do not enumerate directories; use `environments` or service diagnosis to discover environment names from existing directories. See [Configuration](../../README.md#configuration) for the validation rules.

## Error Handling

Detailed error reporting with:

- **Specific Error Messages**: Pinpoint configuration issues
- **Validation Context**: Clear indication of problematic sections
- **Suggestions**: Guidance for fixing common configuration problems
- **Summary Statistics**: Overview of configuration health

## Integration

The Config Manager integrates with:

- **Label Resolver**: Provides configuration for deployment targeting
- **Label Dispatcher**: Validates service and directory configurations
- **GitHub Actions**: Environment validation for CI/CD workflows

## Development

### Running Tests

```bash
cd action-scripts
bundle exec rspec spec/config-manager/
```

### Local Testing

```bash
cp workflow-config.yaml test-config.yaml
WORKFLOW_CONFIG_PATH=test-config.yaml bundle exec ruby config-manager/bin/config-manager validate
bundle exec ruby config-manager/bin/config-manager test myservice develop
```
