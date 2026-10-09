# Changelog

## [2.0.0](https://github.com/panicboat/deploy-actions/compare/v1.4.2...v2.0.0) (2026-10-09)


### ⚠ BREAKING CHANGES

* discover stack environments and expand attributes ([#334](https://github.com/panicboat/deploy-actions/issues/334))

### Features

* discover stack environments and expand attributes ([#334](https://github.com/panicboat/deploy-actions/issues/334)) ([9c87a02](https://github.com/panicboat/deploy-actions/commit/9c87a02c3b14ff5f2f1ff2a07467b1a33be5f874))

## [1.4.2](https://github.com/panicboat/deploy-actions/compare/v1.4.1...v1.4.2) (2026-10-09)


### Bug Fixes

* run scripts directly from action path without checking out deploy-actions ([#332](https://github.com/panicboat/deploy-actions/issues/332)) ([0aea6e7](https://github.com/panicboat/deploy-actions/commit/0aea6e79458bf1075ba8b67ae809b7bc17682e87))

## [1.4.1](https://github.com/panicboat/deploy-actions/compare/v1.4.0...v1.4.1) (2026-10-09)


### Bug Fixes

* support checking out action ref in composite actions ([#330](https://github.com/panicboat/deploy-actions/issues/330)) ([8c93063](https://github.com/panicboat/deploy-actions/commit/8c9306349208086fcfcb7592a3fd164d1c9b2612))

## [1.4.0](https://github.com/panicboat/deploy-actions/compare/v1.3.0...v1.4.0) (2026-10-09)


### Features

* define stack paths, environments, and exclusions ([#328](https://github.com/panicboat/deploy-actions/issues/328)) ([32a515a](https://github.com/panicboat/deploy-actions/commit/32a515aadc1dd0b4f850082e7e6ae39d2abf5a29))

## [1.3.0](https://github.com/panicboat/deploy-actions/compare/v1.2.0...v1.3.0) (2026-09-06)


### Features

* introduce stacks[].id for multi-instance conventions ([#307](https://github.com/panicboat/deploy-actions/issues/307)) ([74da1d6](https://github.com/panicboat/deploy-actions/commit/74da1d66f80b7325e93c576e2b2aa5bfdf6f16a6))

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
