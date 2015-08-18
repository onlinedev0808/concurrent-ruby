require 'concurrent/synchronization/object'

module Concurrent

  # A simple utility class that executes a callable and returns and array of three elements:
  # success - indicating if the callable has been executed without errors
  # value - filled by the callable result if it has been executed without errors, nil otherwise
  # reason - the error risen by the callable if it has been executed with errors, nil otherwise
  class SafeTaskExecutor < Synchronization::Object

    def initialize(task, opts = {})
      super()
      @task = task
      @exception_class = opts.fetch(:rescue_exception, false) ? Exception : StandardError
      ensure_ivar_visibility!
    end

    # @return [Array]
    def execute(*args)
      synchronize do
        success = false
        value = reason = nil

        begin
          value = @task.call(*args)
          success = true
        rescue @exception_class => ex
          reason = ex
          success = false
        end

        [success, value, reason]
      end
    end
  end
end
