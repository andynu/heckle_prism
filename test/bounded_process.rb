require "open3"

# Runs a command that may run away under a backstop that does not depend
# on the code under test: RLIMIT_DATA is set in the child before exec, and
# the child's process group is killed once the wall-clock limit passes.
module BoundedProcess
  Result = Struct.new(:out, :err, :status, :elapsed, :killed)

  # Ruby 3.3 and later start with about 450 MB of data mapped but not
  # resident, so the limit is well above that.
  DATA_LIMIT = 900 * 1024 * 1024

  def self.capture3(*command, seconds:, chdir: Dir.pwd, data_limit: DATA_LIMIT)
    started = now
    options = { chdir: chdir, pgroup: true, rlimit_data: [data_limit, data_limit] }
    Open3.popen3(*command, options) do |stdin, stdout, stderr, waiter|
      stdin.close
      readers = [stdout, stderr].map { |io| Thread.new { io.read } }
      begin
        killed = waiter.join(seconds).nil?
      ensure
        kill_group(waiter.pid)
      end
      status = waiter.value
      out, err = readers.map { |reader| reader.join(5) ? reader.value : "" }
      Result.new(out, err, status, now - started, killed)
    end
  end

  # Also after a normal exit, for anything the command left in its group.
  def self.kill_group(pid)
    Process.kill(:KILL, -pid)
  rescue Errno::ESRCH, Errno::EPERM
    nil
  end

  def self.now
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end
end
