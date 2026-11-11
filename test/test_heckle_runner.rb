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
  BROKEN = %w[--tests broken/broken_doubler_test.rb].freeze

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

  def test_bin_is_tracked_executable
    root = File.expand_path("..", __dir__)
    out, _, status = Open3.capture3("git", "ls-files", "-s", "bin/heckle", chdir: root)

    assert status.success?
    assert_match(/\A100755 /, out)
  end

  def test_full_coverage
    out, err, status = heckle("Doubler", "double")

    assert_equal "", err
    assert_includes out, "Initial tests pass. Let's rumble."
    assert_includes out, "***  Doubler#double loaded with 5 possible mutations"
    assert_includes out, "No mutants survived. Cool!\n\n0 of 5 mutants survived\n\n"
    assert_equal 0, status.exitstatus
  end

  def test_partial_coverage
    out, err, status = heckle("Doubler", "double", *PARTIAL)

    assert_equal "", err
    assert_includes out, "The following mutations didn't cause test failures:"
    assert_includes out, "--- original\n+++ mutation\n"
    assert_includes out, "\n def double x\n   if Numeric === x\n     x * 2\n   else\n-    \"NaN\"\n"
    refute_includes out, "No mutants survived."
    assert_match(/^ end\n\n1 of 5 mutants survived\n\nHeckle Results:\n/, out)
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
      Mutants   :   5 killed, 0 survived

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
    assert_includes out, "Tally#label has a thick skin."
    assert_includes out, "Passed    :   3\nFailed    :   0\nThick Skin:   1\n"
    assert_equal 0, status.exitstatus
  end

  # Money is a Data.define class whose methods are defined in its block.
  def test_whole_class_defined_by_a_block
    out, err, status = heckle("Money", "-t", "test/money_test.rb")

    assert_equal "", err
    refute_includes out, "Skipping"
    loaded = out.scan(/^\*\*\*  (Money#\S+) loaded/).flatten
    assert_equal %w[Money#dollars Money#self.zero], loaded
    assert_includes out, "Passed    :   2\nFailed    :   0\nThick Skin:   0\nMutants   :   6 killed, 0 survived\n"
    assert_equal 0, status.exitstatus
  end

  # Gauge#calibrated is defined by test/fixtures/outside_helper.rb, outside
  # the project; Gauge#level and #level= by attr_accessor inside it.
  def test_whole_class_leaves_out_methods_defined_outside_the_project
    out, err, status = heckle("Gauge")

    assert_equal "", err
    refute_includes out, "calibrated"
    assert_includes out, "Skipping Gauge#level: no def at"
    assert_includes out, "Skipping Gauge#level=: no def at"
    assert_includes out, "Passed    :   1\nFailed    :   0\nThick Skin:   0\n"
    assert_equal 0, status.exitstatus
  end

  def test_verbose_notes_methods_defined_outside_the_project
    out, _err, status = heckle("Gauge", "-v")

    helper = File.expand_path("fixtures/outside_helper.rb", __dir__)
    assert_includes out, "Skipping Gauge#calibrated: defined outside the project, at #{helper}:5\n"
    assert_includes out, "Skipping Gauge#level: no def at"
    assert_equal 0, status.exitstatus
  end

  def test_named_method_outside_the_project_still_errors
    _out, err, status = heckle("Gauge", "calibrated")

    refute status.success?
    assert_match(/\AGauge#calibrated: no def at .*outside_helper\.rb:5\n\z/, err)
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
    assert_includes out, "Doubler#double has a thick skin."
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

  # One pipe for both streams, as with 2>&1 into a file.
  def test_stdout_is_not_reordered_against_stderr
    out, status = Open3.capture2e(RbConfig.ruby, BIN, "Doubler", "double", "-T", "7", *BROKEN, chdir: PROJECT)

    refute status.success?
    assert_equal ["Setting timeout at 7 seconds.", "Initial run of tests failed... fix and run heckle again"],
                 out.lines.map(&:chomp)
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

  # halver_test.rb and test_quarter.rb sit in test/units and require
  # "test_helper", which requires "halver" from the project's lib.
  def test_default_patterns_find_nested_tests_of_both_names
    out, err, status = heckle("Halver")

    assert_equal "", err
    assert_includes out, "Passed    :   2\nFailed    :   0\n"
    assert_equal 0, status.exitstatus
  end

  def test_tests_option_replaces_the_default_patterns
    out, _err, status = heckle("Halver", "-t", "test/units/*_test.rb")

    assert_includes out, "Passed    :   1\nFailed    :   1\n"
    assert_includes out, "-  x / 4\n"
    assert_equal 1, status.exitstatus
  end

  # quarter survives under halver_test.rb alone and dies once test_quarter.rb
  # is loaded as well.
  def test_tests_option_repeated_loads_every_pattern
    alone, _err, status = heckle("Halver", "-t", "test/units/h*_test.rb")
    assert_includes alone, "Passed    :   1\nFailed    :   1\n"
    assert_equal 1, status.exitstatus

    both, err, status = heckle("Halver", "-t", "test/units/h*_test.rb", "-t", "test/units/test_quarter.rb")
    assert_equal "", err
    assert_includes both, "Passed    :   2\nFailed    :   0\n"
    assert_equal 0, status.exitstatus
  end

  # A typo in one -t would otherwise silently narrow the tests.
  def test_tests_option_pattern_matching_nothing_aborts_among_others
    assert_aborts "No test files match test/unit/test_quarter.rb", "Halver",
                  "-t", "test/units/h*_test.rb", "-t", "test/unit/test_quarter.rb"
  end

  # halve is fully covered by test/units/halver_test.rb; quarter not at all.
  def test_whole_class_totals_with_a_mix
    out, _err, _status = heckle("Halver", "-t", "test/units/*_test.rb")

    assert_equal ["0 of 2 mutants survived", "2 of 2 mutants survived"],
                 out.scan(/^\d+ of \d+ mutants survived$/)
    assert_includes out, "Thick Skin:   0\nMutants   :   2 killed, 2 survived\n\nImprove the tests"
  end

  def test_whole_class_totals_leave_out_thick_skins
    out, _err, _status = heckle("Tally", *TALLY)

    assert_equal 3, out.scan(/^\d+ of \d+ mutants survived$/).size
    assert_match(/^Thick Skin:   1\nMutants   : +\d+ killed, 0 survived\n\n/, out)
  end

  def test_default_patterns_skip_files_outside_test
    out, _err, status = heckle("Doubler", "double")

    assert_includes out, "Initial tests pass."
    assert_equal 0, status.exitstatus
  end

  # Run straight from the checkout, with no Bundler to set up heckle's lib.
  def test_runs_from_the_checkout_without_bundler
    run = -> { Open3.capture3(RbConfig.ruby, BIN, "Halver", "halve", chdir: PROJECT) }
    out, err, status = defined?(Bundler) ? Bundler.with_unbundled_env(&run) : run.()

    assert_equal "", err
    assert_includes out, "No mutants survived."
    assert_equal 0, status.exitstatus
  end

  def test_verbose
    out, _err, _status = heckle("Doubler", "double", "-n", "if", "-v", "-t", "test/test_doubler_*.rb")

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
    assert_includes out, "default: test/**/test_*.rb and test/**/*_test.rb"
    assert_includes out, "Repeat to load more"
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
    assert_equal %w[test/**/test_*.rb test/**/*_test.rb], options[:test_pattern]
    assert_equal false, options[:force]
    assert_equal false, options[:debug]
    assert_nil options[:timeout]
    refute options.key?(:focus)
    assert_equal "", out
  end

  def test_parse_args_single_tests_option_replaces_the_defaults
    options, _rest, _out = parse("-t", "spec/*_spec.rb", "Doubler")

    assert_equal %w[spec/*_spec.rb], options[:test_pattern]
  end

  def test_parse_args_tests_option_accumulates
    options, rest, _out = parse("-t", "test/models/a*_test.rb", "Doubler", "--tests", "test/models/b_test.rb")

    assert_equal %w[test/models/a*_test.rb test/models/b_test.rb], options[:test_pattern]
    assert_equal %w[Doubler], rest
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
