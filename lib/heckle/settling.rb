class Heckle
  ##
  # Seconds settle waits for an abandoned executor's workers to stop, and
  # again for those it then kills.

  SETTLE_GRACE = 0.5

  @@abandoned_executor = nil

  ##
  # Cleans up after a test run that an exception (a timeout, ^C) ended,
  # so that what the run left behind cannot change the outcome of the
  # next one. Does nothing after a run that finished. Returns nil.

  def self.settle
    executor = @@abandoned_executor
    @@abandoned_executor = nil
    retire(executor) if executor
    nil
  end

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
    still_running(running)
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
