# Changelog

## 0.1.0 — 2026-10-10

### Added

- First release of the OpenFeature provider for Ruby, backed by the `featureflip` gem. Resolves boolean, string, number, integer, float and object flags through the standard `openfeature-sdk` client, maps Featureflip reasons onto OpenFeature's (an unmet prerequisite surfaces as `PREREQUISITE_FAILED`), exposes `ruleId` and `prerequisiteKey` as flag metadata, writes the targeting key under both `user_id` and `userId`, and emits `PROVIDER_CONFIGURATION_CHANGED` with the changed flag keys. Needs `featureflip` 2.10 or newer. (#3643)
