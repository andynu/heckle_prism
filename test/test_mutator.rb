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

  HOSTILE = "#{(0..125).map(&:chr).join}\#{\""

  def test_strings
    expected = [
      <<~RUBY,
        def uses_strings
          @names << "l33t h4x0r"
          @names << "Hello, Jeff"
          @names << "Hi, Frank"
        end
      RUBY
      <<~RUBY,
        def uses_strings
          @names << "Hello, Robert"
          @names << "l33t h4x0r"
          @names << "Hi, Frank"
        end
      RUBY
      <<~RUBY,
        def uses_strings
          @names << "Hello, Robert"
          @names << "Hello, Jeff"
          @names << "l33t h4x0r"
        end
      RUBY
    ]

    assert_mutants expected, fixture_mutants("uses_strings", :str)
  end

  def test_other_string_literal_forms
    source = "def m\n  ['y', %q(x), ?a]\nend\n"

    assert_mutants ["def m\n  [\"l33t h4x0r\", %q(x), ?a]\nend\n",
                    "def m\n  ['y', \"l33t h4x0r\", ?a]\nend\n",
                    "def m\n  ['y', %q(x), \"l33t h4x0r\"]\nend\n"],
                   inline_mutants(source, :str)
  end

  def test_adjacent_literals_mutate_separately
    source = "def m\n  \"a\" \"b\"\nend\n"

    assert_mutants ["def m\n  \"l33t h4x0r\" \"b\"\nend\n",
                    "def m\n  \"a\" \"l33t h4x0r\"\nend\n"],
                   inline_mutants(source, :str)
  end

  def test_interpolated_string_parts_are_not_mutated
    assert_empty inline_mutants("def m(t)\n  \"s\#{t}u\"\nend\n", :str)
  end

  def test_word_array_elements_are_not_mutated
    assert_empty inline_mutants("def m\n  %w[p q]\nend\n", :str)
  end

  def test_heredocs_are_not_mutated
    source = <<~'SOURCE'
      def m(t)
        [<<A, <<-B, <<~C, <<~D, <<~'E']
      plain
      A
        dash
        B
        squiggly
        C
        interpolated #{t}
        D
        quoted #{t}
        E
      end
    SOURCE

    assert Prism.parse(source).success?
    assert_empty inline_mutants(source, :str)
  end

  def test_backtick_strings_are_not_mutated
    assert_empty inline_mutants("def m\n  `ls`\nend\n", :str)
  end

  def test_hostile_random_string_is_quoted_safely
    randomizer = Randomizer.new(5, HOSTILE, :"l33t h4x0r", 5..10)
    mutants = inline_mutants("def m\n  \"x\"\nend\n", :str, randomizer)

    assert_equal 1, mutants.size
    assert Prism.parse(mutants.first).success?
    assert_equal HOSTILE, call_mutant(mutants.first, :m)
  end

  def test_symbols
    expected = [
      <<~RUBY,
        def uses_symbols
          i = :"l33t h4x0r"
          i = :blah
          i = :and_blah
        end
      RUBY
      <<~RUBY,
        def uses_symbols
          i = :blah
          i = :"l33t h4x0r"
          i = :and_blah
        end
      RUBY
      <<~RUBY,
        def uses_symbols
          i = :blah
          i = :blah
          i = :"l33t h4x0r"
        end
      RUBY
    ]

    assert_mutants expected, fixture_mutants("uses_symbols", :lit)
  end

  def test_quoted_symbols
    source = "def m\n  [:\"quoted\", %s(x)]\nend\n"

    assert_mutants ["def m\n  [:\"l33t h4x0r\", %s(x)]\nend\n",
                    "def m\n  [:\"quoted\", :\"l33t h4x0r\"]\nend\n"],
                   inline_mutants(source, :lit)
  end

  def test_label_keys_stay_labels
    source = "def m\n  [{ foo: 2 }, { \"foo\": 3 }]\nend\n"
    mutants = inline_mutants(source, :lit)

    assert_mutants ["def m\n  [{ \"l33t h4x0r\": 2 }, { \"foo\": 3 }]\nend\n",
                    "def m\n  [{ foo: 7 }, { \"foo\": 3 }]\nend\n",
                    "def m\n  [{ foo: 2 }, { \"l33t h4x0r\": 3 }]\nend\n",
                    "def m\n  [{ foo: 2 }, { \"foo\": 8 }]\nend\n"],
                   mutants
    assert_equal [{ "l33t h4x0r": 2 }, { foo: 3 }], call_mutant(mutants.first, :m)
  end

  def test_symbol_array_elements_are_not_mutated
    assert_empty inline_mutants("def m\n  %i[a b]\nend\n", :lit)
  end

  def test_alias_and_undef_are_not_mutated
    source = "def m\n  alias foo bar\n  alias :baz :qux\n  undef foo, :baz\nend\n"

    assert_empty inline_mutants(source, :lit)
  end

  def test_mutations_are_sorted_by_start_then_widest_first
    def_node = Prism.parse("def m\n  [true, false, true]\nend\n").value.statements.body.first
    mutations = Heckle::Mutator.new(STUB).mutations_for(def_node)

    assert_equal mutations.sort_by { |m| [m.start_offset, -m.end_offset] }, mutations
    assert_equal %i[true false true], mutations.map(&:kind)
  end
end
