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

  def test_uses_the_heckle_in_this_repository
    out, err, status = bundle_exec("ruby", "-e", 'require "heckle"; puts $LOADED_FEATURES.grep(/heckle\.rb\z/)')

    assert status.success?, err
    assert_equal [File.expand_path("../lib/heckle.rb", __dir__)], out.lines.map(&:chomp)
  end
end
