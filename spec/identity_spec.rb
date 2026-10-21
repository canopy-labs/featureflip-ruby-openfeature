require "spec_helper"

# The provider names itself after the SDK in the User-Agent (#4154, contract in
# #4138): "featureflip-ruby/<v> featureflip-openfeature-ruby/<v>", so OpenFeature
# usage can be counted apart from direct SDK use. The SDK's own specs prove that
# Config#user_agent is what reaches the wire; these prove the provider hands the
# SDK a config that produces it.
RSpec.describe Featureflip::OpenFeature::Provider, "identity" do
  let(:fake_client) { instance_double(Featureflip::Client, on_update: -> {}, close: nil) }
  let(:sdk_token) { "featureflip-ruby/#{Featureflip::VERSION}" }
  let(:provider_token) { "featureflip-openfeature-ruby/#{Featureflip::OpenFeature::VERSION}" }

  def config_passed_to_the_sdk(config)
    captured = nil
    allow(Featureflip::Client).to receive(:get) do |_key, config:|
      captured = config
      fake_client
    end
    described_class.new(sdk_key: "sdk-key", config: config).init
    captured
  end

  it "names the provider after the SDK token" do
    passed = config_passed_to_the_sdk(Featureflip::Config.new(streaming: false, send_events: false))

    expect(passed.user_agent).to eq("#{sdk_token} #{provider_token}")
  end

  it "names the provider when no config is given" do
    expect(config_passed_to_the_sdk(nil).user_agent).to eq("#{sdk_token} #{provider_token}")
  end

  it "leaves the caller's config untouched, even one whose user agent was already built" do
    # Config memoizes user_agent. A copy that carried the memo over would send the
    # caller's old value; the caller's own object must not be relabelled either.
    config = Featureflip::Config.new(streaming: false, send_events: false)
    config.user_agent

    passed = config_passed_to_the_sdk(config)

    expect(passed.user_agent).to eq("#{sdk_token} #{provider_token}")
    expect(config.wrapper_name).to be_nil
    expect(config.user_agent).to eq(sdk_token)
  end

  it "keeps a wrapper the caller already set" do
    # The SDK carries one wrapper token, and the caller's is the more specific.
    config = Featureflip::Config.new(streaming: false, send_events: false, wrapper_name: "acme-platform", wrapper_version: "3.1")

    expect(config_passed_to_the_sdk(config).user_agent).to eq("#{sdk_token} acme-platform/3.1")
  end
end
