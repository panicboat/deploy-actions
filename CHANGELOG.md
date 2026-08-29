# Changelog

## v1.3.0

### Added
- `stack_conventions[].stacks[].id` (optional): identifier for a stack
  instance within a convention. Enables a single service to carry multiple
  stack entries that share the same reusable-workflow `name` (e.g. two
  terragrunt stacks: one for AWS, one for Stripe).
- Matrix output now includes `stack_id` (defaults to `stack` when `id` is
  not set).
- `WorkflowConfig#stack_attributes_for` and `#required_attributes_for` now
  accept the identity (`id || name`) and fall back to the stack's `name`
  so existing configs migrate incrementally.

### Changed
- **Breaking**: entries within a single convention that share the same
  `name` and have no `id` now raise a validation error instead of being
  silently deduplicated. Add distinct `id` values to keep both entries.

## [1.2.0](https://github.com/panicboat/deploy-actions/compare/v1.1.0...v1.2.0) (2026-05-20)


### Features

* uniform placeholder handling via PatternMatcher ([#235](https://github.com/panicboat/deploy-actions/issues/235)) ([abe183d](https://github.com/panicboat/deploy-actions/commit/abe183d4f133bbd651dcbc47e47ed7ad3f1bf7c6))

## [1.1.0](https://github.com/panicboat/deploy-actions/compare/v1.0.0...v1.1.0) (2026-05-04)


### Features

* **label-resolver:** match all stack conventions for multi-stack services ([#221](https://github.com/panicboat/deploy-actions/issues/221)) ([5436cad](https://github.com/panicboat/deploy-actions/commit/5436cad6592ada8308ed98c1c5f5d44a2e7d7044))


### Bug Fixes

* **ci:** run lint-actions on every PR (Required check needs to register) ([#218](https://github.com/panicboat/deploy-actions/issues/218)) ([f54f57f](https://github.com/panicboat/deploy-actions/commit/f54f57ff4535ebed9b9cc0267f7c82e85f53513a))

## 1.0.0 (2026-05-01)

Initial release.

### Composite Actions

* `label-dispatcher` — dispatch labels based on PR changes
* `label-resolver` — resolve deployment targets from PR labels and branch information
