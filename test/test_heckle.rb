require "minitest/autorun"
require "fixtures/heckle_dummy"
require "fixtures/heckle_subjects"
require "fixtures/heckle_frozen"
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
     failure no_surviving_mutants replacing report_test_failures].each do |name|
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

  def teardown
    (@hecklers || []).each(&:restore)
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

  def test_restore_keeps_original_source_location
    location = HeckleSubjects.instance_method(:answer).source_location
    heckler = install_only("HeckleSubjects", "answer", [:lit])
    heckler.restore

    assert_equal [SUBJECTS, 8], location.first(2)
    assert_equal location, HeckleSubjects.instance_method(:answer).source_location
  end

  def test_mutant_backtrace_points_at_original_file_and_line
    install_only("HeckleSubjects", "explode", [:str])

    error = assert_raises(ArgumentError) { HeckleSubjects.new.explode }
    assert_equal "l33t h4x0r", error.message
    frame = error.backtrace_locations.first
    assert_equal [SUBJECTS, 28], [frame.path, frame.lineno]
    assert_equal "raise ArgumentError, \"kaboom\"", File.readlines(SUBJECTS)[27].strip
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
    assert_equal [:no_failures, :failure], reporter.names.last(2)
    assert_equal [:failure, "def pair\n  [1, 2]\nend", "def pair\n  [6, 2]\nend"], reporter.calls.last
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
    assert_equal [:failure, LETTER_SHOWN % "if", LETTER_SHOWN % "unless"], reporter.calls.last
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
                 reporter.calls.last
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

    result = with_timeout(0.05) { heckler.validate }

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

    assert_includes error.message, "HeckleDummy::Nope#foo"
    assert_includes error.message, "no such class"
  end

  def test_non_module_constant_is_not_a_class
    error = assert_raises(Heckle::SourceNotFound) { heckle("Heckle::VERSION", "foo") }

    assert_includes error.message, "Heckle::VERSION#foo"
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
    error = assert_raises(Heckle::SourceNotFound) { heckle("HeckleSubjectsChild", "label_shorthand") }

    assert_includes error.message, "HeckleSubjectsChild#label_shorthand"
    assert_includes error.message, "HeckleSubjects"
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

  def test_unparsable_mutants_are_dropped
    def_node = Heckle::MethodFinder.new(File.read(SUBJECTS)).find("HeckleSubjects", "label_shorthand").def_node
    raw = Heckle::Mutator.new(TestHeckler.allocate).mutations_for(def_node)

    assert_equal [:lit], raw.map(&:kind)
    assert_empty heckle("HeckleSubjects", "label_shorthand", [:lit]).mutations
  end

  def test_random_helpers
    heckler = Heckle.new("HeckleDummy", "uses_literal")

    50.times do
      number = heckler.rand_number
      assert_includes 1..100, number.abs

      string = heckler.rand_string
      assert_operator string.size, :<, 50
      assert(string.each_char.all? { |char| char.ord < 126 })

      symbol = heckler.rand_symbol
      assert_match(/\A[a-zA-Z]{1,50}\z/, symbol.to_s)

      range = heckler.rand_range
      assert_includes 0...50, range.begin
      assert_operator range.end, :>=, range.begin
    end
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
end
