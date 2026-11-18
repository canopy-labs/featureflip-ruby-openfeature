require "spec_helper"

# The provider writes the targeting key only as user_id, the canonical
# spelling. A rule written against the userId spelling must still match, and
# it does because the SDK resolves either name to the same identity (#4518).
# These pair the provider's mapping with the SDK's own evaluator, so they fail
# if either half of that pairing regresses (#4546).
RSpec.describe "a targeting key against a rule on either user id spelling" do
  let(:evaluator) { Featureflip::Evaluation::Evaluator.new }

  def flag_targeting(attribute)
    Featureflip::Models::FlagConfiguration.new(
      key: "beta",
      version: 1,
      type: "Boolean",
      enabled: true,
      variations: [
        Featureflip::Models::Variation.new(key: "on", value: true),
        Featureflip::Models::Variation.new(key: "off", value: false)
      ],
      rules: [
        Featureflip::Models::TargetingRule.new(
          id: "r1",
          priority: 0,
          condition_groups: [
            Featureflip::Models::ConditionGroup.new(
              operator: "And",
              conditions: [
                Featureflip::Models::Condition.new(
                  attribute: attribute, operator: "Equals", values: ["user-42"], negate: false
                )
              ]
            )
          ],
          serve: Featureflip::Models::ServeConfig.new(type: "Fixed", variation: "on"),
          segment_key: nil
        )
      ],
      fallthrough: Featureflip::Models::ServeConfig.new(type: "Fixed", variation: "off"),
      off_variation: "off",
      prerequisites: []
    )
  end

  def evaluate(attribute, targeting_key)
    context = Featureflip::OpenFeature::ContextMapping.to_featureflip(
      ::OpenFeature::SDK::EvaluationContext.new(targeting_key: targeting_key)
    )
    evaluator.evaluate(flag_targeting(attribute), context)
  end

  %w[userId user_id].each do |attribute|
    it "matches a rule on #{attribute}" do
      result = evaluate(attribute, "user-42")
      expect(result.variation_key).to eq("on")
      expect(result.rule_id).to eq("r1")
    end
  end

  it "falls through for another targeting key, so the rule is what matched" do
    expect(evaluate("userId", "user-43").variation_key).to eq("off")
  end
end
