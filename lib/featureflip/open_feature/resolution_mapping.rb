module Featureflip
  module OpenFeature
    # Featureflip EvaluationDetail -> OpenFeature ResolutionDetails.
    module ResolutionMapping
      ResolutionDetails = ::OpenFeature::SDK::Provider::ResolutionDetails
      Reason = ::OpenFeature::SDK::Provider::Reason
      ErrorCode = ::OpenFeature::SDK::Provider::ErrorCode

      # No standard OpenFeature reason models an unmet prerequisite, and reasons
      # are open strings, so it is passed through rather than mislabeled DEFAULT
      # or DISABLED. Same choice as every other Featureflip provider.
      PREREQUISITE_FAILED = "PREREQUISITE_FAILED"

      REASONS = {
        "RuleMatch" => Reason::TARGETING_MATCH,
        "Fallthrough" => Reason::DEFAULT,
        "FlagDisabled" => Reason::DISABLED,
        "PrerequisiteFailed" => PREREQUISITE_FAILED
      }.freeze

      ERROR_CODES = {
        "FlagNotFound" => ErrorCode::FLAG_NOT_FOUND,
        "Error" => ErrorCode::GENERAL
      }.freeze

      ERROR_MESSAGES = {
        "FlagNotFound" => "Flag '%s' was not found",
        "Error" => "Flag '%s' could not be evaluated"
      }.freeze

      # A double represents every integer exactly only up to 2**53. Beyond it a
      # whole-looking float may be a rounded neighbor of the number that was
      # meant, so it is refused rather than handed back silently rounded.
      MAX_EXACT_INTEGER = 2**53

      MISMATCH = Object.new.freeze
      private_constant :MISMATCH

      module_function

      def to_resolution(flag_key, detail, default_value, type)
        error_code = ERROR_CODES[detail.reason]
        if error_code
          # The caller's default, never detail.value: an error detail can carry a
          # wrong-typed off variation (a failed prerequisite chain), which is not
          # what the OpenFeature error contract prescribes. The type guard is
          # skipped for the same reason; it would mislabel the error.
          return error(default_value, error_code, format(ERROR_MESSAGES.fetch(detail.reason), flag_key))
        end

        value = coerce(detail.value, type)
        if value.equal?(MISMATCH)
          return error(default_value, ErrorCode::TYPE_MISMATCH,
                       "Flag '#{flag_key}' did not resolve to #{article(type)} #{type} value")
        end

        ResolutionDetails.new(
          value: value,
          reason: REASONS.fetch(detail.reason, Reason::UNKNOWN),
          variant: detail.variation_key,
          flag_metadata: metadata(detail)
        )
      end

      def error(default_value, error_code, message)
        ResolutionDetails.new(value: default_value, reason: Reason::ERROR,
                              error_code: error_code, error_message: message)
      end

      def article(type)
        type.to_s.match?(/\A[aeiou]/i) ? "an" : "a"
      end

      def metadata(detail)
        { "ruleId" => detail.rule_id, "prerequisiteKey" => detail.prerequisite_key }.compact
      end

      def coerce(value, type)
        case type
        when :boolean then value == true || value == false ? value : MISMATCH
        when :string then value.is_a?(String) ? value : MISMATCH
        when :number then value.is_a?(Numeric) ? value : MISMATCH
        when :integer then to_integer(value)
        # The OpenFeature client checks is_a?(Float) strictly, so an integral
        # flag value must be widened here or the client reports a mismatch.
        when :float then value.is_a?(Integer) ? value.to_f : (value.is_a?(Float) ? value : MISMATCH)
        when :object then value.is_a?(Hash) || value.is_a?(Array) ? value : MISMATCH
        else raise ArgumentError, "unknown OpenFeature type #{type.inspect}"
        end
      end

      # JSON does not distinguish 1 from 1.0, and the engine renders whole floats
      # with a decimal part, so a whole Float is an integer here and is narrowed.
      def to_integer(value)
        return value if value.is_a?(Integer)
        return MISMATCH unless value.is_a?(Float) && value.finite? && value == value.truncate
        return MISMATCH if value.abs > MAX_EXACT_INTEGER

        value.to_i
      end
    end
  end
end
