require "minitest/autorun"
require "open3"
require "rbconfig"

# Heckle#tests_pass? runs Minitest in-process, so it is exercised in a
# subprocess against the fixture project rather than inside this suite.
class TestTestsPass < Minitest::Test
  LIB = File.expand_path("../lib", __dir__)
  PROJECT = File.expand_path("fixtures/minitest_project", __dir__)

  # Counts test runs in $runs and prints the count after every other
  # at_exit handler, including any Minitest would register.
  PRELUDE = <<~RUBY
    require "heckle"
    require "doubler"
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
      Heckle.load_tests(Dir.glob("test/test_*.rb"))
      p Heckle.new("Doubler", "double").tests_pass?
    RUBY
  end

  def test_failing_suite
    assert_drive "false\nruns=1\n", <<~RUBY
      Heckle.load_tests(["test/broken_doubler_test.rb"])
      p Heckle.new("Doubler", "double").tests_pass?
    RUBY
  end

  def test_repeated_calls_follow_the_code_under_test
    assert_drive "[true, false, true]\nruns=9\n", <<~RUBY
      Heckle.load_tests(Dir.glob("test/test_*.rb"))
      heckle = Heckle.new("Doubler", "double", [:if])
      results = [heckle.tests_pass?]
      heckle.install(heckle.mutations.first)
      results << heckle.tests_pass?
      heckle.restore
      results << heckle.tests_pass?
      p results
    RUBY
  end

  def test_skips_count_as_passing
    assert_drive "true\nruns=1\n", <<~RUBY
      class SkippingTest < Minitest::Test
        def test_skipped; skip "later"; end
      end
      p Heckle.new("Doubler", "double").tests_pass?
    RUBY
  end

  def test_suite_output_is_silenced
    assert_drive "true\nruns=1\n", <<~RUBY
      class NoisyTest < Minitest::Test
        def test_noise; puts "out"; warn "err"; $stderr.puts "err"; end
      end
      p Heckle.new("Doubler", "double").tests_pass?
    RUBY
  end

  def test_debug_shows_suite_output
    out, err, status = drive(<<~RUBY)
      class NoisyTest < Minitest::Test
        def test_noise; puts "out"; end
      end
      Heckle.debug = true
      Heckle.new("Doubler", "double").tests_pass?
    RUBY

    assert status.success?
    assert_equal "", err
    assert_includes out, "\nout\n"
    assert_includes out, "1 runs, 0 assertions, 0 failures, 0 errors, 0 skips"
  end

  def test_autorun_does_not_run_the_suite_at_exit
    out, err, status = drive(<<~RUBY)
      Heckle.load_tests(Dir.glob("test/test_*.rb"))
    RUBY

    assert status.success?
    assert_equal "", err
    assert_equal "runs=0\n", out
  end

  def test_timeout_escapes_the_test
    assert_drive "Heckle::Timeout\nruns=1\n", <<~RUBY
      class SlowTest < Minitest::Test
        def test_a; sleep 5; end
        def test_b; sleep 5; end
      end
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      begin
        Timeout.timeout(0.2, Heckle::Timeout) { Heckle.new("Doubler", "double").tests_pass? }
      rescue Heckle::Timeout => e
        p e.class
      end
      abort "slow" if Process.clock_gettime(Process::CLOCK_MONOTONIC) - started > 2
    RUBY
  end
end
