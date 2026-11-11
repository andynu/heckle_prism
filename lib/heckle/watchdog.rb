class Heckle
  ##
  # Raised in the test run when it outlives the timeout. Not a
  # StandardError, so that neither a bare rescue nor a rescue of
  # StandardError in the code under test can swallow it.

  class Timeout < Exception; end

  ##
  # Runs a block in the current thread under a deadline kept by a thread
  # of its own. At the deadline the watchdog raises Heckle::Timeout in the
  # block's thread, and again every RERAISE_INTERVAL seconds while the
  # block runs on. If the block is still running GRACE seconds after the
  # first raise, the code under test has swallowed the timeout: the
  # watchdog writes its report to the standard error the process started
  # with and ends the process with exit!, so no at_exit handler runs.
  #
  # The watchdog thread needs the GVL. A thread that holds it without
  # yielding, in C code, keeps the watchdog from running at all.

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
    # +report+ is written to standard error if the timeout is swallowed.

    def initialize(seconds, report)
      @seconds = seconds
      @report = report
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
    # Runs the block and returns its value. Heckle::Timeout is held off
    # outside the block itself, so it never lands in this method's own
    # bookkeeping; one raised as the block returns arrives on the way out.

    def watch
      target = Thread.current
      Thread.handle_interrupt(Heckle::Timeout => :never) do
        patrol = Thread.new { patrol(target) }
        begin
          Thread.handle_interrupt(Heckle::Timeout => :immediate) { yield }
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
        give_up = nil
        until @done
          wait = next_raise - now
          if wait > 0
            @changed.wait(@lock, wait)
            next
          end
          give_up ||= now + GRACE
          stop_the_process if now >= give_up
          @fired = true
          target.raise(Heckle::Timeout)
          next_raise = [now + RERAISE_INTERVAL, give_up].min
        end
      end
    end

    def stop_the_process
      begin
        (STDERR_COPY || STDERR).syswrite(@report)
      rescue SystemCallError, IOError
        nil
      end
      Process.exit!(EXIT_STATUS)
    end

    def now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end
  end
end
