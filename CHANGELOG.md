# Changelog

## 0.2.0 — 2026-10-20

### Added

- Requests made through the provider now identify it: `User-Agent: featureflip-ruby/<version> featureflip-openfeature-ruby/<version>`, so Featureflip can count OpenFeature usage apart from direct SDK use. This applies when the provider builds its own client from `sdk_key:`; it works on a copy of your `Featureflip::Config`, so the config you passed is unchanged. A `client:` you pass in was built before the provider saw it, so its requests are unchanged, and a `wrapper_name:` already set on your config is kept. (#4154)

### Changed

- Requires `featureflip` `~> 2.11`, the release that added `wrapper_name:`.

## 0.1.0 — 2026-10-10

### Added

- First release of the OpenFeature provider for Ruby, backed by the `featureflip` gem. Resolves boolean, string, number, integer, float and object flags through the standard `openfeature-sdk` client, maps Featureflip reasons onto OpenFeature's (an unmet prerequisite surfaces as `PREREQUISITE_FAILED`), exposes `ruleId` and `prerequisiteKey` as flag metadata, writes the targeting key under both `user_id` and `userId`, and emits `PROVIDER_CONFIGURATION_CHANGED` with the changed flag keys. Needs `featureflip` 2.10 or newer. (#3643)
