class HecklePrism
  ##
  # Raised in the test run when it outlives the timeout. Not a
  # StandardError, so that neither a bare rescue nor a rescue of
  # StandardError in the code under test can swallow it.

  class Timeout < Exception; end

  ##
  # Runs a block in the current thread under a deadline kept by a thread
  # of its own. At the deadline the watchdog raises HecklePrism::Timeout in the
  # block's thread, and again every RERAISE_INTERVAL seconds while the
  # block runs on. If the block is still running GRACE seconds after the
  # first raise, the code under test has swallowed the timeout: the
  # watchdog writes its report to the standard error the process started
  # with and ends the process with exit!, so no at_exit handler runs.
  # Given a memory limit, it also reads the process's resident memory
  # every Memory.poll_interval seconds and ends the process the same way
  # once it is over the limit.
  #
  # The watchdog thread needs the GVL. A thread that holds it without
  # yielding, in C code, keeps the watchdog from running at all, and a
  # long major GC delays it.

  class Watchdog
    ##
    # Seconds from the first raise to the end of the process.

    GRACE = 2

    ##
    # Seconds between raises within the grace.

    RERAISE_INTERVAL = 0.5

    ##
    # Exit status of a process the watchdog ended.

    EXIT_STATUS = 2

    # A copy of the standard error the process started with, so the report
    # reaches it even while the tests have $stderr or fd 2 redirected.
    STDERR_COPY = begin
      STDERR.dup
    rescue SystemCallError, IOError
      nil
    end
    private_constant :STDERR_COPY

    ##
    # Writes +report+ to the standard error the process started with and
    # ends the process at once, running no at_exit handler.

    def self.end_process(report)
      begin
        (STDERR_COPY || STDERR).syswrite(report)
      rescue SystemCallError, IOError
        nil
      end
      Process.exit!(EXIT_STATUS)
    end

    ##
    # +report+ is written to standard error if the timeout is swallowed.
    # +memory_report+ is called with the resident memory in bytes when
    # that goes over +memory_limit+ bytes, and what it returns is written.

    def initialize(seconds, report, memory_limit: nil, memory_report: nil)
      @seconds = seconds
      @report = report
      @memory_limit = memory_limit
      @memory_report = memory_report
      @lock = Mutex.new
      @changed = ConditionVariable.new
      @done = false
      @fired = false
    end

    ##
    # True once the deadline has passed and the timeout was raised. The
    # block may still have returned normally, if its code rescued it.

    def fired?
      @fired
    end

    ##
    # Runs the block and returns its value. Asynchronous exceptions
    # (HecklePrism::Timeout, ^C) are held off outside the block itself, so none
    # lands in this method's own bookkeeping and leaves the watchdog
    # running; one raised as the block returns arrives on the way out.

    def watch
      target = Thread.current
      Thread.handle_interrupt(Object => :never) do
        patrol = Thread.new { patrol(target) }
        begin
          Thread.handle_interrupt(Object => :immediate) { yield }
        ensure
          @lock.synchronize do
            @done = true
            @changed.signal
          end
          patrol.join
        end
      end
    end

    private

    def patrol(target)
      @lock.synchronize do
        next_raise = now + @seconds
        next_poll = now
        give_up = nil
        until @done
          time = now
          # Timed from the end of the read, so the wait below always
          # happens and releases the lock even when a read is slow.
          if @memory_limit && time >= next_poll
            check_memory
            next_poll = now + Memory.poll_interval
          end
          if time >= next_raise
            give_up ||= time + GRACE
            self.class.end_process(@report) if time >= give_up
            @fired = true
            target.raise(HecklePrism::Timeout)
            next_raise = [time + RERAISE_INTERVAL, give_up].min
          end
          wake = @memory_limit ? [next_raise, next_poll].min : next_raise
          wait = wake - now
          @changed.wait(@lock, wait) if wait > 0
        end
      end
    end

    def check_memory
      resident = Memory.resident
      return unless resident && resident > @memory_limit

      self.class.end_process(@memory_report.call(resident))
    end

    def now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
