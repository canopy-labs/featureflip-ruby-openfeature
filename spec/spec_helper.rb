require "featureflip-openfeature"

RSpec.configure do |config|
  config.expect_with :rspec do |expectations|
    expectations.include_chain_clauses_in_custom_matcher_descriptions = true
  end

  # OpenFeature's configuration is process-global. Reset it between examples so
  # a provider (or handler) registered by one example cannot answer another's.
  # `reset` is PRIVATE in openfeature-sdk 0.5.x and 0.5 has no public shutdown,
  # hence `send`; it exists under the same name on 0.5 and 0.6.
  config.after(:each) do
    ::OpenFeature::SDK.configuration.send(:reset)
    Featureflip::SharedCore._reset_for_testing
  end
end
