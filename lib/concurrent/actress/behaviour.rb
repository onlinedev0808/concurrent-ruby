module Concurrent
  module Actress
    # TODO split this into files

    module ContextDelegations
      include CoreDelegations

      # @see Actress.spawn
      def spawn(*args, &block)
        Actress.spawn(*args, &block)
      end

      # @see Core#children
      def children
        core.children
      end

      # @see Core#terminate!
      def terminate!
        core.terminate!
      end

      # delegates to core.log
      # @see Logging#log
      def log(level, message = nil, &block)
        core.log(level, message, &block)
      end

      def dead_letter_routing
        context.dead_letter_routing
      end

      def core
        context.core
      end

      def redirect(reference, envelope = self.envelope)
        reference.message(envelope.message, envelope.ivar)
        Behaviour::NOT_PROCESSED
      end
    end

    module Behaviour
      NOT_PROCESSED = Object.new

      class Abstract
        include TypeCheck
        include ContextDelegations

        attr_reader :context, :subsequent

        def initialize(context, subsequent)
          @context    = Type! context, Context
          @subsequent = Type! subsequent, Abstract, NilClass
        end

        def on_message(message)
          raise NotImplementedError
        end

        # @api private
        def on_envelope(envelope)
          raise NotImplementedError
        end

        def pass(envelope = self.envelope)
          log Logging::DEBUG, "passing #{envelope.message} to #{subsequent.class}"
          subsequent.on_envelope envelope
        end

        def reject_messages
          subsequent.reject_messages if subsequent
        end

        def reject_envelope(envelope)
          envelope.reject! ActorTerminated.new(reference)
          dead_letter_routing << envelope unless envelope.ivar
        end
      end

      class Termination < Abstract
        attr_reader :terminated

        def initialize(context, subsequent)
          super context, subsequent
          @terminated = Event.new
        end

        # @note Actor rejects envelopes when terminated.
        # @return [true, false] if actor is terminated
        def terminated?
          @terminated.set?
        end

        def on_envelope(envelope)
          if terminated?
            reject_envelope envelope
            NOT_PROCESSED
          else
            if envelope.message == :terminate!
              terminate!
            else
              pass envelope
            end
          end
        end

        # Terminates the actor. Any Envelope received after termination is rejected.
        # Terminates all its children, does not wait until they are terminated.
        def terminate!
          return nil if terminated?
          children.each { |ch| ch << :terminate! }
          @terminated.set
          parent << :remove_child if parent
          core.reject_messages
          nil
        end
      end

      class RemoveChild < Abstract
        def on_envelope(envelope)
          if envelope.message == :remove_child
            core.remove_child envelope.sender
          else
            pass envelope
          end
        end
      end

      class SetResults < Abstract
        def on_envelope(envelope)
          result = pass envelope
          if result != NOT_PROCESSED && !envelope.ivar.nil?
            envelope.ivar.set result
          end
          nil
        rescue => error
          log Logging::ERROR, error
          terminate!
          envelope.ivar.fail error unless envelope.ivar.nil?
        end
      end

      class Buffer < Abstract
        def initialize(context, subsequent)
          super context, SetResults.new(context, subsequent)
          @buffer                     = []
          @receive_envelope_scheduled = false
        end

        def on_envelope(envelope)
          @buffer.push envelope
          process_envelopes?
          NOT_PROCESSED
        end

        # Ensures that only one envelope processing is scheduled with #schedule_execution,
        # this allows other scheduled blocks to be executed before next envelope processing.
        # Simply put this ensures that Core is still responsive to internal calls (like add_child)
        # even though the Actor is flooded with messages.
        def process_envelopes?
          unless @buffer.empty? || @receive_envelope_scheduled
            @receive_envelope_scheduled = true
            schedule_execution { receive_envelope }
          end
        end

        def receive_envelope
          envelope = @buffer.shift
          return nil unless envelope
          pass envelope
        ensure
          @receive_envelope_scheduled = false
          process_envelopes?
        end

        def reject_messages
          @buffer.each do |envelope|
            reject_envelope envelope
            log Logging::DEBUG, "rejected #{envelope.message} from #{envelope.sender_path}"
          end
          @buffer.clear
          super
        end

        def schedule_execution(&block)
          core.schedule_execution &block
        end
      end

      class DoContext < Abstract
        def on_envelope(envelope)
          context.on_envelope envelope || pass
        end
      end

      class ErrorOnUnknownMessage < Abstract
        def on_envelope(envelope)
          raise "unknown message #{envelope.message.inspect}"
        end
      end

    end
  end
end
