require "minitest/autorun"
require "open3"
require "rbconfig"
require "heckle_prism_runner"
require "bounded_process"

# bin/heckle runs Minitest in-process, so it is exercised as a subprocess in
# the fixture project.
class TestHecklePrismRunner < Minitest::Test
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

  # For mutants that run away: a heckle that fails to contain one is
  # killed by the backstop, and the test fails, instead of the machine.
  def bounded_heckle(*args, seconds: 30)
    BoundedProcess.capture3(RbConfig.ruby, BIN, *args, chdir: PROJECT, seconds: seconds)
  end

  IMPORTER = %w[Importer count_rows -n call -T 1].freeze
  TIMEOUT_WARNING = "!!! Your tests timed out. Heckle may have caused an infinite loop.\n".freeze

  # The second mutant makes count_rows loop forever. The application
  # rescues StandardError around it, and a second test calls it again.
  def test_timeout_is_not_swallowed_by_a_rescue_of_standard_error
    run = bounded_heckle(*IMPORTER, "-t", "runaway/importer_test.rb")

    refute run.killed, "heckle did not finish; stdout:\n#{run.out}"
    assert_equal "", run.err
    assert_includes run.out, TIMEOUT_WARNING
    assert_includes run.out, "0 of 2 mutants survived\n1 timed out\n\n"
    assert_includes run.out, "Mutants   :   1 killed, 1 timed out, 0 survived\n"
    assert_equal 0, run.status.exitstatus
  end

  # Each test swallows one timeout and then passes. Once the timeout has
  # fired, the run's outcome says nothing, so the second mutant is not a
  # survivor even though every test passed.
  def test_timeout_swallowed_once_counts_as_a_timeout
    run = bounded_heckle(*IMPORTER, "-t", "runaway/stubborn_importer_test.rb")

    refute run.killed, "heckle did not finish; stdout:\n#{run.out}"
    assert_equal "", run.err
    assert_includes run.out, TIMEOUT_WARNING
    assert_includes run.out, "-  (@sheet.first..@sheet.last).each { rows += 1 }\n+  (nil..@sheet.last)"
    assert_includes run.out, "1 of 2 mutants survived\n1 timed out\n\n"
    assert_includes run.out, "Mutants   :   0 killed, 1 timed out, 1 survived\n"
    assert_equal 1, run.status.exitstatus
  end

  # import_retrying swallows every timeout, so the watchdog ends the process
  # without running at_exit handlers.
  def test_timeout_swallowed_for_good_ends_the_process
    run = bounded_heckle("Importer", "count_to_last", "-n", "call", "-T", "1",
                         "-t", "runaway/retrying_importer_test.rb")

    refute run.killed, "heckle did not finish; stdout:\n#{run.out}"
    assert_equal HecklePrism::Watchdog::EXIT_STATUS, run.status.exitstatus
    assert_operator run.elapsed, :<, 1 + HecklePrism::Watchdog::GRACE + 5
    assert_includes run.err, "heckle: Importer#count_to_last: the tests were still running"
    assert_includes run.err, "swallowed"
    assert_includes run.err, "--- original\n+++ mutation\n def count_to_last\n   rows = 0\n" \
                             "-  (1..@sheet.last).each { rows += 1 }\n+  (1..nil).each { rows += 1 }\n" \
                             "   rows\n end\n"
    assert_includes run.err, "--fork"
    refute_includes run.err, "at_exit ran"
    assert_includes run.out, "1 mutations remaining...\n"
    refute_includes run.out, "Heckle Results"
  end

  # What the report advises: the child is killed and the run goes on.
  def test_timeout_swallowed_for_good_is_contained_by_fork
    run = bounded_heckle("Importer", "count_to_last", "-n", "call", "-T", "1", "--fork",
                         "-t", "runaway/retrying_importer_test.rb")

    refute run.killed, "heckle did not finish; stdout:\n#{run.out}"
    assert_equal "at_exit ran\n", run.err
    assert_includes run.out, TIMEOUT_WARNING
    assert_includes run.out, "0 of 1 mutants survived\n1 timed out\n\n"
    assert_includes run.out, "Mutants   :   0 killed, 1 timed out, 0 survived\n"
    assert_equal 0, run.status.exitstatus
  end

  LEDGER = %w[-n call -T 1 -t runaway/ledger_test.rb].freeze
  BANG = "#{'!' * 70}\n".freeze
  TALLY_TIMED_OUT = "#{TIMEOUT_WARNING}#{BANG}\n" \
                    "--- original\n+++ mutation\n def tally\n   @notes << :tallied\n   rows = 0\n" \
                    "-  (1..@entries.size).each { rows += 1 }\n+  (1..nil).each { rows += 1 }\n" \
                    "   rows\n end\n\n".freeze

  # Ledger#tally's first mutant survives and its second loops forever.
  def test_timeout_warning_shows_the_mutant
    [[], ["--fork"]].each do |mode|
      run = bounded_heckle("Ledger", "tally", *LEDGER, *mode)

      refute run.killed, "heckle did not finish #{mode}; stdout:\n#{run.out}"
      assert_equal "", run.err
      assert_includes run.out, "1 mutations remaining...\n#{BANG}#{TALLY_TIMED_OUT}\nThe following mutations"
      assert_match(/^ end\n\n1 of 2 mutants survived\n1 timed out\n\nHeckle Results:\n/, run.out)
      assert_includes run.out, "Thick Skin:   0\nMutants   :   0 killed, 1 timed out, 1 survived\n\nImprove"
      assert_equal 1, run.status.exitstatus, mode
    end
  end

  # first is clean, initialize has nothing to mutate, and tally has a
  # survivor and a timeout.
  def test_whole_class_totals_with_a_timeout
    [[], ["--fork"]].each do |mode|
      run = bounded_heckle("Ledger", *LEDGER, *mode)

      refute run.killed, "heckle did not finish #{mode}; stdout:\n#{run.out}"
      assert_equal "", run.err
      assert_equal ["0 of 1 mutants survived\n\n", "1 of 2 mutants survived\n1 timed out\n\n"],
                   run.out.scan(/^\d+ of \d+ mutants survived\n(?:\d+ timed out\n)?\n/)
      assert_includes run.out, "Ledger#initialize has a thick skin."
      assert_includes run.out, <<~OUT
        Heckle Results:

        Passed    :   1
        Failed    :   1
        Thick Skin:   1
        Mutants   :   1 killed, 1 timed out, 1 survived

        Improve the tests and try again.
      OUT
      assert_equal 1, run.status.exitstatus, mode
    end
  end

  def test_mutants_line
    assert_equal "Mutants   :   5 killed, 0 survived", HecklePrismRunner.mutants_line(5, {}, 0)
    assert_equal "Mutants   : 389 killed, 2 timed out, 81 survived",
                 HecklePrismRunner.mutants_line(389, { timeout: 2 }, 81)
    assert_equal "Mutants   : 1200 killed, 2 timed out, 1 crashed, 1 canceled, 3 survived",
                 HecklePrismRunner.mutants_line(1200, { canceled: 1, timeout: 2, crash: 1 }, 3)
  end

  RELAY_SURVIVOR = "The following mutations didn't cause test failures:\n\n" \
                   "--- original\n+++ mutation\n def pass_on\n   rows = 0\n" \
                   "   (1..@entries.size).each { rows += 1 }\n-  @notes << rows\n+  nil\n" \
                   "   @entries.first\n end\n\n1 of 3 mutants survived\n1 timed out\n\n".freeze

  # Relay#pass_on's first mutant loops forever. The two after it, a
  # survivor and a kill, must get the outcomes they get on their own.
  def assert_judged_after_a_timeout(run, label)
    refute run.killed, "heckle did not finish #{label}; stdout:\n#{run.out}"
    assert_equal "", run.err, label
    assert_equal 1, run.out.scan(TIMEOUT_WARNING).size, label
    assert_includes run.out, RELAY_SURVIVOR, label
    assert_includes run.out, "Mutants   :   1 killed, 1 timed out, 1 survived\n", label
    assert_equal 1, run.status.exitstatus, label
  end

  def test_mutants_after_a_timeout_are_judged_on_their_own
    [[], ["--fork"]].each do |mode|
      run = bounded_heckle("Relay", "pass_on", "-n", "call", "-T", "1", "-t", "runaway/relay_test.rb", *mode)

      assert_judged_after_a_timeout(run, mode.inspect)
    end
  end

  # The test rescues the timeout once and returns, failing.
  def test_mutants_after_a_swallowed_timeout_are_judged_on_their_own
    run = bounded_heckle("Relay", "pass_on", "-n", "call", "-T", "1", "-t", "runaway/stubborn_relay_test.rb")

    assert_judged_after_a_timeout(run, "stubborn")
  end

  # The test's setup fails while the state its teardown resets is still
  # set, as a database transaction left open would make later tests fail.
  def test_mutants_after_a_timeout_get_the_teardown_their_test_skipped
    run = bounded_heckle("Relay", "pass_on", "-n", "call", "-T", "1", "-t", "runaway/teardown_relay_test.rb")

    assert_judged_after_a_timeout(run, "teardown")
  end

  # The teardown heckle runs after the timeout runs over too, so the
  # process may still hold its test's state: the later mutants are not
  # run in-process, and --fork judges them.
  def test_mutants_after_a_teardown_that_runs_over_are_not_run
    args = ["Relay", "pass_on", "-n", "call", "-T", "1", "-t", "runaway/slow_teardown_relay_test.rb"]
    run = bounded_heckle(*args)

    refute run.killed, "heckle did not finish; stdout:\n#{run.out}"
    assert_equal "", run.err
    assert_equal 2, run.out.scan("!!! Not run: the teardown of SlowTeardownRelayTest#test_pass_on, which heckle " \
                                 "ran after its test was stopped, did not finish within the 1 second timeout.").size
    assert_includes run.out, "run heckle with --fork to judge it.\n#{BANG}\n--- original\n"
    assert_includes run.out, "1 mutations remaining...\n#{BANG}!!! Not run: "
    refute_includes run.out, "No mutants survived."
    refute_includes run.out, "YAY"
    assert run.out.end_with?(" end\n\n0 of 3 mutants survived\n1 timed out, 2 not run\n\n" \
                             "Heckle Results:\n\nPassed    :   0\nFailed    :   0\nThick Skin:   0\n" \
                             "Not Run   :   1\n" \
                             "Mutants   :   0 killed, 1 timed out, 2 not run, 0 survived\n\n" \
                             "2 mutants were not run. Run heckle with --fork to judge them.\n"), run.out
    assert_equal 1, run.status.exitstatus

    assert_judged_after_a_timeout(bounded_heckle(*args, "--fork"), "fork")
  end

  # hand_over's note survives, then its loop times out and the teardown
  # runs over, so its last mutant is not run.
  def test_survivor_and_mutants_not_run
    run = bounded_heckle("Relay", "hand_over", "-n", "call", "-T", "1", "-t", "runaway/slow_teardown_relay_test.rb")

    refute run.killed, "heckle did not finish; stdout:\n#{run.out}"
    assert_equal "", run.err
    assert run.out.end_with?(" end\n\n1 of 3 mutants survived\n1 timed out, 1 not run\n\n" \
                             "Heckle Results:\n\nPassed    :   0\nFailed    :   1\nThick Skin:   0\n" \
                             "Mutants   :   0 killed, 1 timed out, 1 not run, 1 survived\n\n" \
                             "Improve the tests and try again.\n" \
                             "1 mutant was not run. Run heckle with --fork to judge it.\n"), run.out
    assert_equal 1, run.status.exitstatus
  end

  # first is judged, initialize has nothing to mutate, pass times out and
  # its teardown runs over, so its second mutant and peek's are not run.
  def test_whole_class_with_mutants_not_run
    run = bounded_heckle("Baton", "-n", "call", "-T", "1", "-t", "runaway/slow_teardown_baton_test.rb")

    refute run.killed, "heckle did not finish; stdout:\n#{run.out}"
    assert_equal "", run.err
    assert_equal ["0 of 1 mutants survived\n\n", "0 of 2 mutants survived\n1 timed out, 1 not run\n\n",
                  "0 of 1 mutants survived\n1 not run\n\n"],
                 run.out.scan(/^\d+ of \d+ mutants survived\n(?:\d+ [a-z, 0-9]+\n)?\n/)
    assert_equal 1, run.out.scan("No mutants survived. Cool!").size
    assert run.out.end_with?("Heckle Results:\n\nPassed    :   1\nFailed    :   0\nThick Skin:   1\n" \
                             "Not Run   :   2\n" \
                             "Mutants   :   1 killed, 1 timed out, 2 not run, 0 survived\n\n" \
                             "2 mutants were not run. Run heckle with --fork to judge them.\n"), run.out
    assert_equal 1, run.status.exitstatus
  end

  # In fork mode a mutant over the memory limit is killed and the run goes
  # on; gather's later mutants are four survivors and a kill.
  def test_mutants_after_a_memory_kill_are_judged_on_their_own
    run = bounded_heckle("Relay", "gather", "-n", "call", "--memory-limit", "150", "--fork",
                         "-t", "runaway/relay_test.rb")

    refute run.killed, "heckle did not finish; stdout:\n#{run.out}"
    assert_equal "", run.err
    assert_includes run.out, "4 of 6 mutants survived\n1 ran out of memory\n\n"
    assert_includes run.out, "Mutants   :   1 killed, 1 ran out of memory, 4 survived\n"
    assert_equal 1, run.status.exitstatus
  end

  HOARDER = %w[Hoarder load -n call -t runaway/hoarder_test.rb].freeze

  def memory_limit_line(out)
    out[/^Timeout set to \d+ seconds\.\n(Memory limit.*)\n/, 1]
  end

  # The first mutant holds a megabyte more every few milliseconds.
  def test_memory_limit_ends_the_process_in_process
    run = bounded_heckle(*HOARDER, "--memory-limit", "150")

    refute run.killed, "heckle did not finish; stdout:\n#{run.out}"
    assert_equal "Memory limit set to 150 MB.", memory_limit_line(run.out)
    assert_equal HecklePrism::Watchdog::EXIT_STATUS, run.status.exitstatus
    resident = run.err[/\Aheckle: Hoarder#load: the tests went over the memory limit of 150 MB\n\(resident memory (\d+) MB\)/, 1]
    assert resident, run.err
    assert_operator Integer(resident), :<, 150 + 150
    assert_includes run.err, "-  (1..@rows.size).each { held << chunk }\n+  (1..nil).each { held << chunk }\n"
    assert_includes run.err, "--fork"
    assert_includes run.out, "5 mutations remaining...\n"
    refute_includes run.out, "4 mutations remaining"
  end

  def test_memory_limit_kills_only_the_child_in_fork_mode
    run = bounded_heckle(*HOARDER, "--memory-limit", "150", "--fork")

    refute run.killed, "heckle did not finish; stdout:\n#{run.out}"
    assert_equal "", run.err
    assert_equal "Memory limit set to 150 MB.", memory_limit_line(run.out)
    assert_includes run.out, "!!! The forked test run went over the memory limit of 150 MB and was killed. " \
                             "Not counted as a survivor.\n"
    assert_includes run.out, "-  (1..@rows.size).each { held << chunk }\n+  (1..nil).each { held << chunk }\n"
    assert_includes run.out, "0 of 5 mutants survived\n1 ran out of memory\n\n"
    assert_includes run.out, "Mutants   :   4 killed, 1 ran out of memory, 0 survived\n"
    assert_equal 0, run.status.exitstatus
  end

  # Resident memory after the unmutated run, plus the larger of 1 GiB and
  # that amount again.
  def test_memory_limit_default
    out, err, status = heckle("Doubler", "double", "-n", "if")

    assert_equal "", err
    limit = memory_limit_line(out)[/\AMemory limit set to (\d+) MB\.\z/, 1]
    assert limit, out
    assert_includes 1025..1024 + 500, Integer(limit)
    assert_equal 0, status.exitstatus
  end

  def test_memory_limit_zero_turns_it_off
    run = bounded_heckle(*HOARDER, "-n", "if", "--memory-limit", "0")

    assert_equal "", run.err
    assert_equal "Memory limit off.", memory_limit_line(run.out)
    assert_equal 0, run.status.exitstatus
  end

  def test_memory_limit_must_be_a_whole_number_of_megabytes
    assert_aborts "invalid argument: --memory-limit lots", "Doubler", "--memory-limit", "lots"
    assert_aborts "invalid argument: --memory-limit -1", "Doubler", "--memory-limit", "-1"
  end

  def test_memory_limit_not_enforced_where_memory_cannot_be_read
    script = "require 'heckle_prism'; HecklePrism::Memory.source = nil; load #{BIN.dump}"
    out, err, status = Open3.capture3(RbConfig.ruby, "-I", File.expand_path("../lib", __dir__),
                                      "-e", script, "Doubler", "double", chdir: PROJECT)

    assert_equal "", err
    assert_equal "Memory limit not enforced: resident memory cannot be read on this platform.",
                 memory_limit_line(out)
    assert_equal 1, out.scan("Memory limit").size
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

  # "abc".to_i is 0, and a zero timeout meant no timeout in-process and an
  # instant one in fork mode.
  def test_timeout_must_be_a_positive_whole_number_of_seconds
    assert_aborts "invalid argument: -T 0", "Doubler", "double", "-T", "0"
    assert_aborts "invalid argument: --timeout -3", "Doubler", "double", "--timeout", "-3"
    assert_aborts "invalid argument: -T soon", "Doubler", "double", "-T", "soon"
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

    %w[--verbose --tests --force --assignments --branches --timeout --nodes --exclude-nodes --fork
       --memory-limit].each do |flag|
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

    assert_includes out, HecklePrism::VERSION
    assert_equal 0, status.exitstatus
  end

  # The same commands with and without --fork give the same output once
  # the random replacements are removed: they appear only on the
  # mutation side of a survivor's diff.
  # The default memory limit is measured, so it can differ by a megabyte.
  def strip_replacements(out)
    out.gsub(/^\+(?!\+\+ ).*$/, "+").sub(/^Memory limit set to \d+ MB\.$/, "Memory limit set to N MB.")
  end

  FORK_COMMANDS = [
    %w[Doubler double],
    ["Doubler", "double", *PARTIAL],
    ["Doubler", *PARTIAL],
    ["Tally", *TALLY],
    %w[Halver -t test/units/*_test.rb],
    %w[Money -t test/money_test.rb],
    %w[Doubler double --force --tests broken/broken_doubler_test.rb],
    %w[Gauge],
  ].freeze

  def test_fork_output_matches_in_process
    FORK_COMMANDS.each do |args|
      out, err, status = heckle(*args)
      fork_out, fork_err, fork_status = heckle(*args, "--fork")

      assert_equal [strip_replacements(out), err, status.exitstatus],
                   [strip_replacements(fork_out), fork_err, fork_status.exitstatus], args.join(" ")
    end
  end

  ROOT = File.expand_path("..", __dir__)

  # Runs in which every mutant was killed or survived, with the exit status
  # each gave. fixtures/output_3.0.0 holds what 3.0.0 printed for them,
  # put through strip_replacements and with its checkout's path as ROOT.
  UNCHANGED_COMMANDS = {
    "doubler_double" => [%w[Doubler double], 0],
    "doubler_double_partial" => [["Doubler", "double", *PARTIAL], 1],
    "doubler_partial" => [["Doubler", *PARTIAL], 1],
    "tally" => [["Tally", *TALLY], 0],
    "halver_units" => [%w[Halver -t test/units/*_test.rb], 1],
    "doubler_double_forced" => [%w[Doubler double --force --tests broken/broken_doubler_test.rb], 0],
    "gauge" => [%w[Gauge], 0],
  }.freeze

  def test_output_without_unjudged_mutants_is_unchanged_from_3_0_0
    UNCHANGED_COMMANDS.each do |name, (args, exit_status)|
      out, err, status = heckle(*args)
      expected = File.read(File.join(__dir__, "fixtures", "output_3.0.0", "#{name}.txt"))

      assert_equal [expected, "", exit_status],
                   [strip_replacements(out).gsub(ROOT, "ROOT"), err, status.exitstatus], name
    end
  end

  def test_fork_survivor_and_exit_status
    out, err, status = heckle("Halver", "-t", "test/units/*_test.rb", "--fork")

    assert_equal "", err
    assert_includes out, "-  x / 4\n"
    assert_includes out, "Mutants   :   2 killed, 2 survived\n"
    assert_equal 1, status.exitstatus
  end

  def test_fork_unsupported_aborts
    script = "class << Process; undef_method :fork; end; load #{BIN.dump}"
    out, err, status = Open3.capture3(RbConfig.ruby, "-e", script, "Doubler", "double", "--fork", chdir: PROJECT)

    refute status.success?
    assert_equal ["--fork needs Process.fork, which this Ruby does not have"], err.lines.map(&:chomp)
    assert_equal "", out
  end

  # parse_args sets HecklePrism's global configuration.
  def parse(*args)
    saved = %i[@@debug @@timeout @@guess_timeout @@fork].map { |name| HecklePrism.class_variable_get(name) }
    out, _err = capture_io { @options = HecklePrismRunner.parse_args(args) }
    [@options, args, out]
  ensure
    %i[@@debug @@timeout @@guess_timeout @@fork].zip(saved) { |name, value| HecklePrism.class_variable_set(name, value) }
  end

  def test_parse_args_fork
    options, rest, out = parse("--fork", "Doubler")

    assert_equal true, options[:fork]
    assert_equal %w[Doubler], rest
    assert_equal "", out
  end

  def test_parse_args_fork_sets_heckle
    saved = HecklePrism.fork?
    capture_io { HecklePrismRunner.parse_args(%w[--fork]) }
    assert_equal true, HecklePrism.fork?
    capture_io { HecklePrismRunner.parse_args(%w[Doubler]) }
    assert_equal false, HecklePrism.fork?
  ensure
    HecklePrism.fork = saved
  end

  def test_parse_args_defaults
    options, rest, out = parse("Doubler", "double")

    assert_equal %w[Doubler double], rest
    assert_equal HecklePrism::MUTATABLE_NODES, options[:nodes]
    assert_equal %w[test/**/test_*.rb test/**/*_test.rb], options[:test_pattern]
    assert_equal false, options[:force]
    assert_equal false, options[:debug]
    assert_nil options[:timeout]
    refute options.key?(:fork)
    refute options.key?(:memory_limit)
    refute options.key?(:focus)
    assert_equal "", out
  end

  def test_parse_args_memory_limit
    options, rest, out = parse("--memory-limit", "300", "Doubler")

    assert_equal 300, options[:memory_limit]
    assert_equal %w[Doubler], rest
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
    guess = HecklePrism.guess_timeout?
    parse("Doubler")

    assert_equal guess, HecklePrism.guess_timeout?
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
