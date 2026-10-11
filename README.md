# Featureflip OpenFeature provider for Ruby

Use [Featureflip](https://featureflip.io) feature flags through the
[OpenFeature](https://openfeature.dev) Ruby SDK.

## Install

```ruby
# Gemfile
gem "featureflip-openfeature"
```

## Use

```ruby
require "featureflip-openfeature"

OpenFeature::SDK.set_provider_and_wait(
  Featureflip::OpenFeature::Provider.new(sdk_key: ENV.fetch("FEATUREFLIP_SDK_KEY"))
)

client = OpenFeature::SDK.build_client
enabled = client.fetch_boolean_value(
  flag_key: "new-checkout",
  default_value: false,
  evaluation_context: OpenFeature::SDK::EvaluationContext.new(targeting_key: "user-42", plan: "pro")
)
```

Use `set_provider_and_wait`. Plain `set_provider` initializes in the background
and returns before flags load, so the next read gets your default.

Already using the Featureflip client directly? Pass it in and the provider will
share it, leaving ownership with you:

```ruby
client = Featureflip::Client.get("sdk-...")
OpenFeature::SDK.set_provider_and_wait(Featureflip::OpenFeature::Provider.new(client: client))
```

## Behavior

- `targeting_key` is written under both `user_id` and `userId`, so a targeting
  rule on either spelling matches. An explicit attribute of either spelling wins.
- `Time`, `Date` and `DateTime` attributes become ISO-8601 strings.
- `fetch_integer_value` accepts whole-number floats (`3.0` returns `3`).
  `fetch_float_value` accepts integers (`5` returns `5.0`).
  `fetch_object_value` accepts hashes and arrays only.
- An unmet prerequisite resolves with reason `PREREQUISITE_FAILED`. `ruleId` and
  `prerequisiteKey` are in `flag_metadata`.
- `PROVIDER_CONFIGURATION_CHANGED` fires with `flags_changed` whenever flag
  configuration changes after startup. The initial load does not fire it.

## Forking servers

On Puma with `preload_app!`, Unicorn or Passenger, register the provider in the
post-fork hook (`on_worker_boot` or `after_fork`). A provider built before the
fork leaves each worker with dead polling and streaming threads, so it serves
the boot snapshot and never emits `PROVIDER_CONFIGURATION_CHANGED`. If you pass
your own `client:`, call `client.restart` in that hook instead.

Full documentation: https://featureflip.io/docs/integrations/openfeature/#ruby

## License

Apache-2.0
