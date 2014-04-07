require 'thread'

require 'concurrent/actor_ref'
require 'concurrent/ivar'

module Concurrent

  class SimpleActorRef
    include ActorRef

    def initialize(actor, opts = {})
      @actor = actor
      @mutex = Mutex.new
      @queue = Queue.new
      @thread = nil
      @stopped = false
      @abort_on_exception = opts.fetch(:abort_on_exception, true)
      @reset_on_error = opts.fetch(:reset_on_error, true)
      @exception_class = opts.fetch(:rescue_exception, false) ? Exception : StandardError
      @observers = CopyOnNotifyObserverSet.new
    end

    def running?
      @mutex.synchronize{ @stopped == false }
    end

    def shutdown?
      @mutex.synchronize{ @stopped == true }
    end

    def post(*msg, &block)
      raise ArgumentError.new('message cannot be empty') if msg.empty?
      @mutex.synchronize do
        supervise unless @stopped == true
      end
      ivar = IVar.new
      @queue.push(Message.new(msg, ivar, block))
      ivar
    end

    def post!(seconds, *msg)
      raise Concurrent::TimeoutError if seconds == 0
      ivar = self.post(*msg)
      ivar.value(seconds)
      if ivar.incomplete?
        raise Concurrent::TimeoutError
      elsif ivar.reason
        raise ivar.reason
      end
      ivar.value
    end

    def shutdown
      @mutex.synchronize do
        return if @stopped
        @stopped = true
        if @thread && @thread.alive?
          @thread.kill 
          @actor.on_shutdown
        end
      end
    end

    private

    Message = Struct.new(:payload, :ivar, :callback)

    def supervise
      if @thread.nil?
        @actor.on_start
        @thread = new_worker_thread
      elsif ! @thread.alive?
        @actor.on_reset
        @thread = new_worker_thread
      end
    end

    def new_worker_thread
      Thread.new do
        Thread.current.abort_on_exception = @abort_on_exception
        run_message_loop
      end
    end

    def run_message_loop
      loop do
        message = @queue.pop
        result = ex = nil

        begin
          result = @actor.receive(*message.payload)
        rescue @exception_class => ex
          @actor.on_reset if @reset_on_error
        ensure
          now = Time.now
          message.ivar.complete(ex.nil?, result, ex)
          message.callback.call(now, result, ex) if message.callback
          observers.notify_observers(now, message.payload, result, ex)
        end
      end
    end
  end
end
