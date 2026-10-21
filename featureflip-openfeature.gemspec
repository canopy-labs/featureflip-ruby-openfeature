require_relative "lib/featureflip/open_feature/version"

Gem::Specification.new do |spec|
  spec.name = "featureflip-openfeature"
  spec.version = Featureflip::OpenFeature::VERSION
  spec.authors = ["Featureflip"]
  spec.summary = "OpenFeature provider for Featureflip"
  spec.description = "Use Featureflip feature flags through the OpenFeature Ruby SDK."
  spec.homepage = "https://featureflip.io/docs/integrations/openfeature/"
  spec.license = "Apache-2.0"
  spec.required_ruby_version = ">= 3.2.0"

  spec.metadata = {
    "homepage_uri" => "https://featureflip.io/docs/integrations/openfeature/",
    "documentation_uri" => "https://featureflip.io/docs/integrations/openfeature/",
    "source_code_uri" => "https://github.com/canopy-labs/featureflip-ruby-openfeature",
    "changelog_uri" => "https://github.com/canopy-labs/featureflip-ruby-openfeature/blob/master/CHANGELOG.md"
  }

  spec.files = Dir["lib/**/*.rb"] + %w[README.md CHANGELOG.md LICENSE]
  spec.require_paths = ["lib"]

  # 2.10 is the release that added Client#on_update, which the provider's
  # PROVIDER_CONFIGURATION_CHANGED is built on.
  spec.add_dependency "featureflip", "~> 2.11"
  # 0.5 added provider eventing and still supports Ruby 3.1+; 0.6 needs 3.4+.
  # The range therefore resolves on every Ruby the SDK supports. Upstream is
  # pre-1.0, so a 0.7 is allowed to break the provider interface; widen this
  # bound deliberately, not via a blind dependency bump.
  spec.add_dependency "openfeature-sdk", ">= 0.5", "< 0.7"

  spec.add_development_dependency "rspec", "~> 3.13"
end
