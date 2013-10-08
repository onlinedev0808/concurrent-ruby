require 'thread'
require 'functional'

behavior_info(:runnable,
              run: 0,
              stop: 0,
              running?: 0)

module Concurrent

  module Running

    class Context
      attr_reader :runner, :thread
      def initialize(runner)
        @runner = runner
        @thread = Thread.new(runner) do |runner|
          Thread.abort_on_exception = false
          runner.run
        end
      end
    end

    def self.included(base)

      def run!
        return mutex.synchronize do
          raise LifecycleError.new('already running') if @running
          Context.new(self)
        end
      end

      protected

      def mutex
        @mutex ||= Mutex.new
      end

      public

      class << base

        def run!(*args, &block)
          runner = self.new(*args, &block)
          return Context.new(runner)
        rescue => ex
          return nil
        end
      end
    end
  end

  module Runnable

    behavior(:runnable)

    LifecycleError = Class.new(StandardError)

    def self.included(base)
      base.send(:include, Running)
    end

    def run
      mutex.synchronize do
        raise LifecycleError.new('already running') if @running
        raise LifecycleError.new('#on_task not implemented') unless self.respond_to?(:on_task, true)
        on_run if respond_to?(:on_run, true)
        @running = true
      end

      loop do
        break unless @running
        on_task
        break unless @running
        Thread.pass
      end

      after_run if respond_to?(:after_run, true)
      return true
    rescue LifecycleError => ex
      @running = false
      raise ex
    rescue => ex
      @running = false
      return false
    end

    def stop
      return true unless @running
      mutex.synchronize do
        @running = false
        on_stop if respond_to?(:on_stop, true)
      end
      return true
    rescue => ex
      return false
    end

    def running?
      return @running == true
    end
  end
end
