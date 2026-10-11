RSpec.describe "featureflip-openfeature" do
  it "loads both SDKs and reports its version" do
    expect(Featureflip::OpenFeature::VERSION).to match(/\A\d+\.\d+\.\d+/)
    expect(defined?(::OpenFeature::SDK::Provider::EventEmitter)).to eq("constant")
    expect(Featureflip::Client.instance_methods).to include(:on_update)
  end
end
