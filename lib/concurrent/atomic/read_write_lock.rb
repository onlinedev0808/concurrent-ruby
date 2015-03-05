require 'thread'
require 'concurrent/atomic'
require 'concurrent/errors'

module Concurrent

  # Ruby read-write lock implementation
  #
  # Allows any number of concurrent readers, but only one concurrent writer
  # (And if the "write" lock is taken, any readers who come along will have to wait)
  #
  # If readers are already active when a writer comes along, the writer will wait for
  # all the readers to finish before going ahead.
  # Any additional readers that come when the writer is already waiting, will also
  # wait (so writers are not starved).
  #
  # This implementation is based on `java.util.concurrent.ReentrantReadWriteLock`.
  #
  # @example
  #   lock = Concurrent::ReadWriteLock.new
  #   lock.with_read_lock  { data.retrieve }
  #   lock.with_write_lock { data.modify! }
  #
  # @note Do **not** try to acquire the write lock while already holding a read lock
  #   **or** try to acquire the write lock while you already have it.
  #   This will lead to deadlock
  #
  # @see http://docs.oracle.com/javase/7/docs/api/java/util/concurrent/locks/ReentrantReadWriteLock.html java.util.concurrent.ReentrantReadWriteLock
  class ReadWriteLock

    # @!visibility private
    WAITING_WRITER  = 1 << 15

    # @!visibility private
    RUNNING_WRITER  = 1 << 30

    # @!visibility private
    MAX_READERS     = WAITING_WRITER - 1

    # @!visibility private
    MAX_WRITERS     = RUNNING_WRITER - MAX_READERS - 1

    # Implementation notes: 
    # A goal is to make the uncontended path for both readers/writers lock-free
    # Only if there is reader-writer or writer-writer contention, should locks be used
    # Internal state is represented by a single integer ("counter"), and updated 
    #  using atomic compare-and-swap operations
    # When the counter is 0, the lock is free
    # Each reader increments the counter by 1 when acquiring a read lock
    #   (and decrements by 1 when releasing the read lock)
    # The counter is increased by (1 << 15) for each writer waiting to acquire the
    #   write lock, and by (1 << 30) if the write lock is taken

    # Create a new `ReadWriteLock` in the unlocked state.
    def initialize
      @counter      = Atomic.new(0)         # single integer which represents lock state
      @reader_q     = ConditionVariable.new # queue for waiting readers
      @reader_mutex = Mutex.new             # to protect reader queue
      @writer_q     = ConditionVariable.new # queue for waiting writers
      @writer_mutex = Mutex.new             # to protect writer queue
    end

    # Execute a block operation within a read lock.
    #
    # @yield the task to be performed within the lock.
    #
    # @return [Object] the result of the block operation.
    #
    # @raise [ArgumentError] when no block is given.
    # @raise [Concurrent::ResourceLimitError] if the maximum number of readers
    #   is exceeded.
    def with_read_lock
      raise ArgumentError.new('no block given') unless block_given?
      acquire_read_lock
      yield
    rescue => ex
      raise ex
    ensure
      if block_given? && ! ex.is_a?(Concurrent::ResourceLimitError)
        release_read_lock
      end
    end

    # Execute a block operation within a write lock.
    #
    # @yield the task to be performed within the lock.
    #
    # @return [Object] the result of the block operation.
    #
    # @raise [ArgumentError] when no block is given.
    # @raise [Concurrent::ResourceLimitError] if the maximum number of readers
    #   is exceeded.
    def with_write_lock
      raise ArgumentError.new('no block given') unless block_given?
      acquire_write_lock
      yield
    rescue => ex
      raise ex
    ensure
      if block_given? && ! ex.is_a?(Concurrent::ResourceLimitError)
        release_write_lock
      end
    end

    # Acquire a read lock.
    #
    # @raise [Concurrent::ResourceLimitError] if the maximum number of readers
    #   is exceeded.
    def acquire_read_lock
      while(true)
        c = @counter.value
        raise ResourceLimitError.new('Too many reader threads') if (c & MAX_READERS) == MAX_READERS

        # If a writer is waiting when we first queue up, we need to wait
        if c >= WAITING_WRITER
          # But it is possible that the writer could finish and decrement @counter right here...
          @reader_mutex.synchronize do 
            # So check again inside the synchronized section
            @reader_q.wait(@reader_mutex) if @counter.value >= WAITING_WRITER
          end

          # after a reader has waited once, they are allowed to "barge" ahead of waiting writers
          # but if a writer is *running*, the reader still needs to wait (naturally)
          while(true)
            c = @counter.value
            if c >= RUNNING_WRITER
              @reader_mutex.synchronize do
                @reader_q.wait(@reader_mutex) if @counter.value >= RUNNING_WRITER
              end
            else
              return if @counter.compare_and_swap(c,c+1)
            end
          end
        else
          break if @counter.compare_and_swap(c,c+1)
        end
      end    
      true
    end

    # Release a previously acquired read lock.
    def release_read_lock
      while(true)
        c = @counter.value
        if @counter.compare_and_swap(c,c-1)
          # If one or more writers were waiting, and we were the last reader, wake a writer up
          if c >= WAITING_WRITER && (c & MAX_READERS) == 1
            @writer_mutex.synchronize { @writer_q.signal }
          end
          break
        end
      end
      true
    end

    # Acquire a write lock.
    #
    # @raise [Concurrent::ResourceLimitError] if the maximum number of writers
    #   is exceeded.
    def acquire_write_lock
      while(true)
        c = @counter.value
        raise ResourceLimitError.new('Too many writer threads') if (c & MAX_WRITERS) == MAX_WRITERS

        if c == 0 # no readers OR writers running
          # if we successfully swap the RUNNING_WRITER bit on, then we can go ahead
          break if @counter.compare_and_swap(0,RUNNING_WRITER)
        elsif @counter.compare_and_swap(c,c+WAITING_WRITER)
          while(true)
            # Now we have successfully incremented, so no more readers will be able to increment
            #   (they will wait instead)
            # However, readers OR writers could decrement right here, OR another writer could increment
            @writer_mutex.synchronize do
              # So we have to do another check inside the synchronized section
              # If a writer OR reader is running, then go to sleep
              c = @counter.value
              @writer_q.wait(@writer_mutex) if (c >= RUNNING_WRITER) || ((c & MAX_READERS) > 0)
            end

            # We just came out of a wait
            # If we successfully turn the RUNNING_WRITER bit on with an atomic swap,
            # Then we are OK to stop waiting and go ahead
            # Otherwise go back and wait again
            c = @counter.value
            break if (c < RUNNING_WRITER) && 
              ((c & MAX_READERS) == 0) &&
              @counter.compare_and_swap(c,c+RUNNING_WRITER-WAITING_WRITER)
          end
          break
        end
      end
      true
    end

    # Release a previously acquired write lock.
    def release_write_lock
      while(true)
        c = @counter.value
        if @counter.compare_and_swap(c,c-RUNNING_WRITER)
          @reader_mutex.synchronize { @reader_q.broadcast }
          if (c & MAX_WRITERS) > 0 # if any writers are waiting...
            @writer_mutex.synchronize { @writer_q.signal }
          end
          break
        end
      end
      true
    end

    # Returns a string representing *obj*. Includes the current reader and
    # writer counts.
    def to_s
      c = @counter.value
      s = if c >= RUNNING_WRITER
            "1 writer running, "
          elsif (c & MAX_READERS) > 0
            "#{c & MAX_READERS} readers running, "
          else
            ""
          end

      "#<ReadWriteLock:#{object_id.to_s(16)} #{s}#{(c & MAX_WRITERS) / WAITING_WRITER} writers waiting>"
    end
  end
end
