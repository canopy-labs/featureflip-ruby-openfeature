RSpec.describe Featureflip::OpenFeature::ResolutionMapping do
  Reason = ::OpenFeature::SDK::Provider::Reason unless defined?(Reason)
  ErrorCode = ::OpenFeature::SDK::Provider::ErrorCode unless defined?(ErrorCode)

  def detail(value, reason, **rest)
    Featureflip::Models::EvaluationDetail.new(value: value, reason: reason, **rest)
  end

  def resolve(value, reason = "Fallthrough", type: :boolean, default: false, **rest)
    described_class.to_resolution("my-flag", detail(value, reason, **rest), default, type)
  end

  describe "reasons" do
    {
      "RuleMatch" => Reason::TARGETING_MATCH,
      "Fallthrough" => Reason::DEFAULT,
      "FlagDisabled" => Reason::DISABLED,
      "PrerequisiteFailed" => "PREREQUISITE_FAILED",
      "SomethingNew" => Reason::UNKNOWN
    }.each do |featureflip, open_feature|
      it "maps #{featureflip} to #{open_feature}" do
        result = resolve(true, featureflip)
        expect(result.reason).to eq(open_feature)
        expect(result.error_code).to be_nil
        expect(result.value).to be(true)
      end
    end

    it "maps FlagNotFound to an ERROR with FLAG_NOT_FOUND and the caller's default" do
      result = resolve("off-variation", "FlagNotFound", default: false)
      expect([result.value, result.reason, result.error_code]).to eq([false, Reason::ERROR, ErrorCode::FLAG_NOT_FOUND])
    end

    it "maps Error to GENERAL and substitutes the default even for a wrong-typed served value" do
      result = resolve("not-a-bool", "Error", default: true)
      expect([result.value, result.reason, result.error_code]).to eq([true, Reason::ERROR, ErrorCode::GENERAL])
    end
  end

  describe "variant and metadata" do
    it "exposes the variation key, rule id and prerequisite key" do
      result = resolve(true, "RuleMatch", variation_key: "on", rule_id: "rule-1")
      expect(result.variant).to eq("on")
      expect(result.flag_metadata).to eq("ruleId" => "rule-1")

      prereq = resolve(false, "PrerequisiteFailed", variation_key: "off", prerequisite_key: "parent")
      expect(prereq.flag_metadata).to eq("prerequisiteKey" => "parent")
    end

    it "omits absent metadata" do
      expect(resolve(true).flag_metadata).to eq({})
    end
  end

  describe "type guards" do
    it "accepts only true/false for boolean" do
      expect(resolve(false).value).to be(false)
      expect(resolve(1).error_code).to eq(ErrorCode::TYPE_MISMATCH)
      expect(resolve("true").error_code).to eq(ErrorCode::TYPE_MISMATCH)
    end

    it "accepts only strings for string" do
      expect(resolve("hi", type: :string, default: "").value).to eq("hi")
      expect(resolve(42, type: :string, default: "").error_code).to eq(ErrorCode::TYPE_MISMATCH)
    end

    it "accepts any Numeric for number" do
      expect(resolve(1, type: :number, default: 0).value).to eq(1)
      expect(resolve(1.5, type: :number, default: 0).value).to eq(1.5)
      expect(resolve(true, type: :number, default: 0).error_code).to eq(ErrorCode::TYPE_MISMATCH)
    end

    it "accepts an Integer, and narrows a whole Float, for integer" do
      expect(resolve(7, type: :integer, default: 0).value).to eql(7)
      expect(resolve(3.0, type: :integer, default: 0).value).to eql(3)
      expect(resolve(-(2**53).to_f, type: :integer, default: 0).value).to eql(-(2**53))
    end

    it "rejects a fractional, non-finite or out-of-exact-range Float for integer" do
      [1.5, Float::NAN, Float::INFINITY, 1e20].each do |bad|
        result = resolve(bad, type: :integer, default: 0)
        expect([result.value, result.error_code]).to eq([0, ErrorCode::TYPE_MISMATCH]), "accepted #{bad.inspect}"
      end
    end

    it "widens an Integer to a Float for float" do
      expect(resolve(5, type: :float, default: 0.0).value).to eql(5.0)
      expect(resolve(2.5, type: :float, default: 0.0).value).to eql(2.5)
      expect(resolve("5", type: :float, default: 0.0).error_code).to eq(ErrorCode::TYPE_MISMATCH)
    end

    it "accepts only Hash or Array for object" do
      expect(resolve({ "a" => 1 }, type: :object, default: {}).value).to eq("a" => 1)
      expect(resolve([1], type: :object, default: {}).value).to eq([1])
      expect(resolve("{}", type: :object, default: {}).error_code).to eq(ErrorCode::TYPE_MISMATCH)
    end

    it "reports a mismatch with the default, an ERROR reason and a message naming flag and type" do
      result = resolve("nope", type: :integer, default: 9)
      expect(result.value).to eq(9)
      expect(result.reason).to eq(Reason::ERROR)
      expect(result.variant).to be_nil
      expect(result.error_message).to eq("Flag 'my-flag' did not resolve to an integer value")
    end

    it "skips the guard on error reasons rather than mislabeling them TYPE_MISMATCH" do
      expect(resolve(42, "Error", type: :string, default: "d").error_code).to eq(ErrorCode::GENERAL)
    end
  end

  it "builds a bare error resolution" do
    result = described_class.error(false, ErrorCode::PROVIDER_NOT_READY, "not ready")
    expect([result.value, result.reason, result.error_code, result.error_message])
      .to eq([false, Reason::ERROR, ErrorCode::PROVIDER_NOT_READY, "not ready"])
  end
end
