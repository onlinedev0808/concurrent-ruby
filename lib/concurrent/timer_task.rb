require 'concurrent/dereferenceable'
require 'concurrent/observable'
require 'concurrent/atomic/atomic_boolean'
require 'concurrent/executor/executor'
require 'concurrent/executor/safe_task_executor'

module Concurrent

  # A very common currency pattern is to run a thread that performs a task at regular
  # intervals. The thread that performs the task sleeps for the given interval then
  # wakes up and performs the task. Lather, rinse, repeat... This pattern causes two
  # problems. First, it is difficult to test the business logic of the task because the
  # task itself is tightly coupled with the concurrency logic. Second, an exception
  # raised while performing the task can cause the entire thread to abend. In a
  # long-running application where the task thread is intended to run for days/weeks/years
  # a crashed task thread can pose a significant problem. `TimerTask` alleviates both problems.
  # 
  # When a `TimerTask` is launched it starts a thread for monitoring the execution interval.
  # The `TimerTask` thread does not perform the task, however. Instead, the TimerTask
  # launches the task on a separate thread. Should the task experience an unrecoverable
  # crash only the task thread will crash. This makes the `TimerTask` very fault tolerant
  # Additionally, the `TimerTask` thread can respond to the success or failure of the task,
  # performing logging or ancillary operations. `TimerTask` can also be configured with a
  # timeout value allowing it to kill a task that runs too long.
  # 
  # One other advantage of `TimerTask` is that it forces the business logic to be completely decoupled
  # from the concurrency logic. The business logic can be tested separately then passed to the
  # `TimerTask` for scheduling and running.
  # 
  # In some cases it may be necessary for a `TimerTask` to affect its own execution cycle.
  # To facilitate this, a reference to the TimerTask instance is passed as an argument
  # to the provided block every time the task is executed.
  # 
  # The `TimerTask` class includes the `Dereferenceable` mixin module so the result of
  # the last execution is always available via the `#value` method. Derefencing options
  # can be passed to the `TimerTask` during construction or at any later time using the
  # `#set_deref_options` method.
  # 
  # `TimerTask` supports notification through the Ruby standard library
  # {http://ruby-doc.org/stdlib-2.0/libdoc/observer/rdoc/Observable.html Observable}
  # module. On execution the `TimerTask` will notify the observers
  # with three arguments: time of execution, the result of the block (or nil on failure),
  # and any raised exceptions (or nil on success). If the timeout interval is exceeded
  # the observer will receive a `Concurrent::TimeoutError` object as the third argument.
  #
  # @example Basic usage
  #   task = Concurrent::TimerTask.new{ puts 'Boom!' }
  #   task.run!
  #   
  #   task.execution_interval #=> 60 (default)
  #   task.timeout_interval   #=> 30 (default)
  #   
  #   # wait 60 seconds...
  #   #=> 'Boom!'
  #   
  #   task.stop #=> true
  #
  # @example Configuring `:execution_interval` and `:timeout_interval`
  #   task = Concurrent::TimerTask.new(execution_interval: 5, timeout_interval: 5) do
  #          puts 'Boom!'
  #        end
  #   
  #   task.execution_interval #=> 5
  #   task.timeout_interval   #=> 5
  #
  # @example Immediate execution with `:run_now`
  #   task = Concurrent::TimerTask.new(run_now: true){ puts 'Boom!' }
  #   task.run!
  #   
  #   #=> 'Boom!'
  #
  # @example Last `#value` and `Dereferenceable` mixin
  #   task = Concurrent::TimerTask.new(
  #     dup_on_deref: true,
  #     execution_interval: 5
  #   ){ Time.now }
  #   
  #   task.run!
  #   Time.now   #=> 2013-11-07 18:06:50 -0500
  #   sleep(10)
  #   task.value #=> 2013-11-07 18:06:55 -0500
  #
  # @example Controlling execution from within the block
  #   timer_task = Concurrent::TimerTask.new(execution_interval: 1) do |task|
  #     task.execution_interval.times{ print 'Boom! ' }
  #     print "\n"
  #     task.execution_interval += 1
  #     if task.execution_interval > 5
  #       puts 'Stopping...'
  #       task.stop
  #     end
  #   end
  #   
  #   timer_task.run # blocking call - this task will stop itself
  #   #=> Boom!
  #   #=> Boom! Boom!
  #   #=> Boom! Boom! Boom!
  #   #=> Boom! Boom! Boom! Boom!
  #   #=> Boom! Boom! Boom! Boom! Boom!
  #   #=> Stopping...
  #
  # @example Observation
  #   class TaskObserver
  #     def update(time, result, ex)
  #       if result
  #         print "(#{time}) Execution successfully returned #{result}\n"
  #       elsif ex.is_a?(Concurrent::TimeoutError)
  #         print "(#{time}) Execution timed out\n"
  #       else
  #         print "(#{time}) Execution failed with error #{ex}\n"
  #       end
  #     end
  #   end
  #   
  #   task = Concurrent::TimerTask.new(execution_interval: 1, timeout_interval: 1){ 42 }
  #   task.add_observer(TaskObserver.new)
  #   task.run!
  #   
  #   #=> (2013-10-13 19:08:58 -0400) Execution successfully returned 42
  #   #=> (2013-10-13 19:08:59 -0400) Execution successfully returned 42
  #   #=> (2013-10-13 19:09:00 -0400) Execution successfully returned 42
  #   task.stop
  #   
  #   task = Concurrent::TimerTask.new(execution_interval: 1, timeout_interval: 1){ sleep }
  #   task.add_observer(TaskObserver.new)
  #   task.run!
  #   
  #   #=> (2013-10-13 19:07:25 -0400) Execution timed out
  #   #=> (2013-10-13 19:07:27 -0400) Execution timed out
  #   #=> (2013-10-13 19:07:29 -0400) Execution timed out
  #   task.stop
  #   
  #   task = Concurrent::TimerTask.new(execution_interval: 1){ raise StandardError }
  #   task.add_observer(TaskObserver.new)
  #   task.run!
  #   
  #   #=> (2013-10-13 19:09:37 -0400) Execution failed with error StandardError
  #   #=> (2013-10-13 19:09:38 -0400) Execution failed with error StandardError
  #   #=> (2013-10-13 19:09:39 -0400) Execution failed with error StandardError
  #   task.stop
  #
  # @see http://ruby-doc.org/stdlib-2.0/libdoc/observer/rdoc/Observable.html
  # @see http://docs.oracle.com/javase/7/docs/api/java/util/TimerTask.html
  class TimerTask
    include Dereferenceable
    include RubyExecutor
    include Concurrent::Observable

    # Default `:execution_interval` in seconds.
    EXECUTION_INTERVAL = 60

    # Default `:timeout_interval` in seconds.
    TIMEOUT_INTERVAL = 30

    # Create a new TimerTask with the given task and configuration.
    #
    # @!macro [attach] timer_task_initialize
    #   @param [Hash] opts the options defining task execution.
    #   @option opts [Integer] :execution_interval number of seconds between
    #     task executions (default: EXECUTION_INTERVAL)
    #   @option opts [Integer] :timeout_interval number of seconds a task can
    #     run before it is considered to have failed (default: TIMEOUT_INTERVAL)
    #   @option opts [Boolean] :run_now Whether to run the task immediately
    #     upon instantiation or to wait until the first #  execution_interval
    #     has passed (default: false)
    #  
    #   @raise ArgumentError when no block is given.
    #  
    #   @yield to the block after :execution_interval seconds have passed since
    #     the last yield
    #   @yieldparam task a reference to the `TimerTask` instance so that the
    #     block can control its own lifecycle. Necessary since `self` will
    #     refer to the execution context of the block rather than the running
    #     `TimerTask`.
    #  
    #   @note Calls Concurrent::Dereferenceable#  set_deref_options passing `opts`.
    #     All options supported by Concurrent::Dereferenceable can be set
    #     during object initialization.
    #
    #   @return [TimerTask] the new `TimerTask`
    #  
    #   @see Concurrent::Dereferenceable#  set_deref_options
    def initialize(opts = {}, &task)
      raise ArgumentError.new('no block given') unless block_given?

      init_executor
      set_deref_options(opts)

      self.execution_interval = opts[:execution] || opts[:execution_interval] || EXECUTION_INTERVAL
      self.timeout_interval = opts[:timeout] || opts[:timeout_interval] || TIMEOUT_INTERVAL
      @run_now = opts[:now] || opts[:run_now]
      @executor = Concurrent::SafeTaskExecutor.new(task)
      @running = Concurrent::AtomicBoolean.new(false)

      self.observers = CopyOnNotifyObserverSet.new
    end

    # Is the executor running?
    #
    # @return [Boolean] `true` when running, `false` when shutting down or shutdown
    def running?
      @running.true?
    end

    # Execute a previously created `TimerTask`.
    #
    # @return [TimerTask] a reference to `self`
    #
    # @example Instance and execute in separate steps
    #   task = Concurrent::TimerTask.new(execution_interval: 10){ print "Hello World\n" }
    #   task.running? #=> false
    #   task.execute
    #   task.running? #=> true
    #
    # @example Instance and execute in one line
    #   task = Concurrent::TimerTask.new(execution_interval: 10){ print "Hello World\n" }.execute
    #   task.running? #=> true
    #
    # @since 0.6.0
    def execute
      mutex.synchronize do
        if @running.false?
          @running.make_true
          schedule_next_task(@run_now ? 0 : @execution_interval)
        end
      end
      self
    end

    # Create and execute a new `TimerTask`.
    #
    # @!macro timer_task_initialize
    #
    # @example 
    #   task = Concurrent::TimerTask.execute(execution_interval: 10){ print "Hello World\n" }
    #   task.running? #=> true
    #
    # @since 0.6.0
    def self.execute(opts = {}, &task)
      TimerTask.new(opts, &task).execute
    end

    # @!attribute [rw] execution_interval
    # @return [Fixnum] Number of seconds after the task completes before the
    #   task is performed again.
    def execution_interval
      mutex.lock
      @execution_interval
    ensure
      mutex.unlock
    end

    # @!attribute [rw] execution_interval
    # @return [Fixnum] Number of seconds after the task completes before the
    #   task is performed again.
    def execution_interval=(value)
      if (value = value.to_f) <= 0.0
        raise ArgumentError.new('must be greater than zero')
      else
        begin
          mutex.lock
          @execution_interval = value
        ensure
          mutex.unlock
        end
      end
    end

    # @!attribute [rw] timeout_interval
    # @return [Fixnum] Number of seconds the task can run before it is
    #   considered to have failed.
    def timeout_interval
      mutex.lock
      @timeout_interval
    ensure
      mutex.unlock
    end

    # @!attribute [rw] timeout_interval
    # @return [Fixnum] Number of seconds the task can run before it is
    #   considered to have failed.
    def timeout_interval=(value)
      if (value = value.to_f) <= 0.0
        raise ArgumentError.new('must be greater than zero')
      else
        begin
          mutex.lock
          @timeout_interval = value
        ensure
          mutex.unlock
        end
      end
    end

    private :post, :<<

    protected

    # @!visibility private
    def shutdown_execution
      @running.make_false
      super
    end

    # @!visibility private
    def kill_execution
      @running.make_false
      super
    end

    # @!visibility private
    def schedule_next_task(interval = execution_interval)
      Concurrent::timer(interval, Concurrent::Event.new, &method(:execute_task))
    end

    # @!visibility private
    def execute_task(completion)
      return unless @running.true?
      Concurrent::timer(timeout_interval, completion, &method(:timeout_task))
      success, value, reason = @executor.execute(self)
      if completion.try?
        self.value = value
        schedule_next_task
        time = Time.now
        observers.notify_observers do
          [time, self.value, reason]
        end
      end
    end

    # @!visibility private
    def timeout_task(completion)
      return unless @running.true?
      if completion.try?
        self.value = value
        schedule_next_task
        observers.notify_observers(Time.now, nil, Concurrent::TimeoutError.new)
      end
    end
  end
end
