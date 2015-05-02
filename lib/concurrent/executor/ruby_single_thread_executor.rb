require 'concurrent/executor/executor'
require 'concurrent/executor/executor_service'

module Concurrent

  # @!macro single_thread_executor
  # @!macro thread_pool_options
  class RubySingleThreadExecutor < RubyExecutorService
    include SerialExecutor

    # Create a new thread pool.
    #
    # @option opts [Symbol] :fallback_policy (:discard) the policy for
    #   handling new tasks that are received when the queue size has
    #   reached `max_queue` or after the executor has shut down
    #
    # @see http://docs.oracle.com/javase/tutorial/essential/concurrency/pools.html
    # @see http://docs.oracle.com/javase/7/docs/api/java/util/concurrent/Executors.html
    # @see http://docs.oracle.com/javase/8/docs/api/java/util/concurrent/ExecutorService.html
    def initialize(opts = {})
      super()
      @queue = Queue.new
      @thread = nil
      @fallback_policy = opts.fetch(:fallback_policy, :discard)
      raise ArgumentError.new("#{@fallback_policy} is not a valid fallback policy") unless FALLBACK_POLICIES.include?(@fallback_policy)
      self.auto_terminate = opts.fetch(:auto_terminate, true)
    end

    protected

    # @!visibility private
    def execute(*args, &task)
      supervise
      @queue << [args, task]
    end

    # @!visibility private
    def shutdown_execution
      @queue << :stop
      stopped_event.set unless alive?
    end

    # @!visibility private
    def kill_execution
      @queue.clear
      @thread.kill if alive?
    end

    # @!visibility private
    def alive?
      @thread && @thread.alive?
    end

    # @!visibility private
    def supervise
      @thread = new_worker_thread unless alive?
    end

    # @!visibility private
    def new_worker_thread
      Thread.new do
        Thread.current.abort_on_exception = false
        work
      end
    end

    # @!visibility private
    def work
      loop do
        task = @queue.pop
        break if task == :stop
        begin
          task.last.call(*task.first)
        rescue => ex
          # let it fail
          log DEBUG, ex
        end
      end
      stopped_event.set
    end
  end
end
