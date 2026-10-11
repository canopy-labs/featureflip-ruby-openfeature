source "https://rubygems.org"

# CI builds the provider against the in-repo SDK by setting FEATUREFLIP_SDK_PATH.
# Everyone else (the public mirror, a customer's checkout, the publish
# workflow's verify job) leaves it unset and resolves `featureflip` from
# RubyGems through the gemspec. Never make this unconditional: the mirror has
# no ../ruby-sdk, and the package would be uninstallable there.
sdk_path = ENV.fetch("FEATUREFLIP_SDK_PATH", "")
gem "featureflip", path: sdk_path unless sdk_path.empty?

gemspec
