require "minitest/autorun"
require "open3"
require "rbconfig"
require "tmpdir"
require "fixtures/heckle_dummy"
require "fixtures/heckle_subjects"
require "fixtures/heckle_frozen"
require "fixtures/heckle_blocks"
require "fixtures/heckle_shorthand" if RUBY_VERSION >= "3.1"
require "fixtures/heckle_data" if RUBY_VERSION >= "3.2"
require "heckle"

class TestHeckler < Heckle
  def rand_number
    5
  end

  def rand_string
    "l33t h4x0r"
  end

  def rand_symbol
    :"l33t h4x0r"
  end

  def rand_range
    5..10
  end
end

# Records reporter calls as [name, *args] instead of printing.
class RecordingReporter
  attr_reader :calls

  def initialize
    @calls = []
  end

  %i[no_mutations method_loaded remaining_mutations warning info no_failures
     failure no_surviving_mutants mutant_totals replacing report_test_failures].each do |name|
    define_method(name) { |*args| @calls << [name, *args] }
  end

  def names
    calls.map(&:first)
  end
end

# tests_pass? answers from a script called with the heckler.
class ScriptedHeckler < TestHeckler
  attr_accessor :script

  def tests_pass?
    script.call(self)
  end
end

class TestHeckle < Minitest::Test
  DUMMY = File.expand_path("fixtures/heckle_dummy.rb", __dir__)
  SUBJECTS = File.expand_path("fixtures/heckle_subjects.rb", __dir__)
  FROZEN = File.expand_path("fixtures/heckle_frozen.rb", __dir__)

  def heckle(klass_name, method_name, nodes = Heckle::MUTATABLE_NODES)
    heckler = TestHeckler.new(klass_name, method_name, nodes)
    (@hecklers ||= []) << heckler
    heckler
  end

  # In-process unless a test says otherwise, whatever heckle --fork set
  # when this suite is itself heckled.
  def setup
    @fork = Heckle.fork?
    Heckle.fork = false
  end

  def teardown
    (@hecklers || []).each(&:restore)
    Heckle.fork = @fork
  end

  # Installs the only mutation of klass_name#method_name of the given kinds.
  def install_only(klass_name, method_name, nodes)
    heckler = heckle(klass_name, method_name, nodes)
    assert_equal 1, heckler.mutations.size
    heckler.install(heckler.mutations.first)
    heckler
  end

  def test_install_and_restore_instance_method
    heckler = install_only("HeckleSubjects", "answer", [:lit])

    assert_equal 47, HeckleSubjects.new.answer
    heckler.restore
    assert_equal 42, HeckleSubjects.new.answer
  end

  def test_install_and_restore_self_class_method
    heckler = install_only("HeckleSubjects", "self.class_answer", [:lit])

    assert_equal 47, HeckleSubjects.class_answer
    heckler.restore
    assert_equal 42, HeckleSubjects.class_answer
  end

  def test_install_and_restore_singleton_class_method
    heckler = install_only("HeckleSubjects", "self.singleton_answer", [:lit])

    assert_equal 47, HeckleSubjects.singleton_answer
    heckler.restore
    assert_equal 42, HeckleSubjects.singleton_answer
  end

  def test_private_method_stays_private
    heckler = install_only("HeckleSubjects", "hidden_answer", [:lit])

    assert HeckleSubjects.private_method_defined?(:hidden_answer, false)
    assert_equal 47, HeckleSubjects.new.call_hidden
    assert_raises(NoMethodError) { HeckleSubjects.new.hidden_answer }

    heckler.restore
    assert HeckleSubjects.private_method_defined?(:hidden_answer, false)
    assert_equal 42, HeckleSubjects.new.call_hidden
    assert_raises(NoMethodError) { HeckleSubjects.new.hidden_answer }
  end

  def test_protected_method_stays_protected
    heckler = install_only("HeckleSubjects", "guarded_answer", [:lit])

    assert HeckleSubjects.protected_method_defined?(:guarded_answer, false)
    assert_equal 47, HeckleSubjects.new.call_guarded(HeckleSubjects.new)
    assert_raises(NoMethodError) { HeckleSubjects.new.guarded_answer }

    heckler.restore
    assert HeckleSubjects.protected_method_defined?(:guarded_answer, false)
    assert_equal 42, HeckleSubjects.new.call_guarded(HeckleSubjects.new)
  end

  def test_public_method_stays_public
    heckler = install_only("HeckleSubjects", "answer", [:lit])

    assert HeckleSubjects.public_method_defined?(:answer, false)
    heckler.restore
    assert HeckleSubjects.public_method_defined?(:answer, false)
  end

  def test_mutant_resolves_constants_of_enclosing_module
    heckler = install_only("HeckleNesting::Inner", "limit", [:lit])

    assert_equal 16, HeckleNesting::Inner.new.limit
    heckler.restore
    assert_equal 11, HeckleNesting::Inner.new.limit
  end

  # Data arrived in Ruby 3.2.
  if RUBY_VERSION >= "3.2"
    def test_install_and_restore_data_define_method
      heckler = install_only("HeckleBlocks::Point", "sum", [:lit])

      assert_equal 14, HeckleBlocks::Point.new(x: 3, y: 5).sum
      heckler.restore
      assert_equal 9, HeckleBlocks::Point.new(x: 3, y: 5).sum
    end

    def test_install_and_restore_data_define_self_method
      heckler = install_only("HeckleBlocks::Point", "self.origin_sum", [:lit])

      assert_equal 47, HeckleBlocks::Point.origin_sum
      heckler.restore
      assert_equal 42, HeckleBlocks::Point.origin_sum
    end
  end

  def test_install_and_restore_struct_method_using_module_constant
    heckler = install_only("HeckleBlocks::Pair", "scaled", [:lit])

    assert_equal 26, HeckleBlocks::Pair.new(2, 0).scaled
    heckler.restore
    assert_equal 21, HeckleBlocks::Pair.new(2, 0).scaled
  end

  def test_install_and_restore_struct_singleton_method
    heckler = install_only("HeckleBlocks::Pair", "self.answer", [:lit])

    assert_equal 47, HeckleBlocks::Pair.answer
    heckler.restore
    assert_equal 42, HeckleBlocks::Pair.answer
  end

  def test_struct_private_method_stays_private
    heckler = install_only("HeckleBlocks::Pair", "hidden", [:lit])

    assert HeckleBlocks::Pair.private_method_defined?(:hidden, false)
    assert_equal 47, HeckleBlocks::Pair.new.call_hidden
    heckler.restore
    assert HeckleBlocks::Pair.private_method_defined?(:hidden, false)
    assert_equal 42, HeckleBlocks::Pair.new.call_hidden
  end

  def test_install_and_restore_class_new_method
    heckler = install_only("HeckleBlocks::Child", "answer", [:lit])

    assert_equal 47, HeckleBlocks::Child.new.answer
    assert_equal HeckleBlocks::Base, HeckleBlocks::Child.superclass
    heckler.restore
    assert_equal 42, HeckleBlocks::Child.new.answer
  end

  # The block's lexical scope is the module, so SCALE is the module's even
  # though the class has a SCALE of its own.
  def test_block_scope_mutant_keeps_the_block_constant_lookup
    assert_equal 11, HeckleBlocks::Child.new.scaled
    heckler = install_only("HeckleBlocks::Child", "scaled", [:lit])

    assert_equal 16, HeckleBlocks::Child.new.scaled
    heckler.restore
    assert_equal 11, HeckleBlocks::Child.new.scaled
  end

  def test_install_and_restore_module_new_method
    heckler = install_only("HeckleBlocks::Mixin", "mixed", [:lit])
    holder = Object.new.extend(HeckleBlocks::Mixin)

    assert_equal 47, holder.mixed
    heckler.restore
    assert_equal 42, holder.mixed
  end

  def test_block_scope_install_is_silent_under_verbose
    verbose = $VERBOSE
    assert_silent do
      $VERBOSE = true
      heckler = install_only("HeckleBlocks::Pair", "scaled", [:lit])
      heckler.restore
    end
  ensure
    $VERBOSE = verbose
  end

  class UnparsableInstallHeckler < TestHeckler
    def mutant_source(_mutation)
      "def answer\n  47\nend end"
    end
  end

  def test_restore_after_install_raised
    heckler = UnparsableInstallHeckler.new("HeckleSubjects", "answer", [:lit])
    (@hecklers ||= []) << heckler

    assert_raises(SyntaxError) { heckler.install(nil) }
    heckler.restore
    assert_equal 42, HeckleSubjects.new.answer
  end

  # Heckling Heckle::Mutation#apply: building the mutant source calls the
  # method being replaced.
  def test_install_builds_the_mutant_before_removing_the_method
    heckler = heckle("Heckle::Mutation", "apply", [:lasgn])
    mutation = heckler.mutations.first

    heckler.install(mutation)
    assert_raises(TypeError, NoMethodError) { mutation.apply("x") }
    heckler.restore
    assert_equal "a = 7", Heckle::Mutation.new(kind: :lit, start_offset: 4, end_offset: 5,
                                               replacement: "7").apply("a = 1")
  end

  def test_survivor_text_is_built_without_the_mutant
    heckler = scripted("Heckle::Mutation", "apply", [:lasgn]) { true }
    expected = heckler.mutations.map { |mutation| heckler.mutant_source(mutation) }

    heckler.validate

    assert_equal expected, heckler.failures
    assert_includes expected.first, "start = nil"
  end

  def test_class_with_superclass_is_reopened
    heckler = install_only("HeckleSubjectsChild", "own_answer", [:lit])

    assert_equal 47, HeckleSubjectsChild.new.own_answer
    assert_equal HeckleSubjects, HeckleSubjectsChild.superclass
    heckler.restore
    assert_equal 42, HeckleSubjectsChild.new.own_answer
  end

  def test_two_installs_then_one_restore
    heckler = heckle("HeckleSubjects", "pair", [:lit])
    first, second = heckler.mutations

    heckler.install(first)
    assert_equal [6, 2], HeckleSubjects.new.pair
    heckler.install(second)
    assert_equal [1, 7], HeckleSubjects.new.pair
    heckler.restore
    assert_equal [1, 2], HeckleSubjects.new.pair
  end

  def test_restore_without_install_keeps_original
    heckler = heckle("HeckleSubjects", "answer", [:lit])
    original = HeckleSubjects.instance_method(:answer)

    heckler.restore
    assert_equal original, HeckleSubjects.instance_method(:answer)
  end

  def test_restore_without_install_leaves_another_install_alone
    idle = heckle("HeckleSubjects", "answer", [:lit])
    other = install_only("HeckleSubjects", "answer", [:lit])

    idle.restore
    assert_equal 47, HeckleSubjects.new.answer
    other.restore
    assert_equal 42, HeckleSubjects.new.answer
  end

  def test_second_restore_leaves_another_install_alone
    first = install_only("HeckleSubjects", "answer", [:lit])
    first.restore
    other = install_only("HeckleSubjects", "answer", [:lit])

    first.restore
    assert_equal 47, HeckleSubjects.new.answer
    other.restore
  end

  def test_install_and_restore_leave_verbose_as_it_was
    verbose = $VERBOSE
    $VERBOSE = true
    heckler = install_only("HeckleSubjects", "answer", [:lit])
    assert_equal true, $VERBOSE
    heckler.restore
    assert_equal true, $VERBOSE
  ensure
    $VERBOSE = verbose
  end

  # The parent defines answer too, so the child's must not be taken as
  # still defined once install has removed it.
  def test_restore_after_failed_install_of_an_override
    heckler = UnparsableInstallHeckler.new("HeckleSubjectsChild", "answer", [:lit])
    (@hecklers ||= []) << heckler

    assert_raises(SyntaxError) { heckler.install(nil) }
    heckler.restore
    assert_equal 43, HeckleSubjectsChild.new.answer
    assert_equal HeckleSubjectsChild, HeckleSubjectsChild.instance_method(:answer).owner
  end

  # BasicObject defines a private initialize.
  def test_restore_after_failed_install_of_initialize
    heckler = UnparsableInstallHeckler.new("HeckleSubjectsInit", "initialize", [:lit])
    (@hecklers ||= []) << heckler
    verbose, $VERBOSE = $VERBOSE, nil

    assert_raises(SyntaxError) { heckler.install(nil) }
    heckler.restore
    assert_equal 42, HeckleSubjectsInit.new.value
    assert HeckleSubjectsInit.private_method_defined?(:initialize, false)
  ensure
    $VERBOSE = verbose
  end

  def test_public_method_named_like_a_private_kernel_method_stays_public
    heckler = install_only("HeckleSubjects", "format", [:lit])

    assert HeckleSubjects.public_method_defined?(:format, false)
    assert_equal 47, HeckleSubjects.new.format
    heckler.restore
    assert HeckleSubjects.public_method_defined?(:format, false)
  end

  def test_public_override_of_a_protected_method_stays_public
    heckler = install_only("HeckleSubjectsChild", "guarded_answer", [:lit])

    assert_equal 49, HeckleSubjectsChild.new.guarded_answer
    heckler.restore
    assert_equal 44, HeckleSubjectsChild.new.guarded_answer
  end

  def test_install_and_restore_constant_path_block_scope
    heckler = install_only("HeckleBlocks::Tagged", "label", [:lit])

    assert_equal 47, HeckleBlocks::Tagged.new.label
    heckler.restore
    assert_equal 42, HeckleBlocks::Tagged.new.label
  end

  def test_load_tests_requires_each_file_and_holds_off_autorun
    saved = Minitest.class_variable_get(:@@installed_at_exit)
    Minitest.class_variable_set(:@@installed_at_exit, false)
    Dir.mktmpdir do |dir|
      paths = %w[a b].map do |name|
        File.join(dir, "#{name}.rb").tap { |path| File.write(path, "$heckle_loaded << #{name.dump}\n") }
      end
      $heckle_loaded = []

      Heckle.load_tests(paths)

      assert_equal %w[a b], $heckle_loaded
      assert_equal true, Minitest.class_variable_get(:@@installed_at_exit)
    end
  ensure
    Minitest.class_variable_set(:@@installed_at_exit, saved)
  end

  # Stands in for SimpleCov when it is not loaded.
  module FakeSimpleCov
    class << self
      attr_accessor :external_at_exit
    end
  end

  def test_load_tests_turns_off_the_simplecov_report
    fake = !defined?(::SimpleCov)
    Object.const_set(:SimpleCov, FakeSimpleCov) if fake
    saved = ::SimpleCov.external_at_exit
    ::SimpleCov.external_at_exit = false

    Heckle.load_tests([])

    assert_equal true, ::SimpleCov.external_at_exit
  ensure
    ::SimpleCov.external_at_exit = saved
    Object.send(:remove_const, :SimpleCov) if fake
  end

  def test_setting_the_timeout_ends_the_guess
    with_timeout(60) do
      Heckle.class_variable_set(:@@guess_timeout, true)
      Heckle.timeout = 3

      refute Heckle.guess_timeout?
      assert_equal 3, Heckle.timeout
    end
  end

  def test_restore_keeps_original_source_location
    location = HeckleSubjects.instance_method(:answer).source_location
    heckler = install_only("HeckleSubjects", "answer", [:lit])
    heckler.restore

    assert_equal [SUBJECTS, 4], location.first(2)
    assert_equal location, HeckleSubjects.instance_method(:answer).source_location
  end

  def test_mutant_backtrace_points_at_original_file_and_line
    install_only("HeckleSubjects", "explode", [:str])

    error = assert_raises(ArgumentError) { HeckleSubjects.new.explode }
    assert_equal "l33t h4x0r", error.message
    frame = error.backtrace_locations.first
    assert_equal [SUBJECTS, 24], [frame.path, frame.lineno]
    assert_equal "raise ArgumentError, \"kaboom\"", File.readlines(SUBJECTS)[23].strip
  end

  def test_install_and_restore_initialize_silently_under_verbose
    verbose = $VERBOSE
    assert_silent do
      $VERBOSE = true
      heckler = install_only("HeckleSubjectsInit", "initialize", [:lit])
      assert_equal 47, HeckleSubjectsInit.new.value
      heckler.restore
    end
    assert_equal 42, HeckleSubjectsInit.new.value
    assert HeckleSubjectsInit.private_method_defined?(:initialize, false)
  ensure
    $VERBOSE = verbose
  end

  def test_mutant_keeps_frozen_string_literal_comment
    assert_equal [1, true], HeckleFrozen.new.literal_frozen
    install_only("HeckleFrozen", "literal_frozen", [:lit])

    assert_equal [6, true], HeckleFrozen.new.literal_frozen
  end

  def test_mutant_backtrace_line_with_magic_comment
    install_only("HeckleFrozen", "explode", [:lit])

    error = assert_raises(ArgumentError) { HeckleFrozen.new.explode }
    frame = error.backtrace_locations.first
    assert_equal [FROZEN, 10], [frame.path, frame.lineno]
    assert_equal "raise ArgumentError, \"kaboom\"", File.readlines(FROZEN)[9].strip
  end

  def test_install_with_magic_comment_is_silent_under_verbose
    verbose = $VERBOSE
    assert_silent do
      $VERBOSE = true
      heckler = heckle("HeckleFrozen", "literal_frozen", [:lit])
      heckler.install(heckler.mutations.first)
      heckler.restore
    end
  ensure
    $VERBOSE = verbose
  end

  def scripted(klass_name, method_name, nodes, reporter = RecordingReporter.new, &script)
    heckler = ScriptedHeckler.new(klass_name, method_name, nodes, reporter)
    heckler.script = script
    (@hecklers ||= []) << heckler
    heckler
  end

  def with_timeout(seconds)
    saved = [Heckle.class_variable_get(:@@timeout), Heckle.class_variable_get(:@@guess_timeout)]
    Heckle.timeout = seconds
    yield
  ensure
    Heckle.class_variable_set(:@@timeout, saved[0])
    Heckle.class_variable_set(:@@guess_timeout, saved[1])
  end

  def test_validate_without_mutations
    reporter = RecordingReporter.new
    heckler = scripted("HeckleDummy", "uses_nothing", Heckle::MUTATABLE_NODES, reporter) { flunk "no run expected" }

    assert_nil heckler.validate
    assert_equal [[:no_mutations, "HeckleDummy", :uses_nothing]], reporter.calls
    assert_equal 0, heckler.count
  end

  def test_validate_all_killed
    reporter = RecordingReporter.new
    heckler = scripted("HeckleSubjects", "pair", [:lit], reporter) { false }

    assert_equal true, heckler.validate
    assert_equal [
      [:method_loaded, "HeckleSubjects", :pair, 2],
      [:remaining_mutations, 2],
      [:report_test_failures],
      [:remaining_mutations, 1],
      [:report_test_failures],
      [:no_surviving_mutants],
      [:mutant_totals, 0, 2],
    ], reporter.calls
    assert_empty heckler.failures
    assert_equal 2, heckler.count
  end

  def test_validate_with_survivor
    reporter = RecordingReporter.new
    heckler = scripted("HeckleSubjects", "pair", [:lit], reporter) { |h| h.count == 1 }
    survivor = "def pair\n    [6, 2]\n  end"

    assert_equal false, heckler.validate
    assert_equal [survivor], heckler.failures
    assert_equal [:no_failures, :failure, :mutant_totals], reporter.names.last(3)
    assert_equal [:failure, "def pair\n  [1, 2]\nend", "def pair\n  [6, 2]\nend"], reporter.calls[-2]
    assert_equal [:mutant_totals, 1, 2], reporter.calls.last
  end

  LETTER = [
    'def letter(name)',
    '      %s name',
    '        heading = "Dear',
    '  #{name},"',
    '      end',
    '      <<-TEXT',
    '#{heading}',
    '  thanks',
    '      TEXT',
    '    end',
  ].join("\n")

  LETTER_SHOWN = [
    'def letter(name)',
    '  %s name',
    '    heading = "Dear',
    '  #{name},"',
    '  end',
    '  <<-TEXT',
    '#{heading}',
    '  thanks',
    '  TEXT',
    'end',
  ].join("\n")

  def test_reported_survivor_is_dedented_and_failures_keep_mutant_source
    reporter = RecordingReporter.new
    heckler = scripted("HeckleNesting::Inner", "letter", [:if], reporter) { true }

    assert_equal false, heckler.validate
    assert_equal [LETTER % "unless"], heckler.failures
    assert_equal [:failure, LETTER_SHOWN % "if", LETTER_SHOWN % "unless"], reporter.calls[-2]
  end

  def test_debug_replacement_is_dedented
    reporter = RecordingReporter.new
    heckler = scripted("HeckleNesting::Inner", "letter", [:if], reporter) { false }
    debug = Heckle.debug
    Heckle.debug = true

    heckler.validate

    replacing = reporter.calls.find { |call| call.first == :replacing }
    assert_equal [:replacing, "HeckleNesting::Inner", :letter,
                  LETTER_SHOWN % "if", LETTER_SHOWN % "unless"], replacing
  ensure
    Heckle.debug = debug
  end

  def test_dedent_uses_the_def_line_indentation
    reporter = RecordingReporter.new
    heckler = scripted("HeckleSubjects", "guarded_answer", [:lit], reporter) { true }

    heckler.validate

    assert_equal ["def guarded_answer\n    47\n  end"], heckler.failures
    assert_equal [:failure, "def guarded_answer\n  42\nend", "def guarded_answer\n  47\nend"],
                 reporter.calls[-2]
  end

  def test_tests_run_against_installed_mutant
    seen = []
    heckler = scripted("HeckleSubjects", "pair", [:lit]) do
      seen << HeckleSubjects.new.pair
      false
    end

    heckler.validate
    assert_equal [[6, 2], [1, 7]], seen
    assert_equal [1, 2], HeckleSubjects.new.pair
  end

  def test_timeout_is_reported_and_loop_continues
    reporter = RecordingReporter.new
    heckler = scripted("HeckleSubjects", "pair", [:lit], reporter) do |h|
      sleep 5 if h.count == 1
      true
    end

    result = with_timeout(0.5) { heckler.validate }

    assert_equal false, result
    assert_equal ["def pair\n    [1, 7]\n  end"], heckler.failures
    assert_equal 2, heckler.count
    assert_includes reporter.calls,
                    [:warning, "Your tests timed out. Heckle may have caused an infinite loop."]
    assert_equal [1, 2], HeckleSubjects.new.pair
  end

  def test_syntax_error_is_reported_and_loop_continues
    reporter = RecordingReporter.new
    heckler = scripted("HeckleSubjects", "pair", [:lit], reporter) do |h|
      raise SyntaxError, "bad mutant" if h.count == 1
      false
    end

    assert_equal true, heckler.validate
    assert_equal 2, heckler.count
    assert_includes reporter.calls, [:warning, "Mutation caused a syntax error:\n\nbad mutant"]
  end

  def test_exception_in_tests_propagates_and_restores
    heckler = scripted("HeckleSubjects", "answer", [:lit]) { raise "test runner broke" }

    error = assert_raises(RuntimeError) { heckler.validate }
    assert_equal "test runner broke", error.message
    assert_equal 42, HeckleSubjects.new.answer
  end

  def test_script_error_in_tests_propagates_and_restores
    heckler = scripted("HeckleSubjects", "answer", [:lit]) { raise NotImplementedError }

    assert_raises(NotImplementedError) { heckler.validate }
    assert_equal 42, HeckleSubjects.new.answer
  end

  def test_validate_twice_gives_same_result
    reporter = RecordingReporter.new
    heckler = scripted("HeckleSubjects", "pair", [:lit], reporter) { |h| h.count == 2 }

    first = [heckler.validate, heckler.failures.dup, heckler.count, reporter.calls.dup]
    reporter.calls.clear
    second = [heckler.validate, heckler.failures.dup, heckler.count, reporter.calls.dup]

    assert_equal first, second
    assert_equal false, first[0]
    assert_equal ["def pair\n    [1, 7]\n  end"], first[1]
  end

  def test_real_reporter_output
    heckler = scripted("HeckleSubjects", "pair", [:lit], Heckle::Reporter.new) { |h| h.count == 1 }

    out, _err = capture_io { heckler.validate }

    assert_includes out, "***  HeckleSubjects#pair loaded with 2 possible mutations\n"
    assert_includes out, "2 mutations remaining...\n"
    assert_includes out, "1 mutations remaining...\n"
    assert_includes out, "The following mutations didn't cause test failures:\n"
    assert_includes out, "--- original\n+++ mutation\n"
    assert_includes out, "\n def pair\n-  [1, 2]\n+  [6, 2]\n end\n"
    assert out.end_with?(" end\n\n1 of 2 mutants survived\n\n"), out
  end

  def test_reporter_warning_and_info_text
    reporter = Heckle::Reporter.new

    assert_output("#{'!' * 70}\n!!! careful\n#{'!' * 70}\n\n") { reporter.warning "careful" }
    assert_output("#{'*' * 70}\n***  note\n#{'*' * 70}\n\n") { reporter.info "note" }
    assert_output("\nThe following mutations didn't cause test failures:\n\n") { reporter.no_failures }
  end

  def test_reporter_diff_has_no_hunk_header
    out, _err = capture_io { Heckle::Reporter.new.diff("a\nb\n", "a\nc\n") }

    assert_equal "--- original\n+++ mutation\n a\n-b\n+c\n\n", out
  end

  def test_reporter_replacing_text
    out, _err = capture_io { Heckle::Reporter.new.replacing("K", :m, "a\nb\n", "a\nc\n") }

    assert_equal "Replacing K#m with:\n\n--- original\n+++ mutation\n a\n-b\n+c\n\n", out
  end

  def test_reporter_test_failures_only_in_debug
    debug = Heckle.debug
    reporter = Heckle::Reporter.new

    Heckle.debug = false
    assert_output("") { reporter.report_test_failures }
    Heckle.debug = true
    assert_output("Tests failed -- this is good\n") { reporter.report_test_failures }
  ensure
    Heckle.debug = debug
  end

  def test_real_reporter_totals_without_survivors
    heckler = scripted("HeckleSubjects", "pair", [:lit], Heckle::Reporter.new) { false }

    out, _err = capture_io { heckler.validate }

    assert out.end_with?("No mutants survived. Cool!\n\n0 of 2 mutants survived\n\n"), out
  end

  def test_thick_skin_has_no_totals_line
    heckler = scripted("HeckleDummy", "uses_nothing", Heckle::MUTATABLE_NODES, Heckle::Reporter.new) { flunk "no run expected" }

    out, _err = capture_io { heckler.validate }

    refute_includes out, "mutants survived"
  end

  def test_totals_count_a_timed_out_mutant_as_killed
    reporter = RecordingReporter.new
    heckler = scripted("HeckleSubjects", "pair", [:lit], reporter) do |h|
      sleep 5 if h.count == 1
      true
    end

    with_timeout(0.5) { heckler.validate }

    assert_equal [:mutant_totals, 1, 2], reporter.calls.last
  end

  def test_real_reporter_thick_skin_names_the_class
    heckler = scripted("HeckleDummy", "uses_nothing", Heckle::MUTATABLE_NODES, Heckle::Reporter.new) { flunk "no run expected" }

    out, _err = capture_io { heckler.validate }

    assert_includes out, "!!! HeckleDummy#uses_nothing has a thick skin. There's nothing to heckle.\n"
  end

  def test_install_and_restore_are_silent_under_verbose
    verbose = $VERBOSE
    assert_silent do
      $VERBOSE = true
      heckler = heckle("HeckleSubjects", "pair", [:lit])
      first, second = heckler.mutations
      heckler.install(first)
      heckler.install(second)
      heckler.restore
      class_heckler = heckle("HeckleSubjects", "self.singleton_answer", [:lit])
      class_heckler.install(class_heckler.mutations.first)
      class_heckler.restore
    end
  ensure
    $VERBOSE = verbose
  end

  def test_mutatable_nodes
    assert_equal %i[call cvasgn false gasgn iasgn if iter lasgn lit str true until while],
                 Heckle::MUTATABLE_NODES
    assert_equal %i[if until while], Heckle::BRANCH_NODES
    assert_equal %i[cvasgn gasgn iasgn lasgn], Heckle::ASGN_NODES.sort
    assert_equal({ dasgn: :lasgn, dasgn_curr: :lasgn }, Heckle::NODE_ALIASES)
  end

  def test_public_surface
    %i[count klass klass_name method_name failures].each do |name|
      assert Heckle.public_method_defined?(name), "#{name} should be public"
    end
    %i[count= klass= klass_name= method_name=].each do |name|
      refute Heckle.method_defined?(name), "#{name} should not exist"
    end
    assert Heckle.public_method_defined?(:failures=)
    %i[run_tests record_passing_mutation].each do |name|
      assert Heckle.private_method_defined?(name), "#{name} should be private"
    end
  end

  def test_instance_method
    heckler = heckle("HeckleDummy", "uses_literal")

    assert_equal HeckleDummy, heckler.klass
    assert_equal "HeckleDummy", heckler.klass_name
    assert_equal :uses_literal, heckler.method_name
    assert_equal "def uses_literal\n    i = 1\n  end", heckler.original_source
    assert_equal [], heckler.failures
    assert_equal 0, heckler.count
  end

  def test_class_method
    heckler = heckle("HeckleDummy", "self.is_a_klass_method?")

    assert_equal :"self.is_a_klass_method?", heckler.method_name
    assert_equal "def self.is_a_klass_method?\n    true\n  end", heckler.original_source
  end

  def test_nested_class
    heckler = heckle("HeckleDummy::OuterNesting::InnerNesting::InnerClass", "foo")

    assert_equal HeckleDummy::OuterNesting::InnerNesting::InnerClass, heckler.klass
    assert_equal "def foo\n          1337\n        end", heckler.original_source
  end

  def test_twice_defined_method_resolves_to_live_definition
    heckler = heckle("HeckleDummy::OuterNesting::InnerNesting", "foo")

    assert_equal "def foo\n        -3\n      end", heckler.original_source
    assert_equal [DUMMY, 178],
                 HeckleDummy::OuterNesting::InnerNesting.instance_method(:foo).source_location.first(2)
  end

  def test_unknown_class
    error = assert_raises(Heckle::SourceNotFound) { heckle("HeckleDummy::Nope", "foo") }

    assert_equal "HeckleDummy::Nope#foo: no such class HeckleDummy::Nope", error.message
  end

  # Object's constants are reachable from any class by inheritance.
  def test_class_path_does_not_resolve_through_ancestors
    error = assert_raises(Heckle::SourceNotFound) { heckle("HeckleSubjects::HeckleDummy", "uses_literal") }

    assert_equal "HeckleSubjects::HeckleDummy#uses_literal: no such class HeckleSubjects::HeckleDummy",
                 error.message
  end

  def test_non_module_constant_is_not_a_class
    error = assert_raises(Heckle::SourceNotFound) { heckle("Heckle::VERSION", "foo") }

    assert_equal "Heckle::VERSION#foo: Heckle::VERSION is not a class or module", error.message
  end

  def test_unknown_method
    error = assert_raises(Heckle::SourceNotFound) { heckle("HeckleDummy", "nope") }

    assert_includes error.message, "HeckleDummy#nope"
    assert_includes error.message, "no such method"
  end

  def test_unknown_class_method
    error = assert_raises(Heckle::SourceNotFound) { heckle("HeckleDummy", "self.uses_literal") }

    assert_includes error.message, "HeckleDummy#self.uses_literal"
  end

  def test_define_method_has_no_usable_source
    error = assert_raises(Heckle::SourceNotFound) { heckle("HeckleSubjects", "defined_dynamically") }

    assert_includes error.message, "HeckleSubjects#defined_dynamically"
    assert_includes error.message, "no def"
  end

  def test_attr_accessor_has_no_usable_source
    error = assert_raises(Heckle::SourceNotFound) { heckle("HeckleDummy", "names") }

    assert_includes error.message, "HeckleDummy#names"
  end

  def test_c_method_has_no_source_location
    error = assert_raises(Heckle::SourceNotFound) { heckle("String", "upcase") }

    assert_includes error.message, "String#upcase"
    assert_includes error.message, "no source location"
  end

  def test_inherited_method_is_not_the_class_own
    error = assert_raises(Heckle::SourceNotFound) { heckle("HeckleSubjectsChild", "pair") }

    assert_equal "HeckleSubjectsChild#pair: no such method in HeckleSubjectsChild itself; " \
                 "it is defined by HeckleSubjects", error.message
  end

  def test_unreadable_source_file
    error = assert_raises(Heckle::SourceNotFound) { heckle("HeckleSubjectsEvaled", "gone") }

    assert_equal "HeckleSubjectsEvaled#gone: source file /nonexistent/heckle_gone.rb is not readable",
                 error.message
  end

  # Without the live def's line the finder would take the last def.
  def test_live_def_is_chosen_by_line
    assert_equal 42, HeckleSubjectsHalfLoaded.new.answer
    assert_equal "def answer\n    42\n  end", heckle("HeckleSubjectsHalfLoaded", "answer").original_source
  end

  def test_mutations_for_many_things
    heckler = heckle("HeckleDummy", "uses_many_things")
    source = File.read(DUMMY)
    triples = heckler.mutations.map do |mutation|
      text = source.byteslice(mutation.start_offset, mutation.end_offset - mutation.start_offset)
      [mutation.kind, text, mutation.replacement]
    end

    expected = [
      [:lasgn, "1", "nil"],
      [:lit, "1", "6"],
      [:while, "while", "until"],
      [:call, "i < 10", "nil"],
      [:lit, "10", "15"],
      [:lasgn, "1", "nil"],
      [:lit, "1", "6"],
      [:until, "until", "while"],
      [:call, "some_func", "nil"],
      [:call, "some_other_func", "nil"],
      [:true, "true", "false"],
      [:if, "if", "unless"],
      [:call, "\"hi there\" == \"changeling\"", "nil"],
      [:str, "\"hi there\"", "\"l33t h4x0r\""],
      [:str, "\"changeling\"", "\"l33t h4x0r\""],
      [:false, "false", "true"],
    ]
    assert_equal expected, triples
  end

  def test_mutations_filtered_by_if
    assert_equal [:if], heckle("HeckleDummy", "uses_many_things", [:if]).mutations.map(&:kind)
  end

  def test_mutations_filtered_by_branch_nodes
    kinds = heckle("HeckleDummy", "uses_many_things", Heckle::BRANCH_NODES).mutations.map(&:kind)

    assert_equal %i[while until if], kinds
  end

  def test_mutations_filtered_by_asgn_nodes
    kinds = heckle("HeckleDummy", "uses_many_things", Heckle::ASGN_NODES).mutations.map(&:kind)

    assert_equal %i[lasgn lasgn], kinds
  end

  def test_dasgn_aliases_select_local_assignments
    [[:dasgn], [:dasgn_curr]].each do |nodes|
      kinds = heckle("HeckleDummy", "uses_many_things", nodes).mutations.map(&:kind)

      assert_equal %i[lasgn lasgn], kinds, nodes.inspect
    end
  end

  def test_unknown_kind
    error = assert_raises(ArgumentError) { heckle("HeckleDummy", "uses_many_things", [:if, :bogus]) }

    assert_includes error.message, "bogus"
  end

  # The mutant that does not parse comes from `{foo:}`, Ruby 3.1 syntax.
  if RUBY_VERSION >= "3.1"
    def test_unparsable_mutants_are_dropped
      shorthand = File.expand_path("fixtures/heckle_shorthand.rb", __dir__)
      def_node = Heckle::MethodFinder.new(File.read(shorthand)).find("HeckleShorthand", "label_shorthand").def_node
      raw = Heckle::Mutator.new(TestHeckler.allocate).mutations_for(def_node)

      assert_equal [:lit], raw.map(&:kind)
      assert_empty heckle("HeckleShorthand", "label_shorthand", [:lit]).mutations
    end
  end

  def test_random_helpers
    heckler = Heckle.new("HeckleDummy", "uses_literal")

    50.times do
      number = heckler.rand_number
      assert_includes 1..100, number.abs

      string = heckler.rand_string
      assert_operator string.size, :<, 50
      assert(string.each_char.all? { |char| (32..126).cover?(char.ord) })

      symbol = heckler.rand_symbol
      assert_match(/\A[a-zA-Z]{1,50}\z/, symbol.to_s)

      range = heckler.rand_range
      assert_includes 0...50, range.begin
      assert_operator range.end, :>=, range.begin
    end
  end

  # Bounds reached in 1000 draws with probability above 1 - 1e-90.
  def test_rand_range_and_symbol_cover_their_spans
    heckler = Heckle.new("HeckleDummy", "uses_literal")
    ranges = Array.new(1000) { heckler.rand_range }
    symbols = Array.new(1000) { heckler.rand_symbol.to_s }

    assert_includes 40..49, ranges.map(&:begin).max
    assert_includes 40..49, ranges.map { |range| range.end - range.begin }.max
    assert_includes 41..50, symbols.map(&:size).max
    assert_equal [*"a".."z", *"A".."Z"].sort, symbols.join.chars.uniq.sort
  end

  def test_rand_string_is_printable_ascii
    heckler = Heckle.new("HeckleDummy", "uses_literal")
    strings = Array.new(1000) { heckler.rand_string }

    strings.each { |string| assert_match(/\A[ -~]{0,49}\z/, string) }
    assert_includes 40..49, strings.map(&:size).max
  end

  def test_drawn_strings_make_valid_string_and_regex_mutants
    heckler = Heckle.new("HeckleDummy", "uses_literal")
    source = "def m\n  [\"x\", /y/]\nend\n"
    def_node = Prism.parse(source).value.statements.body.first
    drawn = []
    randomizer = Object.new
    randomizer.define_singleton_method(:rand_string) { (drawn << heckler.rand_string).last }

    200.times do
      drawn.clear
      string_mutant, regex_mutant = Heckle::Mutator.new(randomizer).mutations_for(def_node)
                                                                    .map { |mutation| mutation.apply(source) }

      [string_mutant, regex_mutant].each { |mutant| assert Prism.parse(mutant).success?, mutant }
      assert_equal drawn[0], call_inline(string_mutant)[0]
      assert_equal drawn[1], call_inline(regex_mutant)[1].match(drawn[1])[0]
    end
  end

  def call_inline(mutant)
    holder = Object.new
    holder.instance_eval(mutant)
    holder.m
  end

  def test_nothing_to_mutate
    assert_empty heckle("HeckleDummy", "uses_nothing").mutations
  end

  def test_mutant_source_changes_one_site
    heckler = heckle("HeckleDummy", "uses_same_literal", [:lit])
    mutants = heckler.mutations.map { |mutation| heckler.mutant_source(mutation) }

    assert_equal [
      "def uses_same_literal\n    i = 6\n    i = 1\n    i = 1\n  end",
      "def uses_same_literal\n    i = 1\n    i = 6\n    i = 1\n  end",
      "def uses_same_literal\n    i = 1\n    i = 1\n    i = 6\n  end",
    ], mutants
    assert_equal "def uses_same_literal\n    i = 1\n    i = 1\n    i = 1\n  end", heckler.original_source
  end

  # Fork mode. Scripts run in the forked child, so they report back through
  # a pipe the child inherits. Every child is reaped, which leaves
  # Process.waitpid with nothing to wait for.

  # Records the pid of each forked child.
  class ForkRecordingHeckler < ScriptedHeckler
    def pids
      @pids ||= []
    end

    private

    def fork_child(mutation)
      super.tap { |pid| pids << pid }
    end
  end

  # The usual ^C pause is recorded instead of taken. The parent's end of
  # the pipe is closed once the first child has it, so a child that dies
  # before writing gives end of file rather than a reader that waits.
  class NoPauseHeckler < ForkRecordingHeckler
    attr_accessor :writer

    def sleeps
      @sleeps ||= []
    end

    def sleep(*args)
      sleeps << args
    end

    private

    def fork_child(mutation)
      super.tap { writer.close if count == 1 }
    end
  end

  # Records the signals sent to children.
  class SignalRecordingHeckler < ForkRecordingHeckler
    def signals
      @signals ||= []
    end

    private

    def signal_child(signal, pid, waiter)
      signals << signal
      super
    end
  end

  # install raises something other than a SyntaxError.
  class RaisingInstallHeckler < ForkRecordingHeckler
    private

    def install_source(_mutation)
      ["raise ArgumentError, 'no such constant'\n", 1]
    end
  end

  # install raises a SyntaxError for every mutant.
  class BadInstallHeckler < ForkRecordingHeckler
    private

    def install_source(_mutation)
      ["class HeckleSubjects; def pair\n  [1, 2]\nend end\nend\n", 12]
    end
  end

  def with_fork(value = true)
    saved = Heckle.fork?
    Heckle.fork = value
    yield
  ensure
    Heckle.fork = saved
  end

  def forked(klass_name, method_name, nodes, reporter = RecordingReporter.new,
             heckler_class: ForkRecordingHeckler, &script)
    heckler = heckler_class.new(klass_name, method_name, nodes, reporter)
    heckler.script = script
    (@hecklers ||= []) << heckler
    heckler
  end

  def assert_reaped(pids)
    refute_empty pids
    pids.each do |pid|
      assert_raises(Errno::ECHILD, "child #{pid} not reaped") { Process.waitpid(pid, Process::WNOHANG) }
    end
  end

  # What the child wrote into the pipe, once every child has exited.
  def drain(reader, writer)
    writer.close
    reader.read
  ensure
    reader.close
  end

  def test_fork_setting_is_off_by_default
    lib = File.expand_path("../lib", __dir__)
    out, err, status = Open3.capture3(RbConfig.ruby, "-I", lib, "-e", 'require "heckle"; p Heckle.fork?')

    assert status.success?, err
    assert_equal "false\n", out
  end

  def test_fork_reports_like_in_process
    script = ->(h) { h.count == 1 }
    in_process_reporter = RecordingReporter.new
    in_process = scripted("HeckleSubjects", "pair", [:lit], in_process_reporter, &script)
    in_process_result = in_process.validate

    reporter = RecordingReporter.new
    heckler = forked("HeckleSubjects", "pair", [:lit], reporter, &script)
    result = with_fork { heckler.validate }

    assert_equal false, result
    assert_equal in_process_result, result
    assert_equal in_process_reporter.calls, reporter.calls
    assert_equal ["def pair\n    [6, 2]\n  end"], heckler.failures
    assert_equal 2, heckler.count
    assert_reaped heckler.pids
  end

  def test_fork_all_killed_like_in_process
    in_process_reporter = RecordingReporter.new
    scripted("HeckleSubjects", "pair", [:lit], in_process_reporter) { false }.validate
    reporter = RecordingReporter.new
    heckler = forked("HeckleSubjects", "pair", [:lit], reporter) { false }

    assert_equal true, with_fork { heckler.validate }
    assert_equal in_process_reporter.calls, reporter.calls
  end

  def test_fork_thick_skin_forks_nothing
    reporter = RecordingReporter.new
    heckler = forked("HeckleDummy", "uses_nothing", Heckle::MUTATABLE_NODES, reporter) { flunk }

    assert_nil with_fork { heckler.validate }
    assert_equal [[:no_mutations, "HeckleDummy", :uses_nothing]], reporter.calls
    assert_empty heckler.pids
  end

  def test_fork_child_runs_the_mutant_and_the_parent_never_does
    original = HeckleSubjects.instance_method(:pair)
    reader, writer = IO.pipe
    heckler = forked("HeckleSubjects", "pair", [:lit]) do
      writer.puts HeckleSubjects.new.pair.inspect
      false
    end

    with_fork { heckler.validate }

    assert_equal "[6, 2]\n[1, 7]\n", drain(reader, writer)
    assert_equal original, HeckleSubjects.instance_method(:pair)
    assert_equal [1, 2], HeckleSubjects.new.pair
    assert_reaped heckler.pids
  end

  def test_fork_child_skips_at_exit_handlers
    reader, writer = IO.pipe
    heckler = forked("HeckleSubjects", "answer", [:lit]) do
      at_exit { writer.puts "at_exit ran" }
      writer.puts "judged"
      true
    end

    with_fork { heckler.validate }

    assert_equal "judged\n", drain(reader, writer)
  end

  def test_fork_install_syntax_error_is_reported_as_in_process
    in_process_reporter = RecordingReporter.new
    in_process = BadInstallHeckler.new("HeckleSubjects", "pair", [:lit], in_process_reporter)
    in_process.script = ->(_h) { flunk "no test run expected" }
    (@hecklers ||= []) << in_process
    in_process.validate

    reporter = RecordingReporter.new
    heckler = forked("HeckleSubjects", "pair", [:lit], reporter, heckler_class: BadInstallHeckler) { true }

    assert_equal true, with_fork { heckler.validate }
    assert_equal in_process_reporter.calls, reporter.calls
    warning = reporter.calls.find { |call| call.first == :warning }
    assert_match(/\AMutation caused a syntax error:\n\n.*heckle_subjects\.rb:\d+: syntax error/, warning[1])
    assert_empty heckler.failures
    assert_reaped heckler.pids
  end

  def test_fork_install_raising_another_error_is_not_a_survivor
    reporter = RecordingReporter.new
    heckler = forked("HeckleSubjects", "answer", [:lit], reporter, heckler_class: RaisingInstallHeckler) { true }

    assert_equal true, with_fork { heckler.validate }
    assert_includes reporter.calls,
                    [:warning, "Installing the mutant raised an exception in the forked child. Not counted as a survivor."]
    assert_empty heckler.failures
    assert_reaped heckler.pids
  end

  def test_fork_tests_raising_is_not_a_survivor
    original = HeckleSubjects.instance_method(:answer)
    reporter = RecordingReporter.new
    heckler = forked("HeckleSubjects", "answer", [:lit], reporter) { raise "test runner broke" }

    assert_equal true, with_fork { heckler.validate }
    assert_includes reporter.calls, [:warning, "The tests raised an exception in the forked child. Not counted as a survivor."]
    assert_equal [:mutant_totals, 0, 1], reporter.calls.last
    assert_equal original, HeckleSubjects.instance_method(:answer)
    assert_reaped heckler.pids
  end

  def test_fork_unexpected_exit_status_is_not_a_survivor
    reporter = RecordingReporter.new
    heckler = forked("HeckleSubjects", "answer", [:lit], reporter) { exit!(0) }

    assert_equal true, with_fork { heckler.validate }
    assert_includes reporter.calls,
                    [:warning, "The forked test run ended with exit status 0. Not counted as a survivor."]
    assert_empty heckler.failures
  end

  def test_fork_child_crash_is_not_a_survivor
    original = HeckleSubjects.instance_method(:pair)
    reader, writer = IO.pipe
    reporter = RecordingReporter.new
    heckler = forked("HeckleSubjects", "pair", [:lit], reporter) do |h|
      writer.puts HeckleSubjects.new.pair.inspect
      Process.kill(:KILL, Process.pid) if h.count == 1
      true
    end

    assert_equal false, with_fork { heckler.validate }

    assert_equal "[6, 2]\n[1, 7]\n", drain(reader, writer)
    assert_includes reporter.calls,
                    [:warning, "The forked test run was killed by signal KILL. Not counted as a survivor."]
    assert_equal ["def pair\n    [1, 7]\n  end"], heckler.failures
    assert_equal [:mutant_totals, 1, 2], reporter.calls.last
    assert_equal original, HeckleSubjects.instance_method(:pair)
    assert_equal [1, 2], HeckleSubjects.new.pair
    assert_reaped heckler.pids
  end

  # The first child never finishes; the deadline ends it. TERM is enough,
  # so it is not sent KILL.
  def test_fork_timeout_kills_the_child
    original = HeckleSubjects.instance_method(:pair)
    reporter = RecordingReporter.new
    heckler = forked("HeckleSubjects", "pair", [:lit], reporter, heckler_class: SignalRecordingHeckler) do |h|
      sleep if h.count == 1
      true
    end

    result = with_timeout(0.5) { with_fork { heckler.validate } }

    assert_equal false, result
    assert_equal %i[TERM], heckler.signals
    assert_includes reporter.calls,
                    [:warning, "Your tests timed out. Heckle may have caused an infinite loop."]
    assert_equal ["def pair\n    [1, 7]\n  end"], heckler.failures
    assert_equal [:mutant_totals, 1, 2], reporter.calls.last
    assert_equal original, HeckleSubjects.instance_method(:pair)
    assert_reaped heckler.pids
  end

  # Signals the child only once it reports it has trapped TERM, and
  # records the signals sent.
  # The parent's end of the pipe is closed first, so a child that died
  # before writing gives end of file rather than a reader that waits.
  class TermIgnoredHeckler < SignalRecordingHeckler
    attr_accessor :ready, :writer

    private

    def fork_grace
      0.1
    end

    def stop_child(pid, waiter)
      writer.close
      ready.gets
      super
    end
  end

  def test_fork_timeout_kills_a_child_that_ignores_term
    reader, writer = IO.pipe
    reporter = RecordingReporter.new
    heckler = forked("HeckleSubjects", "answer", [:lit], reporter, heckler_class: TermIgnoredHeckler) do
      trap("TERM") {}
      writer.puts "trapped"
      sleep
    end
    heckler.ready = reader
    heckler.writer = writer

    with_timeout(0.2) { with_fork { heckler.validate } }

    assert_equal %i[TERM KILL], heckler.signals
    assert_includes reporter.calls,
                    [:warning, "Your tests timed out. Heckle may have caused an infinite loop."]
    assert_reaped heckler.pids
  ensure
    reader&.close
    writer&.close
  end

  # ^C in the parent while the child is running its tests.
  def test_fork_interrupt_kills_the_child
    original = HeckleSubjects.instance_method(:pair)
    reader, writer = IO.pipe
    reporter = RecordingReporter.new
    heckler = forked("HeckleSubjects", "pair", [:lit], reporter, heckler_class: NoPauseHeckler) do |h|
      if h.count == 1
        writer.puts "running"
        sleep
      end
      false
    end
    heckler.writer = writer
    main = Thread.current
    interrupter = Thread.new do
      main.raise(Interrupt) if reader.gets
    end

    result = with_fork { heckler.validate }
    interrupter.join

    assert_equal true, result
    assert_includes reporter.calls, [:warning, "Mutation canceled, hit ^C again to exit"]
    assert_equal [[2]], heckler.sleeps
    assert_equal [:mutant_totals, 0, 2], reporter.calls.last
    assert_equal original, HeckleSubjects.instance_method(:pair)
    assert_reaped heckler.pids
  ensure
    reader&.close
    writer&.close
  end
end
