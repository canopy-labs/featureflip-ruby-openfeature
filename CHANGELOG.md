# Changelog

## 0.3.0 — 2026-11-17

### Changed

- `targeting_key` is written into the Featureflip context as `user_id` only, the canonical spelling, instead of under both `user_id` and `userId`. A targeting rule on either spelling still matches, because the SDK resolves `userId` and `user_id` to the same identity. That alias reached the SDK's condition evaluator in `featureflip` 2.13.1, so the provider now requires 2.13.1 or later. An explicit attribute of either spelling still wins. (#4546)

## 0.2.1 — 2026-10-26

### Changed

- Requires the `featureflip` gem 2.13 or later, so the evaluation events behind every flag the provider resolves carry the evaluation reason (`rule-match`, `fallthrough`, `flag-disabled`, `prerequisite-failed`, `error` or `flag-not-found`) and the matched rule id. Featureflip's flag Analytics tab uses them to show which part of the targeting served the traffic. (#4268)

## 0.2.0 — 2026-10-20

### Added

- Requests made through the provider now identify it: `User-Agent: featureflip-ruby/<version> featureflip-openfeature-ruby/<version>`, so Featureflip can count OpenFeature usage apart from direct SDK use. This applies when the provider builds its own client from `sdk_key:`; it works on a copy of your `Featureflip::Config`, so the config you passed is unchanged. A `client:` you pass in was built before the provider saw it, so its requests are unchanged, and a `wrapper_name:` already set on your config is kept. (#4154)

### Changed

- Requires `featureflip` `~> 2.11`, the release that added `wrapper_name:`.

## 0.1.0 — 2026-10-10

### Added

- First release of the OpenFeature provider for Ruby, backed by the `featureflip` gem. Resolves boolean, string, number, integer, float and object flags through the standard `openfeature-sdk` client, maps Featureflip reasons onto OpenFeature's (an unmet prerequisite surfaces as `PREREQUISITE_FAILED`), exposes `ruleId` and `prerequisiteKey` as flag metadata, writes the targeting key under both `user_id` and `userId`, and emits `PROVIDER_CONFIGURATION_CHANGED` with the changed flag keys. Needs `featureflip` 2.10 or newer. (#3643)
