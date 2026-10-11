RSpec.describe Featureflip::OpenFeature::Provider do
  SDK = ::OpenFeature::SDK unless defined?(SDK)

  let(:flags) do
    {
      "bool-flag" => true, "string-flag" => "hello", "int-flag" => 5,
      "whole-flag" => 3.0, "float-flag" => 2.5, "object-flag" => { "a" => 1 }
    }
  end
  let(:test_client) { Featureflip::Client.for_testing(flags) }

  def openfeature_client_for(provider)
    SDK.set_provider_and_wait(provider)
    SDK.build_client
  end

  describe "construction" do
    it "requires exactly one of sdk_key: and client:" do
      expect { described_class.new }.to raise_error(ArgumentError, /exactly one/)
      expect { described_class.new(sdk_key: "k", client: test_client) }.to raise_error(ArgumentError, /exactly one/)
    end

    it "rejects config: without sdk_key:" do
      expect { described_class.new(client: test_client, config: Featureflip::Config.new) }
        .to raise_error(ArgumentError, /config: applies only with sdk_key:/)
    end

    it "reports its name" do
      expect(described_class.new(client: test_client).metadata.name).to eq("featureflip-ruby")
    end
  end

  describe "resolution through the real OpenFeature client" do
    let(:of) { openfeature_client_for(described_class.new(client: test_client)) }

    it "resolves each type" do
      expect(of.fetch_boolean_value(flag_key: "bool-flag", default_value: false)).to be(true)
      expect(of.fetch_string_value(flag_key: "string-flag", default_value: "")).to eq("hello")
      expect(of.fetch_number_value(flag_key: "float-flag", default_value: 0)).to eq(2.5)
      expect(of.fetch_object_value(flag_key: "object-flag", default_value: {})).to eq("a" => 1)
    end

    it "narrows a whole float for an integer read and widens an integer for a float read" do
      expect(of.fetch_integer_value(flag_key: "whole-flag", default_value: 0)).to eql(3)
      expect(of.fetch_float_value(flag_key: "int-flag", default_value: 0.0)).to eql(5.0)
    end

    it "reports DEFAULT for a served flag" do
      details = of.fetch_boolean_details(flag_key: "bool-flag", default_value: false)
      expect(details.reason).to eq(SDK::Provider::Reason::DEFAULT)
    end

    it "returns the default with FLAG_NOT_FOUND for a missing flag" do
      details = of.fetch_boolean_details(flag_key: "missing", default_value: true)
      expect([details.value, details.error_code]).to eq([true, SDK::Provider::ErrorCode::FLAG_NOT_FOUND])
    end

    it "returns the default with TYPE_MISMATCH for a wrong-typed read" do
      details = of.fetch_boolean_details(flag_key: "string-flag", default_value: false)
      expect([details.value, details.error_code]).to eq([false, SDK::Provider::ErrorCode::TYPE_MISMATCH])
    end
  end

  describe "fetch before init" do
    it "returns PROVIDER_NOT_READY for an owned client that was never initialized" do
      result = described_class.new(sdk_key: "k").fetch_boolean_value(flag_key: "x", default_value: true)
      expect([result.value, result.error_code]).to eq([true, SDK::Provider::ErrorCode::PROVIDER_NOT_READY])
    end
  end

  describe "lifecycle" do
    let(:unsubscribe) { instance_double(Proc, call: nil) }
    let(:fake_client) { instance_double(Featureflip::Client, on_update: unsubscribe, close: nil) }

    it "builds and owns a client from sdk_key in init, and closes it in shutdown" do
      config = Featureflip::Config.new(streaming: false, send_events: false)
      allow(Featureflip::Client).to receive(:get).with("sdk-key", config: config).and_return(fake_client)
      provider = described_class.new(sdk_key: "sdk-key", config: config)
      expect(Featureflip::Client).not_to have_received(:get)

      provider.init
      provider.shutdown
      expect(unsubscribe).to have_received(:call)
      expect(fake_client).to have_received(:close)
    end

    it "never closes a borrowed client, but still unsubscribes" do
      provider = described_class.new(client: fake_client)
      provider.init
      provider.shutdown
      expect(unsubscribe).to have_received(:call)
      expect(fake_client).not_to have_received(:close)
    end

    it "leaves a borrowed real client usable after the provider shuts down" do
      provider = described_class.new(client: test_client)
      openfeature_client_for(provider)
      provider.shutdown # what OpenFeature calls on teardown (0.5 has no public API shutdown)
      expect(test_client.bool_variation("bool-flag", {}, false)).to be(true)
    end

    it "subscribes once across repeated init" do
      provider = described_class.new(client: fake_client)
      provider.init
      provider.init
      expect(fake_client).to have_received(:on_update).once
    end

    it "fails set_provider_and_wait when the client cannot initialize" do
      allow(Featureflip::Client).to receive(:get)
        .and_raise(Featureflip::InitializationError, "Initialization timed out after 1s")
      expect { SDK.set_provider_and_wait(described_class.new(sdk_key: "bad")) }
        .to raise_error(SDK::ProviderInitializationError)
    end
  end

  describe "events" do
    it "emits PROVIDER_CONFIGURATION_CHANGED with the keys the SDK reports" do
      listener = nil
      fake = instance_double(Featureflip::Client, close: nil)
      allow(fake).to receive(:on_update) { |callable| listener = callable; -> {} }

      events = Queue.new
      handler = ->(details) { events << details }
      SDK.add_handler(SDK::ProviderEvent::PROVIDER_CONFIGURATION_CHANGED, handler)
      begin
        SDK.set_provider_and_wait(described_class.new(client: fake))
        listener.call(%w[a b])
        expect(events.pop(timeout: 2)).to include(flags_changed: %w[a b])
      ensure
        SDK.remove_handler(SDK::ProviderEvent::PROVIDER_CONFIGURATION_CHANGED, handler)
      end
    end
  end

  describe "events after shutdown" do
    it "does not leak a late event from a shut-down provider to handlers" do
      listener = nil
      fake = instance_double(Featureflip::Client, close: nil)
      allow(fake).to receive(:on_update) { |callable| listener = callable; -> {} }
      provider = described_class.new(client: fake)

      events = Queue.new
      handler = ->(details) { events << details }
      SDK.add_handler(SDK::ProviderEvent::PROVIDER_CONFIGURATION_CHANGED, handler)
      begin
        SDK.set_provider_and_wait(provider)
        provider.shutdown
        listener.call(%w[late])
        expect(events.pop(timeout: 0.5)).to be_nil
      ensure
        SDK.remove_handler(SDK::ProviderEvent::PROVIDER_CONFIGURATION_CHANGED, handler)
      end
    end

    # A dispatch that passed the check before #shutdown must finish before
    # #shutdown returns, or it reaches the app's handlers after the provider was
    # replaced: openfeature-sdk never detaches a provider it replaces.
    it "makes shutdown wait for an event already being delivered" do
      listener = nil
      fake = instance_double(Featureflip::Client, close: nil)
      allow(fake).to receive(:on_update) { |callable| listener = callable; -> {} }
      provider = described_class.new(client: fake)

      entered = Queue.new
      gate = Queue.new
      handler = lambda do |_details|
        entered << true
        gate.pop
      end
      SDK.add_handler(SDK::ProviderEvent::PROVIDER_CONFIGURATION_CHANGED, handler)
      begin
        SDK.set_provider_and_wait(provider)
        dispatch = Thread.new { listener.call(%w[a]) }
        entered.pop(timeout: 2) or raise "the event never reached the handler"

        shutdown = Thread.new { provider.shutdown }
        expect(shutdown.join(0.3)).to be_nil # still waiting on the in-flight event

        gate << true
        expect(shutdown.join(2)).to eq(shutdown)
        dispatch.join(2)
      ensure
        gate << true
        SDK.remove_handler(SDK::ProviderEvent::PROVIDER_CONFIGURATION_CHANGED, handler)
      end
    end

    it "lets a handler shut the provider down from inside its own event" do
      listener = nil
      fake = instance_double(Featureflip::Client, close: nil)
      allow(fake).to receive(:on_update) { |callable| listener = callable; -> {} }
      provider = described_class.new(client: fake)

      handler = ->(_details) { provider.shutdown }
      SDK.add_handler(SDK::ProviderEvent::PROVIDER_CONFIGURATION_CHANGED, handler)
      begin
        SDK.set_provider_and_wait(provider)
        dispatch = Thread.new { listener.call(%w[a]) }
        expect(dispatch.join(2)).to eq(dispatch) # no self-deadlock
      ensure
        SDK.remove_handler(SDK::ProviderEvent::PROVIDER_CONFIGURATION_CHANGED, handler)
      end
    end
  end

  describe "events during init" do
    # The SDK's polling or streaming thread can fire the listener the instant it
    # is registered, before #on_update has even returned the unsubscribe handle.
    it "delivers a change the SDK reports while the subscription is being registered" do
      fake = instance_double(Featureflip::Client, close: nil)
      allow(fake).to receive(:on_update) do |callable|
        callable.call(%w[early])
        -> {}
      end

      events = Queue.new
      handler = ->(details) { events << details }
      SDK.add_handler(SDK::ProviderEvent::PROVIDER_CONFIGURATION_CHANGED, handler)
      begin
        SDK.set_provider_and_wait(described_class.new(client: fake))
        expect(events.pop(timeout: 2)).to include(flags_changed: %w[early])
      ensure
        SDK.remove_handler(SDK::ProviderEvent::PROVIDER_CONFIGURATION_CHANGED, handler)
      end
    end
  end

  describe "init after shutdown" do
    # Plain set_provider runs #init on a background thread, so a set_provider
    # that replaces the provider at once can run #shutdown first. That #init
    # belongs to a provider nobody holds any more.
    it "does not build an owned client once shutdown has run" do
      allow(Featureflip::Client).to receive(:get)
      provider = described_class.new(sdk_key: "sdk-key")

      provider.shutdown
      provider.init

      expect(Featureflip::Client).not_to have_received(:get)
      result = provider.fetch_boolean_value(flag_key: "bool-flag", default_value: false)
      expect(result.error_code).to eq(SDK::Provider::ErrorCode::PROVIDER_NOT_READY)
    end

    it "initializes again when OpenFeature sets the provider again" do
      allow(Featureflip::Client).to receive(:get) { Featureflip::Client.for_testing(flags) }
      provider = described_class.new(sdk_key: "sdk-key")

      SDK.set_provider_and_wait(provider)
      SDK.set_provider_and_wait(SDK::Provider::NoOpProvider.new) # shuts it down
      of = openfeature_client_for(provider)

      expect(Featureflip::Client).to have_received(:get).twice
      expect(of.fetch_boolean_value(flag_key: "bool-flag", default_value: false)).to be(true)
    end

    it "drops a change from the previous subscription once re-initialized" do
      listeners = []
      fake = instance_double(Featureflip::Client, close: nil)
      allow(fake).to receive(:on_update) { |callable| listeners << callable; -> {} }
      provider = described_class.new(client: fake)

      events = Queue.new
      handler = ->(details) { events << details }
      SDK.add_handler(SDK::ProviderEvent::PROVIDER_CONFIGURATION_CHANGED, handler)
      begin
        SDK.set_provider_and_wait(provider)
        SDK.set_provider_and_wait(SDK::Provider::NoOpProvider.new)
        SDK.set_provider_and_wait(provider)
        expect(listeners.size).to eq(2)

        listeners.first.call(%w[stale]) # a dispatch the SDK snapshotted before the unsubscribe
        listeners.last.call(%w[fresh])
        expect(events.pop(timeout: 2)).to include(flags_changed: %w[fresh])
        expect(events.pop(timeout: 0.3)).to be_nil
      ensure
        SDK.remove_handler(SDK::ProviderEvent::PROVIDER_CONFIGURATION_CHANGED, handler)
      end
    end
  end

  describe "evaluation failure" do
    it "serves the default with GENERAL when the client raises" do
      fake = instance_double(Featureflip::Client, on_update: -> {})
      allow(fake).to receive(:variation_detail).and_raise(RuntimeError, "boom")
      provider = described_class.new(client: fake)
      provider.init
      result = provider.fetch_boolean_value(flag_key: "x", default_value: true)
      expect([result.value, result.error_code, result.error_message])
        .to eq([true, SDK::Provider::ErrorCode::GENERAL, "boom"])
    end
  end

  describe "#track" do
    it "forwards the event, the mapped context and the details as metadata" do
      fake = instance_double(Featureflip::Client, on_update: -> {}, track: nil)
      provider = described_class.new(client: fake)
      details = Struct.new(:value, :fields).new(9.99, { "plan" => "pro" })
      provider.track(
        "purchase",
        evaluation_context: SDK::EvaluationContext.new(targeting_key: "u1"),
        tracking_event_details: details
      )
      expect(fake).to have_received(:track)
        .with("purchase", { "user_id" => "u1", "userId" => "u1" }, { "plan" => "pro", "value" => 9.99 })
    end
  end
end
