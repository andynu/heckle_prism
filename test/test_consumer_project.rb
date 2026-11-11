require "minitest/autorun"
require "open3"
require "rbconfig"

# A project that depends on heckle by Gemfile path and runs it with
# bundle exec, as a user would.
class TestConsumerProject < Minitest::Test
  PROJECT = File.expand_path("fixtures/consumer_project", __dir__)

  # The outer bundle's RUBYOPT and BUNDLE_* variables would make the
  # subprocess load this repository's bundle instead of the fixture's.
  def bundle_exec(*args)
    env = { "BUNDLE_GEMFILE" => File.join(PROJECT, "Gemfile") }
    run = -> { Open3.capture3(env, RbConfig.ruby, Gem.bin_path("bundler", "bundle"), "exec", *args, chdir: PROJECT) }
    defined?(Bundler) ? Bundler.with_unbundled_env(&run) : run.()
  end

  def test_heckles_the_whole_class
    out, err, status = bundle_exec("heckle", "Thermometer")

    assert_equal "", err
    loaded = out.scan(/^\*\*\*  (Thermometer#\S+) loaded/).flatten
    assert_equal %w[Thermometer#fahrenheit Thermometer#initialize Thermometer#self.freezing], loaded
    assert_includes out, "Passed    :   3\nFailed    :   0\nThick Skin:   0\n"
    refute_match(/\d+ runs, \d+ assertions/, out)
    assert_equal 0, status.exitstatus
  end

  # heckle ... | head: the reader closes stdout mid-run, here while a mutant
  # is installed. Bundler's command dispatcher turns an Errno::EPIPE
  # escaping into it into exit status 0.
  def test_closed_stdout_ends_non_zero_with_methods_restored
    env = { "BUNDLE_GEMFILE" => File.join(PROJECT, "Gemfile") }
    args = [RbConfig.ruby, Gem.bin_path("bundler", "bundle"), "exec", "heckle", "Thermometer",
            "-v", "-t", "pipe/thermometer_pipe_test.rb"]
    run = lambda do
      Open3.popen3(env, *args, chdir: PROJECT) do |stdin, stdout, stderr, thread|
        stdin.close
        stdout.each_line.find { |line| line == "mutant installed\n" }
        stdout.close
        [stderr.read, thread.value]
      end
    end
    err, status = defined?(Bundler) ? Bundler.with_unbundled_env(&run) : run.()

    refute status.success?, "exit status #{status.inspect}"
    assert_equal 1, status.exitstatus
    assert_equal ["at exit: [212, 32]"], err.lines.map(&:chomp)
  end

  def test_uses_the_heckle_in_this_repository
    out, err, status = bundle_exec("ruby", "-e", 'require "heckle"; puts $LOADED_FEATURES.grep(/heckle\.rb\z/)')

    assert status.success?, err
    assert_equal [File.expand_path("../lib/heckle.rb", __dir__)], out.lines.map(&:chomp)
  end
end
