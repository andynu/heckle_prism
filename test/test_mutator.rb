require "minitest/autorun"
require "heckle/method_finder"
require "heckle/mutator"

class TestMutator < Minitest::Test
  FIXTURE = File.expand_path("fixtures/heckle_dummy.rb", __dir__)

  Randomizer = Struct.new(:rand_number, :rand_string, :rand_symbol, :rand_range)

  STUB = Randomizer.new(5, "l33t h4x0r", :"l33t h4x0r", 5..10)

  def fixture_source
    @fixture_source ||= File.read(FIXTURE)
  end

  # Mutated sources of HeckleDummy#method_name, in mutation order. Lines after
  # the first lose the def's indentation, so expectations read as flush-left.
  def fixture_mutants(method_name, kinds, randomizer = STUB)
    def_node = Heckle::MethodFinder.new(fixture_source).find("HeckleDummy", method_name).def_node
    mutants_of(def_node, kinds, randomizer)
  end

  # Mutated sources of the first def in source.
  def inline_mutants(source, kinds, randomizer = STUB)
    def_node = Prism.parse(source).value.statements.body.first
    mutants_of(def_node, kinds, randomizer)
  end

  def mutants_of(def_node, kinds, randomizer)
    indent = def_node.location.start_column
    mutations = Heckle::Mutator.new(randomizer).mutations_for(def_node)
    mutations = mutations.select { |mutation| Array(kinds).include?(mutation.kind) }
    mutations.map do |mutation|
      text = mutation.apply(def_node.slice, def_node.location.start_offset)
      "#{text.gsub(/\n {#{indent}}/, "\n")}\n"
    end
  end

  def assert_mutants(expected, actual)
    assert_equal expected, actual
    actual.each do |mutant|
      assert Prism.parse(mutant).success?, "mutant does not parse:\n#{mutant}"
    end
  end

  # Defines the mutant on a fresh object and returns the result of calling it.
  def call_mutant(mutant, name, *args)
    object = Object.new
    object.instance_eval(mutant)
    object.public_send(name, *args)
  end

  def test_true_and_false
    expected = [
      <<~RUBY,
        def uses_boolean
          a = false
          b = false
        end
      RUBY
      <<~RUBY,
        def uses_boolean
          a = true
          b = true
        end
      RUBY
    ]

    assert_mutants expected, fixture_mutants("uses_boolean", [:true, :false])
  end

  def test_true_and_false_are_separate_kinds
    assert_equal 1, fixture_mutants("uses_boolean", :true).size
    assert_equal 1, fixture_mutants("uses_boolean", :false).size
  end

  def test_class_method_boolean
    expected = [
      <<~RUBY,
        def self.is_a_klass_method?
          false
        end
      RUBY
    ]

    assert_mutants expected, fixture_mutants("self.is_a_klass_method?", [:true, :false])
  end

  def test_numeric_literals
    expected = [
      <<~RUBY,
        def uses_numeric_literals
          i = 6
          i += 2147483648
          i -= 3.5
        end
      RUBY
      <<~RUBY,
        def uses_numeric_literals
          i = 1
          i += 2147483653
          i -= 3.5
        end
      RUBY
      <<~RUBY,
        def uses_numeric_literals
          i = 1
          i += 2147483648
          i -= 8.5
        end
      RUBY
    ]

    assert_mutants expected, fixture_mutants("uses_numeric_literals", :lit)
  end

  def test_same_literal_mutates_each_site
    expected = [
      <<~RUBY,
        def uses_same_literal
          i = 6
          i = 1
          i = 1
        end
      RUBY
      <<~RUBY,
        def uses_same_literal
          i = 1
          i = 6
          i = 1
        end
      RUBY
      <<~RUBY,
        def uses_same_literal
          i = 1
          i = 1
          i = 6
        end
      RUBY
    ]

    assert_mutants expected, fixture_mutants("uses_same_literal", :lit)
  end

  def test_single_literal
    expected = [
      <<~RUBY,
        def uses_literal
          i = 6
        end
      RUBY
    ]

    assert_mutants expected, fixture_mutants("uses_literal", :lit)
  end

  def test_negative_literal
    mutants = inline_mutants("def m\n  -1\nend\n", :lit)

    assert_mutants ["def m\n  4\nend\n"], mutants
    assert_equal 4, call_mutant(mutants.first, :m)
  end

  def test_literal_as_right_operand_of_binary_minus
    mutants = inline_mutants("def m(x)\n  x-1\nend\n", :lit)

    assert_mutants ["def m(x)\n  x-6\nend\n"], mutants
    assert_equal 4, call_mutant(mutants.first, :m, 10)
  end

  def test_negative_result_is_parenthesized
    randomizer = Randomizer.new(-10, "l33t h4x0r", :"l33t h4x0r", 5..10)
    mutants = inline_mutants("def m(x)\n  x-1 + 2 ** 2\nend\n", :lit, randomizer)

    assert_mutants ["def m(x)\n  x-(-9) + 2 ** 2\nend\n",
                    "def m(x)\n  x-1 + (-8) ** 2\nend\n",
                    "def m(x)\n  x-1 + 2 ** (-8)\nend\n"], mutants
    assert_equal [17, 67, 3 + 2r**-8], mutants.map { |mutant| call_mutant(mutant, :m, 4) }
  end

  def test_float_literal
    mutants = inline_mutants("def m\n  1.25\nend\n", :lit)

    assert_mutants ["def m\n  6.25\nend\n"], mutants
  end

  def test_rationals_and_imaginaries_are_not_mutated
    assert_empty inline_mutants("def m\n  [2r, 3i, 1.5r]\nend\n", :lit)
  end

  def test_mutations_are_sorted_by_start_then_widest_first
    def_node = Prism.parse("def m\n  [true, false, true]\nend\n").value.statements.body.first
    mutations = Heckle::Mutator.new(STUB).mutations_for(def_node)

    assert_equal mutations.sort_by { |m| [m.start_offset, -m.end_offset] }, mutations
    assert_equal %i[true false true], mutations.map(&:kind)
  end
end
