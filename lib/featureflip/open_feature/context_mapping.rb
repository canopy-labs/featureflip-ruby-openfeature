require "date"
require "time"

module Featureflip
  module OpenFeature
    # OpenFeature evaluation context -> the Featureflip SDK's context hash.
    module ContextMapping
      TARGETING_KEY = "targeting_key"
      IDENTITY_KEYS = %w[user_id userId].freeze

      module_function

      def to_featureflip(evaluation_context)
        return {} if evaluation_context.nil?

        fields = evaluation_context.fields
        # The reserved key is OpenFeature's, not an attribute: leaking it into
        # the bag is a recorded .NET-provider bug.
        context = fields.each_with_object({}) do |(key, value), out|
          out[key] = render(value) unless key == TARGETING_KEY
        end

        targeting_key = fields[TARGETING_KEY]
        blank = targeting_key.nil? || (targeting_key.respond_to?(:empty?) && targeting_key.empty?)
        # BOTH spellings, because the Ruby SDK's condition evaluator reads
        # context[attribute] exactly; the userId/user_id alias exists only on
        # the bucketing path. A rule on either spelling must match. An explicit
        # attribute of either spelling wins and nothing is overwritten.
        if !blank && IDENTITY_KEYS.none? { |k| context.key?(k) }
          IDENTITY_KEYS.each { |k| context[k] = targeting_key }
        end
        context
      end

      # Every SDK gates its date operators on the ISO grammar, so a Time left as
      # an object would match no date rule at all.
      def render(value)
        case value
        when Time, Date then value.iso8601 # DateTime < Date, so it lands here too
        when Hash then value.transform_values { |v| render(v) }
        when Array then value.map { |v| render(v) }
        else value
        end
      end
    end
  end
end
