require 'concurrent/actor'
require 'concurrent/stoppable'

module Concurrent

  class Channel < Actor
    include Stoppable

    def initialize(&block)
      raise ArgumentError.new('no block given') unless block_given?
      super()
      @task = block
    end

    protected

    def on_stop # :nodoc:
      stopper.call if stopper
      super
    end

    private

    def act(*message)
      return @task.call(*message)
    end
  end
end
