module Featureflip
  module OpenFeature
    # OpenFeature server provider backed by the Featureflip Ruby SDK.
    #
    #   ::OpenFeature::SDK.set_provider_and_wait(
    #     Featureflip::OpenFeature::Provider.new(sdk_key: "sdk-...")
    #   )
    #
    # Prefer set_provider_and_wait: plain set_provider initializes on a
    # background thread and returns before flags load.
    class Provider
      include ::OpenFeature::SDK::Provider::EventEmitter

      NAME = "featureflip-ruby"

      attr_reader :metadata

      # Pass exactly one of:
      # - sdk_key: (with an optional Featureflip::Config). The provider builds the
      #   client in #init and closes it in #shutdown.
      # - client: an existing Featureflip::Client. The caller keeps ownership;
      #   #shutdown never closes it.
      def initialize(sdk_key: nil, config: nil, client: nil)
        raise ArgumentError, "pass exactly one of sdk_key: or client:" if sdk_key.nil? == client.nil?
        raise ArgumentError, "config: applies only with sdk_key:" if client && config

        @metadata = ::OpenFeature::SDK::Provider::ProviderMetadata.new(name: NAME).freeze
        @sdk_key = sdk_key
        @config = config
        @client = client
        @owns_client = client.nil?
        # Held across #init's blocking Client.get, so nothing on the SDK's update
        # thread may ever wait on it.
        @lifecycle_mutex = Mutex.new
        @unsubscribe = nil
        # Guards the fields below. Held only for a few assignments and never while
        # an app handler runs, because emit_event calls handlers inline.
        @state_mutex = Mutex.new
        @events_drained = ConditionVariable.new
        @shut_down = false
        # Bumped by #shutdown. A listener only emits for the generation it was
        # subscribed under, so a dispatch the SDK snapshotted before an
        # unsubscribe can never surface on a later subscription.
        @generation = 0
        @emitting = Hash.new(0) # thread => events it is delivering right now
      end

      # Builds the owned client here rather than in #new because Client.get blocks
      # on the first flag fetch, and that wait belongs inside
      # set_provider_and_wait. It is bounded by config.init_timeout and raises
      # Featureflip::InitializationError, which OpenFeature reports as
      # PROVIDER_ERROR. The evaluation context is unused: this is a
      # dynamic-context (server) provider.
      def init(_evaluation_context = nil)
        @lifecycle_mutex.synchronize do
          # Plain set_provider runs #init on a background thread, so replacing the
          # provider at once can run #shutdown first. Building a client now would
          # leave one nothing ever closes. Setting the provider again re-arms it
          # (see #attach).
          generation = @state_mutex.synchronize { @shut_down ? nil : @generation }
          return nil if generation.nil?

          @client ||= Featureflip::Client.get(@sdk_key, config: identified_config)
          # Subscribed after the client is ready, so the initial load is never a
          # "change" (OpenFeature signals it with PROVIDER_READY). Guarded because
          # OpenFeature may initialize a provider more than once. The listener can
          # fire before on_update returns; it checks the generation, not
          # @unsubscribe, so that change is still delivered.
          @unsubscribe ||= @client.on_update(->(keys) { on_flags_changed(keys, generation) })
        end
        nil
      end

      def shutdown
        @lifecycle_mutex.synchronize do
          @state_mutex.synchronize do
            @shut_down = true
            @generation += 1
          end
          # Always unsubscribe: the listener publishes on this provider's event
          # channel and must not outlive it, even on a borrowed client.
          @unsubscribe&.call
          @unsubscribe = nil
          # A borrowed client is a refcounted handle the caller still holds;
          # closing it would make THEIR handle start serving defaults.
          if @owns_client && @client
            @client.close
            @client = nil
          end
        end
        # Outside the lifecycle mutex: a handler still running may itself call
        # into this provider.
        wait_for_events_in_flight
        nil
      end

      def fetch_boolean_value(flag_key:, default_value:, evaluation_context: nil)
        resolve(:boolean, flag_key, default_value, evaluation_context)
      end

      def fetch_string_value(flag_key:, default_value:, evaluation_context: nil)
        resolve(:string, flag_key, default_value, evaluation_context)
      end

      def fetch_number_value(flag_key:, default_value:, evaluation_context: nil)
        resolve(:number, flag_key, default_value, evaluation_context)
      end

      def fetch_integer_value(flag_key:, default_value:, evaluation_context: nil)
        resolve(:integer, flag_key, default_value, evaluation_context)
      end

      def fetch_float_value(flag_key:, default_value:, evaluation_context: nil)
        resolve(:float, flag_key, default_value, evaluation_context)
      end

      def fetch_object_value(flag_key:, default_value:, evaluation_context: nil)
        resolve(:object, flag_key, default_value, evaluation_context)
      end

      # Called by openfeature-sdk 0.6.1+, the release that added the tracking API.
      # Earlier versions never call it.
      def track(tracking_event_name, evaluation_context: nil, tracking_event_details: nil)
        client = @client
        return if client.nil?

        metadata = nil
        if tracking_event_details
          metadata = tracking_event_details.fields.dup
          metadata["value"] = tracking_event_details.value unless tracking_event_details.value.nil?
        end
        client.track(tracking_event_name, ContextMapping.to_featureflip(evaluation_context), metadata)
      end

      private

      WRAPPER_NAME = "featureflip-openfeature-ruby"

      # The caller's config (or a default one) naming this provider as the SDK's
      # wrapper, so requests read "featureflip-ruby/<v> featureflip-openfeature-ruby/<v>"
      # (#4154). A copy, so a config the caller reuses for direct SDK clients is not
      # relabelled, with the SDK's memoized user agent cleared so the copy does not
      # inherit the caller's. A wrapper the caller already set is kept: the SDK
      # carries one, and theirs is the more specific. Only the sdk_key: form gets
      # here; a borrowed client was built before the provider saw it.
      def identified_config
        return @config if @config&.wrapper_name

        copy = @config ? @config.dup : Featureflip::Config.new
        copy.remove_instance_variable(:@user_agent) if copy.instance_variable_defined?(:@user_agent)
        copy.wrapper_name = WRAPPER_NAME
        copy.wrapper_version = VERSION
        copy
      end

      # Reads UNTYPED via variation_detail and applies the type guard here. The
      # SDK's typed accessors report a wrong-typed value as reason "Error", the
      # same reason a real failure carries, so TYPE_MISMATCH could not be told
      # apart from GENERAL through them.
      def resolve(type, flag_key, default_value, evaluation_context)
        client = @client
        if client.nil?
          return ResolutionMapping.error(default_value, ::OpenFeature::SDK::Provider::ErrorCode::PROVIDER_NOT_READY,
                                         "Featureflip provider has not been initialized")
        end

        detail = client.variation_detail(flag_key, ContextMapping.to_featureflip(evaluation_context), default_value)
        ResolutionMapping.to_resolution(flag_key, detail, default_value, type)
      rescue StandardError => e
        # The SDK rescues its own evaluation errors; this only catches a mapping
        # defect, which must still serve the caller's default.
        ResolutionMapping.error(default_value, ::OpenFeature::SDK::Provider::ErrorCode::GENERAL, e.message)
      end

      # OpenFeature attaches a provider every time it is set, always before the
      # #init that follows, so this is the one signal that a later #init is
      # legitimate rather than a stale one that lost the race to #shutdown.
      # Overrides the private EventEmitter#attach, which 0.5 and 0.6 both call.
      def attach(configuration)
        @state_mutex.synchronize { @shut_down = false }
        super
      end

      # Runs on the SDK's streaming/polling thread. Needs no rescue: Client#on_update
      # isolates and logs a raising listener.
      #
      # openfeature-sdk (0.5 and 0.6) never detaches a replaced provider, so an
      # event emitted after #shutdown would still reach every API-level handler.
      # The generation check and the in-flight count are taken together under
      # @state_mutex, and #shutdown bumps the generation under the same lock and
      # then waits for the count to drain: once #shutdown returns, no event from
      # this provider is being delivered and none can start.
      def on_flags_changed(keys, generation)
        @state_mutex.synchronize do
          return unless generation == @generation

          @emitting[Thread.current] += 1
        end
        begin
          emit_event(::OpenFeature::SDK::ProviderEvent::PROVIDER_CONFIGURATION_CHANGED, flags_changed: keys)
        ensure
          @state_mutex.synchronize do
            @emitting.delete(Thread.current) if (@emitting[Thread.current] -= 1).zero?
            @events_drained.broadcast
          end
        end
      end

      def wait_for_events_in_flight
        @state_mutex.synchronize do
          # A handler that shuts this provider down runs on the delivering thread.
          # Waiting for its own event would never return, so only other threads'
          # deliveries are waited out.
          @events_drained.wait(@state_mutex) while @emitting.any? { |thread, _| !thread.equal?(Thread.current) }
        end
      end
    end
  end
end
