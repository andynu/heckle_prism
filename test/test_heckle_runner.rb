require "minitest/autorun"
require "open3"
require "rbconfig"
require "heckle_runner"

# bin/heckle runs Minitest in-process, so it is exercised as a subprocess in
# the fixture project.
class TestHeckleRunner < Minitest::Test
  BIN = File.expand_path("../bin/heckle", __dir__)
  PROJECT = File.expand_path("fixtures/minitest_project", __dir__)
  PARTIAL = %w[--tests test/test_doubler_with_a_number.rb].freeze
  TALLY = %w[--tests test/tally_test.rb].freeze
  BROKEN = %w[--tests test/broken_doubler_test.rb].freeze

  def heckle(*args)
    Open3.capture3(RbConfig.ruby, BIN, *args, chdir: PROJECT)
  end

  # A one-line message on stderr, no Ruby backtrace, non-zero exit.
  def assert_aborts(message, *args)
    out, err, status = heckle(*args)

    refute status.success?
    assert_equal [message], err.lines.map(&:chomp)
    refute_match(/\.rb:\d+:in /, out + err)
    out
  end

  def test_full_coverage
    out, err, status = heckle("Doubler", "double")

    assert_equal "", err
    assert_includes out, "Initial tests pass. Let's rumble."
    assert_includes out, "***  Doubler#double loaded with 5 possible mutations"
    assert_includes out, "No mutants survived."
    assert_equal 0, status.exitstatus
  end

  def test_partial_coverage
    out, err, status = heckle("Doubler", "double", *PARTIAL)

    assert_equal "", err
    assert_includes out, "The following mutations didn't cause test failures:"
    assert_includes out, "--- original\n+++ mutation\n"
    assert_includes out, "\n-      \"NaN\"\n"
    refute_includes out, "No mutants survived."
    assert_equal 1, status.exitstatus
  end

  def test_whole_class_summary
    out, _err, status = heckle("Doubler")

    assert_includes out, "No mutants survived."
    assert_includes out, <<~OUT
      Heckle Results:

      Passed    :   1
      Failed    :   0
      Thick Skin:   0

      All heckling was thwarted! YAY!!!
    OUT
    assert_equal 0, status.exitstatus
  end

  def test_whole_class_summary_with_survivor
    out, _err, status = heckle("Doubler", *PARTIAL)

    assert_includes out, "Failed    :   1\n"
    assert_includes out, "Improve the tests and try again."
    assert_equal 1, status.exitstatus
  end

  def test_whole_class_covers_class_private_and_empty_methods
    out, _err, status = heckle("Tally", *TALLY)

    assert_includes out, "Skipping Tally#count: no def at"
    loaded = out.scan(/^\*\*\*  (Tally#\S+) loaded/).flatten
    assert_equal %w[Tally#bump Tally#initialize Tally#self.start], loaded
    assert_includes out, "label has a thick skin."
    assert_includes out, "Passed    :   3\nFailed    :   0\nThick Skin:   1\n"
    assert_equal 0, status.exitstatus
  end

  def test_nodes_option_limits_mutations
    out, _err, status = heckle("Doubler", "double", "-n", "if")

    assert_includes out, "Mutating nodes: [:if]"
    assert_includes out, "loaded with 1 possible mutations"
    assert_equal 0, status.exitstatus
  end

  def test_exclude_nodes_option
    out, _err, _status = heckle("Doubler", "double", "-x", "if,str")

    assert_includes out, "Mutating without nodes: [:if, :str]"
    assert_includes out, "loaded with 3 possible mutations"
  end

  def test_node_alias
    out, _err, _status = heckle("Tally", "bump", "-n", "dasgn", *TALLY)

    assert_includes out, "loaded with 1 possible mutations"
  end

  def test_branches_option
    out, _err, _status = heckle("Doubler", "double", "-b")

    assert_includes out, "!!! Heckling branches only"
    assert_includes out, "loaded with 1 possible mutations"
  end

  def test_assignments_option
    out, _err, status = heckle("Tally", "bump", "--assignments", *TALLY)

    assert_includes out, "!!! Heckling assignments only"
    assert_includes out, "loaded with 2 possible mutations"
    assert_equal 0, status.exitstatus

    out, _err, status = heckle("Doubler", "double", "--assignments")
    assert_includes out, "double has a thick skin."
    assert_equal 0, status.exitstatus
  end

  def test_unknown_class
    assert_aborts "Unknown class: Nope", "Nope", "double"
    assert_aborts "Unknown class: Nope", "Nope"
    assert_aborts "Unknown class: Doubler::Nope", "Doubler::Nope"
  end

  def test_unknown_method
    assert_aborts "Doubler#nope: no such method", "Doubler", "nope"
    assert_aborts "Doubler#self.nope: no such method", "Doubler", "self.nope"
  end

  def test_unknown_node_kind
    assert_aborts "Unknown mutation kind: bogus", "Doubler", "double", "-n", "if,bogus"
  end

  def test_no_matching_test_files
    assert_aborts "No test files match nothing/*.rb", "Doubler", "double", "-t", "nothing/*.rb"
  end

  def test_missing_class_argument
    _out, err, status = heckle

    refute status.success?
    assert_includes err, "Usage: heckle class_name [method_name]"
  end

  def test_unknown_option
    _out, err, status = heckle("Doubler", "--bogus")

    refute status.success?
    assert_includes err, "invalid option: --bogus"
    refute_match(/\.rb:\d+:in /, err)
  end

  def test_failing_initial_run_aborts
    out = assert_aborts "Initial run of tests failed... fix and run heckle again",
                        "Doubler", "double", *BROKEN

    refute_includes out, "loaded with"
  end

  def test_force_proceeds_after_failing_initial_run
    out, _err, status = heckle("Doubler", "double", "--force", *BROKEN)

    assert_includes out, "Initial tests failed but you forced things. Let's rumble."
    assert_includes out, "No mutants survived."
    assert_equal 0, status.exitstatus
  end

  def test_timeout_guess
    out, _err, _status = heckle("Doubler", "double", "-n", "if")

    assert_includes out, "Timeout set to 5 seconds."
  end

  def test_timeout_option
    out, _err, _status = heckle("Doubler", "double", "-n", "if", "-T", "7")

    assert_includes out, "Setting timeout at 7 seconds."
    assert_includes out, "Timeout set to 7 seconds."
  end

  def test_verbose
    out, _err, _status = heckle("Doubler", "double", "-n", "if", "-v")

    assert_includes out, "debug: true"
    assert_includes out, "Replacing Doubler#double with:"
    assert_includes out, "Tests failed -- this is good"
    assert_includes out, "3 runs, 3 assertions, 0 failures, 0 errors, 0 skips"
  end

  def test_help
    out, _err, status = heckle("--help")

    %w[--verbose --tests --force --assignments --branches --timeout --nodes --exclude-nodes].each do |flag|
      assert_includes out, flag
    end
    refute_includes out, "--focus"
    refute_includes out, "sauron"
    assert_equal 0, status.exitstatus
  end

  def test_version
    out, _err, status = heckle("--version")

    assert_includes out, Heckle::VERSION
    assert_equal 0, status.exitstatus
  end

  # parse_args sets Heckle's global configuration.
  def parse(*args)
    saved = %i[@@debug @@timeout @@guess_timeout].map { |name| Heckle.class_variable_get(name) }
    out, _err = capture_io { @options = HeckleRunner.parse_args(args) }
    [@options, args, out]
  ensure
    %i[@@debug @@timeout @@guess_timeout].zip(saved) { |name, value| Heckle.class_variable_set(name, value) }
  end

  def test_parse_args_defaults
    options, rest, out = parse("Doubler", "double")

    assert_equal %w[Doubler double], rest
    assert_equal Heckle::MUTATABLE_NODES, options[:nodes]
    assert_equal "test/test_*.rb", options[:test_pattern]
    assert_equal false, options[:force]
    assert_equal false, options[:debug]
    assert_nil options[:timeout]
    refute options.key?(:focus)
    assert_equal "", out
  end

  def test_parse_args_leaves_timeout_guess_unless_given
    guess = Heckle.guess_timeout?
    parse("Doubler")

    assert_equal guess, Heckle.guess_timeout?
  end

  def test_parse_args_exclusions_apply_to_selection
    options, _rest, _out = parse("-b", "-x", "while")

    assert_equal %i[if until], options[:nodes]
  end

  def test_parse_args_exclusions_accept_aliases
    options, _rest, _out = parse("-x", "dasgn")

    refute_includes options[:nodes], :lasgn
  end
end
