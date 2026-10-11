require "date"

RSpec.describe Featureflip::OpenFeature::ContextMapping do
  def ctx(**fields) = ::OpenFeature::SDK::EvaluationContext.new(**fields)

  it "maps a nil context to an empty, anonymous context" do
    expect(described_class.to_featureflip(nil)).to eq({})
  end

  it "writes targeting_key under both identity spellings and drops the reserved key" do
    mapped = described_class.to_featureflip(ctx(targeting_key: "user-42", plan: "pro"))
    expect(mapped).to eq("user_id" => "user-42", "userId" => "user-42", "plan" => "pro")
  end

  it "leaves an explicit identity attribute alone, whichever spelling it uses" do
    expect(described_class.to_featureflip(ctx(targeting_key: "tk", user_id: "explicit")))
      .to eq("user_id" => "explicit")
    expect(described_class.to_featureflip(ctx(targeting_key: "tk", userId: "explicit")))
      .to eq("userId" => "explicit")
  end

  it "writes no identity for a blank targeting key" do
    expect(described_class.to_featureflip(ctx(targeting_key: "", plan: "pro"))).to eq("plan" => "pro")
  end

  it "passes a numeric targeting key through unconverted" do
    # Ruby never widens 12345 to 12345.0, so the Java bucketing hazard (the same
    # user split two ways by "12345" vs "12345.0") cannot arise. Recorded here.
    mapped = described_class.to_featureflip(ctx(targeting_key: 12_345))
    expect(mapped["user_id"]).to eql(12_345)
  end

  it "renders Time, Date and DateTime as ISO-8601, recursing into nested values" do
    time = Time.utc(2026, 10, 9, 12, 30, 0)
    mapped = described_class.to_featureflip(
      ctx(
        signed_up: time,
        birthday: Date.new(1990, 1, 2),
        nested: { "at" => DateTime.new(2026, 1, 2, 3, 4, 5), "list" => [time] }
      )
    )
    expect(mapped["signed_up"]).to eq("2026-10-09T12:30:00Z")
    expect(mapped["birthday"]).to eq("1990-01-02")
    expect(mapped["nested"]).to eq("at" => "2026-01-02T03:04:05+00:00", "list" => ["2026-10-09T12:30:00Z"])
  end

  it "passes other values through untouched" do
    mapped = described_class.to_featureflip(ctx(age: 30, beta: true, tags: %w[a b]))
    expect(mapped).to eq("age" => 30, "beta" => true, "tags" => %w[a b])
  end
end
