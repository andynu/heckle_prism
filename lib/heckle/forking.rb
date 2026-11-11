class Heckle
  ##
  # Exit statuses of a fork mode child. Any other status, or death by a
  # signal, is reported as unexpected and is never counted as a survivor.

  FORK_SURVIVED = 100       # the tests passed against the mutant
  FORK_KILLED = 101         # the tests failed
  FORK_INSTALL_FAILED = 102 # install raised
  FORK_RAISED = 103         # the test run raised, or a signal ended it
  FORK_OUT_OF_MEMORY = 104  # NoMemoryError, at the backstop or not

  ##
  # Seconds a child gets to exit after TERM before it is sent KILL.

  FORK_GRACE = 1

  private

  # Runs the tests against +mutation+ in a forked child and reports the
  # outcome as validate does in-process. The parent never installs it.
  def run_forked(mutation)
    status = wait_for_child(mutation)
    if status == :over_memory
      report_not_judged :memory, "The forked test run went over the memory limit of #{megabytes(@@memory_limit)} " \
                                 "and was killed. Not counted as a survivor."
      return
    end

    case status.exitstatus
    when FORK_SURVIVED then record_passing_mutation
    when FORK_KILLED then @reporter.report_test_failures
    when FORK_INSTALL_FAILED then raise_install_error(mutation)
    when FORK_RAISED
      report_not_judged :crash, "The tests raised an exception in the forked child. Not counted as a survivor."
    when FORK_OUT_OF_MEMORY
      report_not_judged :memory, "The forked test run ran out of memory. Not counted as a survivor."
    else
      report_not_judged :crash, "The forked test run #{child_ending(status)}. Not counted as a survivor."
    end
  end

  # Returns the child's Process::Status, or :over_memory when it went over
  # the memory limit and was killed. Raises Heckle::Timeout when it
  # outlives the timeout. The child is stopped and reaped on every path.
  def wait_for_child(mutation)
    $stdout.flush
    $stderr.flush
    outcome = nil

    # ^C is held off until the child is tracked, and while it is stopped.
    Thread.handle_interrupt(Object => :never) do
      pid = fork_child(mutation)
      own_group(pid)
      waiter = Process.detach(pid)
      begin
        outcome = Thread.handle_interrupt(Object => :immediate) { watch_child(pid, waiter) }
      ensure
        if outcome == :over_memory
          kill_child(pid, waiter)
        elsif !outcome
          stop_child(pid, waiter)
        end
      end
    end
    raise Heckle::Timeout unless outcome

    outcome == :over_memory ? outcome : outcome.value
  end

  # The waiter once the child has ended, :over_memory, or nil at the
  # deadline. The parent is the enforcer: a child stuck in C code or in
  # GC cannot hold it up.
  def watch_child(pid, waiter)
    deadline = now + @@timeout
    loop do
      left = deadline - now
      return nil if left <= 0

      finished = waiter.join(@@memory_limit ? [left, Memory.poll_interval].min : left)
      return finished if finished

      resident = @@memory_limit && Memory.resident(pid)
      return :over_memory if resident && resident > @@memory_limit
    end
  end

  def now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  # The child inherits the parent's interrupt mask, so it reopens it.
  # Everything after install judges the mutant and so runs the mutant's
  # code wherever it is on that path: keep it to tests_pass? and exit!.
  # exit! skips at_exit handlers (Minitest, SimpleCov, database cleanup).
  # The backstop is set in the child only, so the parent stays unlimited.
  def fork_child(mutation)
    Process.fork do
      status = FORK_RAISED
      begin
        own_group(0)
        Thread.handle_interrupt(Object => :immediate) do
          Memory.backstop(@@memory_limit) if @@memory_limit
          status = FORK_INSTALL_FAILED
          install mutation
          status = FORK_RAISED
          status = tests_pass? ? FORK_SURVIVED : FORK_KILLED
        end
      rescue NoMemoryError
        status = FORK_OUT_OF_MEMORY
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

    report_not_judged :install, "Installing the mutant raised an exception in the forked child. Not counted as a survivor."
  end

  # TERM, then KILL if the child outlives the grace. Processes the child
  # started are in its group and get the same signals, and whatever is
  # left of the group once the child is gone is killed.
  def stop_child(pid, waiter)
    signal_child(:TERM, pid, waiter)
    unless waiter.join(fork_grace)
      signal_child(:KILL, pid, waiter)
      waiter.join
    end
    signal_group(:KILL, pid)
  end

  # No TERM first: a child growing at gigabytes a second would grow on
  # through the grace.
  def kill_child(pid, waiter)
    signal_child(:KILL, pid, waiter)
    waiter.join
    signal_group(:KILL, pid)
  end

  def fork_grace
    FORK_GRACE
  end

  # Both the parent and the child make the child a group leader, so the
  # group exists before either goes on. It fails harmlessly once the
  # child has done it or has exited.
  def own_group(pid)
    Process.setpgid(pid, 0)
  rescue SystemCallError
    nil
  end

  # Only while the waiter has not reaped the child, so the group is still its.
  def signal_child(signal, pid, waiter)
    signal_group(signal, pid) if waiter.alive?
  end

  def signal_group(signal, pid)
    Process.kill(signal, -pid)
  rescue Errno::ESRCH, Errno::EPERM
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
