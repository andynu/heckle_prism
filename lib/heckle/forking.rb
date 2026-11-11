class Heckle
  ##
  # Exit statuses of a fork mode child. Any other status, or death by a
  # signal, is reported as unexpected and is never counted as a survivor.

  FORK_SURVIVED = 100       # the tests passed against the mutant
  FORK_KILLED = 101         # the tests failed
  FORK_INSTALL_FAILED = 102 # install raised
  FORK_RAISED = 103         # the test run raised, or a signal ended it

  ##
  # Seconds a child gets to exit after TERM before it is sent KILL.

  FORK_GRACE = 1

  private

  # Runs the tests against +mutation+ in a forked child and reports the
  # outcome as validate does in-process. The parent never installs it.
  def run_forked(mutation)
    status = wait_for_child(mutation)

    case status.exitstatus
    when FORK_SURVIVED then record_passing_mutation
    when FORK_KILLED then @reporter.report_test_failures
    when FORK_INSTALL_FAILED then raise_install_error(mutation)
    when FORK_RAISED
      @reporter.warning "The tests raised an exception in the forked child. Not counted as a survivor."
    else
      @reporter.warning "The forked test run #{child_ending(status)}. Not counted as a survivor."
    end
  end

  # Returns the child's Process::Status. Raises Heckle::Timeout when it
  # outlives the timeout. The child is stopped and reaped on every path.
  def wait_for_child(mutation)
    $stdout.flush
    $stderr.flush
    finished = nil

    # ^C is held off until the child is tracked, and while it is stopped.
    Thread.handle_interrupt(Object => :never) do
      pid = fork_child(mutation)
      waiter = Process.detach(pid)
      begin
        finished = Thread.handle_interrupt(Object => :immediate) { waiter.join(@@timeout) }
      ensure
        stop_child(pid, waiter) unless finished
      end
    end
    raise Heckle::Timeout unless finished

    finished.value
  end

  # The child inherits the parent's interrupt mask, so it reopens it.
  # Everything after install judges the mutant and so runs the mutant's
  # code wherever it is on that path: keep it to tests_pass? and exit!.
  # exit! skips at_exit handlers (Minitest, SimpleCov, database cleanup).
  def fork_child(mutation)
    Process.fork do
      status = FORK_RAISED
      begin
        Thread.handle_interrupt(Object => :immediate) do
          status = FORK_INSTALL_FAILED
          install mutation
          status = FORK_RAISED
          status = tests_pass? ? FORK_SURVIVED : FORK_KILLED
        end
      ensure
        exit!(status)
      end
    end
  end

  # The child cannot pass the error back, so it is rebuilt by compiling,
  # without running, the source install evaluated.
  def raise_install_error(mutation)
    source, line = install_source(mutation)
    RubyVM::InstructionSequence.compile(source, @file, @file, line)

    @reporter.warning "Installing the mutant raised an exception in the forked child. Not counted as a survivor."
  end

  def stop_child(pid, waiter)
    signal_child(:TERM, pid, waiter)
    return if waiter.join(fork_grace)

    signal_child(:KILL, pid, waiter)
    waiter.join
  end

  def fork_grace
    FORK_GRACE
  end

  # Only while the waiter has not reaped the child, so the pid is still its.
  def signal_child(signal, pid, waiter)
    Process.kill(signal, pid) if waiter.alive?
  rescue Errno::ESRCH
    nil
  end

  def child_ending(status)
    if status.signaled?
      "was killed by signal #{Signal.signame(status.termsig)}"
    else
      "ended with exit status #{status.exitstatus}"
    end
  end
end
