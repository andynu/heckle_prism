class HecklePrism
  ##
  # Seconds settle waits for an abandoned executor's workers to stop, and
  # again for those it then kills.

  SETTLE_GRACE = 0.5

  @@abandoned_executor = nil
  @@stopped_test = nil
  @@unsettled = nil

  ##
  # Why settle could not clean up after a stopped run, or nil. Once set
  # it stays set: no later mutant is run in this process, since its
  # outcome could be the earlier mutant's doing.

  def self.unsettled
    @@unsettled
  end

  def self.unsettle(reason)
    @@unsettled ||= reason
  end
  private_class_method :unsettle

  ##
  # Cleans up after a test run that an exception (a timeout, ^C) ended,
  # so that what the run left behind cannot change the outcome of the
  # next one. Does nothing after a run that finished. Returns nil.

  def self.settle
    executor = @@abandoned_executor
    test = @@stopped_test
    @@abandoned_executor = @@stopped_test = nil
    retire(executor) if executor
    finish(test) if test
    nil
  end

  ##
  # Records the test an exception passed through, whose teardown hooks
  # Minitest then skips.

  module StoppedTest
    def run
      super
    rescue Exception
      HecklePrism.send(:stopped, self)
      raise
    end
  end
  Minitest::Test.prepend(StoppedTest)

  def self.stopped(test)
    @@stopped_test = test
  end
  private_class_method :stopped

  # Runs the hooks Minitest skipped, as it runs them after a failure:
  # each in turn, with errors captured. A teardown that state outlives
  # (a transaction, a frozen clock) would otherwise leave that state to
  # the next mutant's tests. It gets the timeout of a test run.
  def self.finish(test)
    report = teardown_swallowed_report(test)
    quietly do
      Watchdog.new(@@timeout, report).watch do
        Minitest::Test::TEARDOWN_METHODS.each do |hook|
          test.capture_exceptions { test.send(hook) }
        end
      end
    end
  rescue HecklePrism::Timeout
    unsettle "the teardown of #{test.class}##{test.name}, which heckle ran after its test was stopped, " \
             "did not finish within the #{@@timeout} second timeout"
  end
  private_class_method :finish

  def self.teardown_swallowed_report(test)
    <<~TEXT
      heckle: the teardown of #{test.class}##{test.name}, which heckle ran after its test was stopped,
      was still running #{Watchdog::GRACE} seconds after the #{@@timeout} second timeout was raised in it.
      Heckle ended the process without printing results or running at_exit handlers.
      Run heckle with --fork to run each mutant's tests in a process of their own.
    TEXT
  end
  private_class_method :teardown_swallowed_report

  # Records the executor of a run that did not reach its shutdown.
  def self.abandon(executor)
    @@abandoned_executor = executor if executor.is_a?(Minitest::Parallel::Executor)
  end
  private_class_method :abandon

  # The workers of a run cut short wait on their executor's queue, where
  # they would take the signals that end the next run's own workers and
  # leave that run waiting for them. Minitest has no API for this, so the
  # queue is emptied and closed, which ends a waiting worker, and a fresh
  # executor of the same size takes the old one's place. A worker still
  # running a test (a parallel one, say) is killed.
  def self.retire(executor)
    Minitest.parallel_executor = Minitest::Parallel::Executor.new(executor.size)

    queue = executor.instance_variable_get(:@queue)
    if queue.respond_to?(:close)
      queue.clear
      queue.close
    end
    running = still_running(Array(executor.instance_variable_get(:@pool)))
    running.each(&:kill)
    return if still_running(running).empty?

    # Left running: Thread#kill waits for it to leave C code or a
    # handle_interrupt block, which may be never.
    unsettle "a test thread of an earlier mutant's run could not be stopped and may still be running"
  end
  private_class_method :retire

  # The threads of +threads+ alive after waiting SETTLE_GRACE for them.
  def self.still_running(threads)
    deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + SETTLE_GRACE
    threads.each do |thread|
      left = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
      thread.join(left) if left > 0
    end
    threads.select(&:alive?)
  end
  private_class_method :still_running
end
