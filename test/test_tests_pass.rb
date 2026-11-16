require "minitest/autorun"
require "open3"
require "rbconfig"
require "bounded_process"
require "heckle_prism/watchdog"

# HecklePrism#tests_pass? runs Minitest in-process, so it is exercised in a
# subprocess against the fixture project rather than inside this suite.
class TestTestsPass < Minitest::Test
  LIB = File.expand_path("../lib", __dir__)
  PROJECT = File.expand_path("fixtures/minitest_project", __dir__)

  # Counts test runs in $runs and prints the count after every other
  # at_exit handler, including any Minitest would register.
  PRELUDE = <<~RUBY
    require "heckle_prism"
    require "squarer"
    $runs = 0
    at_exit { puts "runs=\#{$runs}" }
    Minitest::Test.prepend(Module.new { def before_setup; $runs += 1; super; end })
  RUBY

  def drive(script)
    Open3.capture3(RbConfig.ruby, "-I", LIB, "-I", "lib", "-e", PRELUDE + script, chdir: PROJECT)
  end

  def assert_drive(expected_out, script)
    out, err, status = drive(script)

    assert_equal "", err
    assert_equal expected_out, out
    assert status.success?, "driver exited #{status.exitstatus}"
  end

  def test_passing_suite
    assert_drive "true\nruns=3\n", <<~RUBY
      HecklePrism.load_tests(Dir.glob("test/test_*.rb"))
      p HecklePrism.new("Squarer", "square").tests_pass?
    RUBY
  end

  def test_failing_suite
    assert_drive "false\nruns=1\n", <<~RUBY
      HecklePrism.load_tests(["broken/broken_squarer_test.rb"])
      p HecklePrism.new("Squarer", "square").tests_pass?
    RUBY
  end

  def test_repeated_calls_follow_the_code_under_test
    assert_drive "[true, false, true]\nruns=9\n", <<~RUBY
      HecklePrism.load_tests(Dir.glob("test/test_*.rb"))
      heckle = HecklePrism.new("Squarer", "square", [:if])
      results = [heckle.tests_pass?]
      heckle.install(heckle.mutations.first)
      results << heckle.tests_pass?
      heckle.restore
      results << heckle.tests_pass?
      p results
    RUBY
  end

  # Each suite run reseeds the global RNG with Minitest.seed, so with one
  # test class the global state after every run is the same. Twenty draws
  # repeat by chance with probability 200**-20.
  def test_suite_runs_do_not_repeat_random_replacements
    assert_drive "false\nruns=2\n", <<~RUBY
      HecklePrism.load_tests(["test/test_squarer_with_a_number.rb", "test/test_helper.rb"])
      draws = [HecklePrism.new("Squarer", "square"), HecklePrism.new("Halver", "halve")].map do |heckle|
        heckle.tests_pass?
        Array.new(20) { heckle.rand_number }
      end
      p draws.first == draws.last
    RUBY
  end

  def test_skips_count_as_passing
    assert_drive "true\nruns=1\n", <<~RUBY
      class SkippingTest < Minitest::Test
        def test_skipped; skip "later"; end
      end
      p HecklePrism.new("Squarer", "square").tests_pass?
    RUBY
  end

  def test_suite_output_is_silenced
    assert_drive "true\nruns=1\n", <<~RUBY
      class NoisyTest < Minitest::Test
        def test_noise; puts "out"; warn "err"; $stderr.puts "err"; end
      end
      p HecklePrism.new("Squarer", "square").tests_pass?
    RUBY
  end

  def test_debug_shows_suite_output
    out, err, status = drive(<<~RUBY)
      class NoisyTest < Minitest::Test
        def test_noise; puts "out"; end
      end
      HecklePrism.debug = true
      HecklePrism.new("Squarer", "square").tests_pass?
    RUBY

    assert status.success?
    assert_equal "", err
    assert_includes out, "\nout\n"
    assert_includes out, "1 runs, 0 assertions, 0 failures, 0 errors, 0 skips"
  end

  def test_autorun_does_not_run_the_suite_at_exit
    out, err, status = drive(<<~RUBY)
      HecklePrism.load_tests(Dir.glob("test/test_*.rb"))
    RUBY

    assert status.success?
    assert_equal "", err
    assert_equal "runs=0\n", out
  end

  def test_timeout_escapes_the_test
    assert_drive "HecklePrism::Timeout\nruns=1\n", <<~RUBY
      require "timeout"
      class SlowTest < Minitest::Test
        def test_a; sleep 5; end
        def test_b; sleep 5; end
      end
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      begin
        Timeout.timeout(0.2, HecklePrism::Timeout) { HecklePrism.new("Squarer", "square").tests_pass? }
      rescue HecklePrism::Timeout => e
        p e.class
      end
      abort "slow" if Process.clock_gettime(Process::CLOCK_MONOTONIC) - started > 2
    RUBY
  end

  # Runs +script+ after PRELUDE with Minitest's parallel executor at four
  # workers, under a backstop, since it provokes runaway tests.
  def drive_bounded(script)
    command = [{ "MT_CPU" => "4" }, RbConfig.ruby, "-I", LIB, "-I", "lib", "-e", PRELUDE + script]
    BoundedProcess.capture3(*command, chdir: PROJECT, seconds: 30)
  end

  # A run that times out, then one that passes, each under a watchdog.
  ESCAPE_THEN_PASS = <<~'RUBY'.freeze
    def now
      Process.clock_gettime(Process::CLOCK_MONOTONIC)
    end

    def watched(seconds)
      HecklePrism::Watchdog.new(seconds, "swallowed\n").watch { HecklePrism.tests_pass? }
    rescue HecklePrism::Timeout
      :timeout
    end

    threads = Thread.list.size
    $spin = true
    p watched(0.3)
    started = now
    HecklePrism.settle
    puts(now - started < 2 ? "settled" : "settled slowly")
    $spin = false
    p watched(5)
    p Thread.list.size == threads
  RUBY

  # The stopped run leaves the executor's workers waiting on its queue,
  # where they would take the signals that end the next run's workers.
  def test_settle_after_an_escaped_timeout_frees_the_next_run
    run = drive_bounded(<<~'RUBY' + ESCAPE_THEN_PASS)
      class SpinTest < Minitest::Test
        def test_spin
          loop {} if $spin
        end
      end
    RUBY

    refute run.killed, run.out
    assert_equal ["", ":timeout\nsettled\ntrue\ntrue\nruns=2\n"], [run.err, run.out]
  end

  # A parallel test still spinning in a worker when the run is stopped is
  # killed, so it cannot run on beside the next run.
  def test_settle_stops_a_worker_stuck_in_a_parallel_test
    run = drive_bounded(<<~'RUBY' + ESCAPE_THEN_PASS)
      class ParallelSpinTest < Minitest::Test
        parallelize_me!

        def test_spin
          loop {} if $spin
        end
      end
    RUBY

    refute run.killed, run.out
    assert_equal ["", ":timeout\nsettled\ntrue\ntrue\nruns=2\n"], [run.err, run.out]
  end

  # Minitest skips the teardown hooks of a test an exception passes
  # through. settle runs them, quietly, as Minitest runs them after a
  # failure: each in turn, errors captured, against the restored code.
  def test_settle_runs_the_teardown_a_stopped_test_skipped
    run = drive_bounded(<<~'RUBY')
      $events = []
      Minitest::Test.prepend(Module.new do
        def after_teardown
          $events << :after_teardown
          super
        end
      end)
      class SpinTest < Minitest::Test
        def setup
          $events << :setup
        end

        def teardown
          puts "teardown output"
          $events << :teardown
          raise "teardown broke"
        end

        def test_spin
          loop {}
        end
      end
      begin
        HecklePrism::Watchdog.new(0.3, "swallowed\n").watch { HecklePrism.tests_pass? }
      rescue HecklePrism::Timeout
        p $events
      end
      HecklePrism.settle
      p $events
      HecklePrism.settle
      p $events
    RUBY

    refute run.killed, run.out
    assert_equal ["", "[:setup]\n[:setup, :teardown, :after_teardown]\n" \
                      "[:setup, :teardown, :after_teardown]\nruns=1\n"], [run.err, run.out]
  end

  # A teardown that swallows the timeout heckle raises in it ends the
  # process, as a test run that does so does.
  def test_settle_ends_the_process_when_the_teardown_swallows_its_timeout
    run = drive_bounded(<<~'RUBY')
      class StuckTeardownTest < Minitest::Test
        def teardown
          begin
            sleep
          rescue Exception
            retry
          end
        end

        def test_spin
          loop {}
        end
      end
      $stdout.sync = true
      HecklePrism.timeout = 1
      begin
        HecklePrism::Watchdog.new(0.3, "swallowed\n").watch { HecklePrism.tests_pass? }
      rescue HecklePrism::Timeout
        puts "stopped"
      end
      HecklePrism.settle
      puts "not reached"
    RUBY

    refute run.killed, run.out
    assert_equal "stopped\n", run.out
    assert_equal HecklePrism::Watchdog::EXIT_STATUS, run.status.exitstatus
    assert run.err.start_with?("heckle_prism: the teardown of StuckTeardownTest#test_spin, which heckle ran after " \
                               "its test was stopped,\nwas still running 2 seconds after the 1 second timeout"), run.err
    assert_includes run.err, "--fork"
  end

  # A worker that cannot be killed (here it holds off interrupts, as a
  # thread inside one long C call does) may go on running the mutant
  # beside the next mutant's tests, so heckle no longer vouches for them.
  def test_settle_records_a_worker_it_cannot_stop
    run = drive_bounded(<<~'RUBY')
      $hold = true
      class HeldTest < Minitest::Test
        parallelize_me!

        def test_hold
          Thread.handle_interrupt(Object => :never) { sleep 0.01 while $hold }
        end
      end
      p HecklePrism.unsettled
      begin
        HecklePrism::Watchdog.new(0.3, "swallowed\n").watch { HecklePrism.tests_pass? }
      rescue HecklePrism::Timeout
        puts "stopped"
      end
      HecklePrism.settle
      puts HecklePrism.unsettled
      $hold = false
    RUBY

    refute run.killed, run.out
    assert_equal ["", "nil\nstopped\na test thread of an earlier mutant's run could not be stopped " \
                      "and may still be running\nruns=1\n"], [run.err, run.out]
  end

  def test_settle_records_a_teardown_that_runs_over
    run = drive_bounded(<<~'RUBY')
      class SlowTeardownTest < Minitest::Test
        def teardown
          sleep 5
        end

        def test_spin
          loop {}
        end
      end
      HecklePrism.timeout = 1
      begin
        HecklePrism::Watchdog.new(0.3, "swallowed\n").watch { HecklePrism.tests_pass? }
      rescue HecklePrism::Timeout
        puts "stopped"
      end
      HecklePrism.settle
      puts HecklePrism.unsettled
    RUBY

    refute run.killed, run.out
    assert_equal ["", "stopped\nthe teardown of SlowTeardownTest#test_spin, which heckle ran after its test " \
                      "was stopped, did not finish within the 1 second timeout\nruns=1\n"], [run.err, run.out]
  end

  def test_settle_without_a_stopped_run_does_nothing
    assert_drive "true\nnil\ntrue\nruns=3\n", <<~RUBY
      HecklePrism.load_tests(Dir.glob("test/test_*.rb"))
      executor = Minitest.parallel_executor
      p HecklePrism.new("Squarer", "square").tests_pass?
      p HecklePrism.settle
      p Minitest.parallel_executor.equal?(executor)
    RUBY
  end
end
