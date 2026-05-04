# Changelog

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
