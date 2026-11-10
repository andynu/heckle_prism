require "minitest/autorun"
require "fixtures/heckle_dummy"
require "fixtures/heckle_subjects"
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

class TestHeckle < Minitest::Test
  DUMMY = File.expand_path("fixtures/heckle_dummy.rb", __dir__)
  SUBJECTS = File.expand_path("fixtures/heckle_subjects.rb", __dir__)

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
