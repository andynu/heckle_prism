class Heckle
  ##
  # Reads resident memory and keeps the RLIMIT_DATA backstop. Resident
  # memory comes from /proc/PID/status where there is one, otherwise from
  # ps(1); on a platform with neither it cannot be read and the memory
  # limit is not enforced.

  module Memory
    MB = 1024 * 1024

    ##
    # Seconds between reads of resident memory while a mutant runs.
    # ps(1) is a process per read, so it is read less often.

    PROC_INTERVAL = 0.05
    PS_INTERVAL = 0.5

    ##
    # Room the RLIMIT_DATA backstop leaves above the memory limit, so that
    # polling, not the backstop, normally ends a runaway: under the limit
    # Ruby can abort, or on 3.3 spin in GC, instead of raising.

    BACKSTOP_SLACK = 1024 * MB

    ##
    # The default limit for a process using +baseline+ bytes.

    def self.default_limit(baseline)
      baseline + [1024 * MB, baseline].max
    end

    ##
    # Resident memory of +pid+ in bytes, or nil when it cannot be read
    # (no such process, a zombie, or no way to read it here).

    def self.resident(pid = Process.pid)
      case source
      when :proc then proc_status(pid, "VmRSS")
      when :ps then ps_rss(pid)
      end
    end

    ##
    # True when resident memory can be read on this platform.

    def self.readable?
      !source.nil?
    end

    def self.poll_interval
      source == :ps ? PS_INTERVAL : PROC_INTERVAL
    end

    ##
    # :proc, :ps or nil, decided once.

    def self.source
      return @source if defined?(@source)

      @source = if proc_status(Process.pid, "VmRSS")
                  :proc
                elsif ps_rss(Process.pid)
                  :ps
                end
    end

    def self.source=(value)
      @source = value
    end

    ##
    # Lowers this process's soft RLIMIT_DATA so that data can grow by about
    # +slack+ bytes beyond what the memory +limit+ allows. Never raises it.
    # Needs /proc, since the limit is set from VmData. An allocation that
    # crosses it fails with NoMemoryError, which no polling can catch in
    # time when one C call allocates a lot at once. Processes started from
    # this one inherit the limit.

    def self.backstop(limit, slack = BACKSTOP_SLACK)
      data = proc_status(Process.pid, "VmData")
      resident = proc_status(Process.pid, "VmRSS")
      return unless data && resident

      soft, hard = Process.getrlimit(:DATA)
      wanted = [data + [limit - resident, 0].max + slack, hard].min
      Process.setrlimit(:DATA, wanted, hard) if soft > wanted
    rescue SystemCallError, NotImplementedError, ArgumentError
      nil
    end

    def self.proc_status(pid, key)
      kb = File.read("/proc/#{pid}/status")[/^#{key}:\s+(\d+) kB/, 1]
      kb && Integer(kb) * 1024
    rescue SystemCallError, IOError
      nil
    end
    private_class_method :proc_status

    def self.ps_rss(pid)
      out = IO.popen(["ps", "-o", "rss=", "-p", pid.to_s], err: File::NULL, &:read)
      kb = out[/\A\s*(\d+)\s*\z/, 1]
      kb && Integer(kb) * 1024
    rescue SystemCallError, IOError
      nil
    end
    private_class_method :ps_rss
  end
end
