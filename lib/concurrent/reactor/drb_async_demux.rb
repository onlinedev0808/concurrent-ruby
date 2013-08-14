require 'drb/drb'
require 'drb/acl'
require 'functional'
require 'concurrent/reactor'

module Concurrent
  class Reactor

    class DRbAsyncDemux

      behavior(:async_event_demux)

      DEFAULT_URI = 'druby://localhost:12345'
      DEFAULT_ACL = %w[allow all]

      def initialize(opts = {})
        @uri = opts[:uri] || DEFAULT_URI
        @acl = ACL.new(opts[:acl] || DEFAULT_ACL)
      end

      def set_reactor(reactor)
        raise ArgumentError.new('invalid reactor') unless reactor.behaves_as?(:demux_reactor)
        @reactor = reactor
      end

      def start
        DRb.install_acl(@acl)
        @service = DRb.start_service(@uri, Demultiplexer.new(@reactor))
      end

      def stop
        @service = DRb.stop_service
      end

      def stopped?
        return @service.nil?
      end

      private

      class Demultiplexer

        def initialize(reactor)
          @reactor = reactor
        end

        Concurrent::Reactor::RESERVED_EVENTS.each do |event|
          define_method(event){|*args| false }
        end

        def method_missing(method, *args, &block)
          (class << self; self; end).class_eval do
            define_method(method) do |*args|
              result = @reactor.handle(method, *args)
              case result.first
              when :ok
                return result.last
              when :ex
                raise result.last
              when :noop
                raise NoMethodError.new("undefined method '#{method}' for #{self}")
              else
                raise DRb::DRbUnknownError.new("unexpected error when calling method '#{method}'")
              end
            end
          end
          self.send(method, *args)
        end
      end
    end

    DRbAsyncDemultiplexer = DRbAsyncDemux
  end
end
