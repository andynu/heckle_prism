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

  def test_regexes
    expected = [
      <<~'RUBY',
        def uses_regexes
          i = /l33t\ h4x0r/
          i = /c{2,4}+/
          i = /123/
        end
      RUBY
      <<~'RUBY',
        def uses_regexes
          i = /a.*/
          i = /l33t\ h4x0r/
          i = /123/
        end
      RUBY
      <<~'RUBY',
        def uses_regexes
          i = /a.*/
          i = /c{2,4}+/
          i = /l33t\ h4x0r/
        end
      RUBY
    ]

    assert_mutants expected, fixture_mutants("uses_regexes", :lit)
  end

  def test_hostile_random_string_regex_matches_literally
    randomizer = Randomizer.new(5, HOSTILE, :"l33t h4x0r", 5..10)
    mutants = inline_mutants("def m\n  /x/\nend\n", :lit, randomizer)

    assert_equal 1, mutants.size
    assert Prism.parse(mutants.first).success?
    assert_equal HOSTILE, call_mutant(mutants.first, :m).match(HOSTILE)[0]
  end

  def test_regex_flags_are_kept
    source = "def m\n  [/ab/im, %r{c}x]\nend\n"
    mutants = inline_mutants(source, :lit)

    assert_mutants ["def m\n  [/l33t\\ h4x0r/im, %r{c}x]\nend\n",
                    "def m\n  [/ab/im, /l33t\\ h4x0r/x]\nend\n"],
                   mutants
    assert_equal Regexp::IGNORECASE | Regexp::MULTILINE, call_mutant(mutants.first, :m).first.options
  end

  def test_interpolated_regex_is_not_mutated
    assert_empty inline_mutants("def m(b)\n  /a\#{b}c/\nend\n", [:lit, :str])
  end

  def test_ranges
    expected = [
      <<~RUBY,
        def uses_ranges
          i = 5..10
          i = -1..9
          i = 1..4
        end
      RUBY
      <<~RUBY,
        def uses_ranges
          i = 6..100
          i = 5..10
          i = 1..4
        end
      RUBY
      <<~RUBY,
        def uses_ranges
          i = 6..100
          i = -1..9
          i = 5..10
        end
      RUBY
    ]

    assert_mutants expected, fixture_mutants("uses_ranges", :lit)
  end

  def test_range_with_negative_end_is_one_mutation
    assert_mutants ["def m\n  5..10\nend\n"],
                   inline_mutants("def m\n  -1..9\nend\n", :lit)
  end

  def test_exclusive_range_becomes_inclusive_random_range
    mutants = inline_mutants("def m\n  (1...4).to_a\nend\n", :lit)

    assert_mutants ["def m\n  (5..10).to_a\nend\n"], mutants
    assert_equal (5..10).to_a, call_mutant(mutants.first, :m)
  end

  def test_range_with_non_literal_end_mutates_only_the_literal
    assert_mutants ["def m(a)\n  a..15\nend\n"],
                   inline_mutants("def m(a)\n  a..10\nend\n", :lit)
  end

  def test_while
    expected = [
      <<~RUBY,
        def uses_while
          until some_func
            some_other_func
          end
        end
      RUBY
    ]

    assert_mutants expected, fixture_mutants("uses_while", :while)
  end

  def test_until
    expected = [
      <<~RUBY,
        def uses_until
          while some_func
            some_other_func
          end
        end
      RUBY
    ]

    assert_mutants expected, fixture_mutants("uses_until", :until)
  end

  def test_modifier_loops
    assert_mutants ["def m\n  x until y\nend\n"], inline_mutants("def m\n  x while y\nend\n", :while)
    assert_mutants ["def m\n  x while y\nend\n"], inline_mutants("def m\n  x until y\nend\n", :until)
  end

  def test_begin_end_while_keeps_running_the_body_first
    source = "def m\n  n = 0\n  begin\n    n += 1\n  end while n > 5\n  n\nend\n"
    mutants = inline_mutants(source, :while)

    assert_mutants ["def m\n  n = 0\n  begin\n    n += 1\n  end until n > 5\n  n\nend\n"], mutants
    assert_equal 6, call_mutant(mutants.first, :m)
  end

  def test_only_the_loop_keyword_changes
    source = <<~RUBY
      def m
        while ready? # while
          log "while"
        end
      end
    RUBY
    expected = <<~RUBY
      def m
        until ready? # while
          log "while"
        end
      end
    RUBY

    assert_mutants [expected], inline_mutants(source, [:while, :until])
  end

  # Asserts mutant returns what reference returns for every argument list.
  def assert_same_behavior(reference, mutant, name, arg_lists)
    expected = arg_lists.map { |args| call_mutant(reference, name, *args) }
    actual = arg_lists.map { |args| call_mutant(mutant, name, *args) }
    assert_equal expected, actual
  end

  TRUTHS = [[true], [false], [nil], [0]]
  TRUTH_PAIRS = [true, false].product([true, false])

  def test_if
    expected = [
      <<~RUBY,
        def uses_if
          unless some_func
            if some_other_func
              return
            end
          end
        end
      RUBY
      <<~RUBY,
        def uses_if
          if some_func
            unless some_other_func
              return
            end
          end
        end
      RUBY
    ]

    assert_mutants expected, fixture_mutants("uses_if", :if)
  end

  def test_unless
    expected = [
      <<~RUBY,
        def uses_unless
          if true
            if false
              return
            end
          end
        end
      RUBY
      <<~RUBY,
        def uses_unless
          unless true
            unless false
              return
            end
          end
        end
      RUBY
    ]

    assert_mutants expected, fixture_mutants("uses_unless", :if)
  end

  def test_modifier_if_in_many_things
    expected = [
      <<~RUBY,
        def uses_many_things
          i = 1
          while i < 10
            i += 1
            until some_func
              some_other_func
            end
            return true unless "hi there" == "changeling"
            return false
          end
          i
        end
      RUBY
    ]

    assert_mutants expected, fixture_mutants("uses_many_things", :if)
  end

  def test_block_if_with_else
    mutants = inline_mutants("def m(a)\n  if a\n    1\n  else\n    2\n  end\nend\n", :if)

    assert_mutants ["def m(a)\n  unless a\n    1\n  else\n    2\n  end\nend\n"], mutants
    assert_same_behavior "def m(a)\n  if a\n    2\n  else\n    1\n  end\nend\n", mutants.first, :m, TRUTHS
  end

  def test_block_if_without_else
    mutants = inline_mutants("def m(a)\n  if a\n    1\n  end\nend\n", :if)

    assert_mutants ["def m(a)\n  unless a\n    1\n  end\nend\n"], mutants
    assert_same_behavior "def m(a)\n  if a\n    nil\n  else\n    1\n  end\nend\n", mutants.first, :m, TRUTHS
  end

  def test_modifier_if
    mutants = inline_mutants("def m(a)\n  1 if a\nend\n", :if)

    assert_mutants ["def m(a)\n  1 unless a\nend\n"], mutants
    assert_same_behavior "def m(a)\n  a ? nil : 1\nend\n", mutants.first, :m, TRUTHS
  end

  def test_block_unless_with_else
    mutants = inline_mutants("def m(a)\n  unless a\n    1\n  else\n    2\n  end\nend\n", :if)

    assert_mutants ["def m(a)\n  if a\n    1\n  else\n    2\n  end\nend\n"], mutants
    assert_same_behavior "def m(a)\n  unless a\n    2\n  else\n    1\n  end\nend\n", mutants.first, :m, TRUTHS
  end

  def test_block_unless_without_else
    mutants = inline_mutants("def m(a)\n  unless a\n    1\n  end\nend\n", :if)

    assert_mutants ["def m(a)\n  if a\n    1\n  end\nend\n"], mutants
    assert_same_behavior "def m(a)\n  unless a\n    nil\n  else\n    1\n  end\nend\n", mutants.first, :m, TRUTHS
  end

  def test_modifier_unless
    mutants = inline_mutants("def m(a)\n  1 unless a\nend\n", :if)

    assert_mutants ["def m(a)\n  1 if a\nend\n"], mutants
    assert_same_behavior "def m(a)\n  a ? 1 : nil\nend\n", mutants.first, :m, TRUTHS
  end

  def test_elsif_chain_negates_each_predicate
    source = "def m(a, b)\n  if a\n    1\n  elsif b\n    2\n  else\n    3\n  end\nend\n"
    mutants = inline_mutants(source, :if)

    assert_mutants ["def m(a, b)\n  if !(a)\n    1\n  elsif b\n    2\n  else\n    3\n  end\nend\n",
                    "def m(a, b)\n  if a\n    1\n  elsif !(b)\n    2\n  else\n    3\n  end\nend\n"],
                   mutants
    assert_same_behavior "def m(a, b)\n  a ? (b ? 2 : 3) : 1\nend\n", mutants[0], :m, TRUTH_PAIRS
    assert_same_behavior "def m(a, b)\n  a ? 1 : (b ? 3 : 2)\nend\n", mutants[1], :m, TRUTH_PAIRS
  end

  def test_ternary
    mutants = inline_mutants("def m(a)\n  a ? 1 : 2\nend\n", :if)

    assert_mutants ["def m(a)\n  !(a) ? 1 : 2\nend\n"], mutants
    assert_same_behavior "def m(a)\n  a ? 2 : 1\nend\n", mutants.first, :m, TRUTHS
  end

  def test_low_precedence_predicates_are_negated_whole
    source = "def m(a, b)\n  if a and b\n    1\n  elsif not a or b\n    2\n  end\nend\n"
    mutants = inline_mutants(source, :if)

    assert_mutants ["def m(a, b)\n  if !(a and b)\n    1\n  elsif not a or b\n    2\n  end\nend\n",
                    "def m(a, b)\n  if a and b\n    1\n  elsif !(not a or b)\n    2\n  end\nend\n"],
                   mutants
    assert_same_behavior "def m(a, b)\n  (a && b) ? ((!a || b) ? 2 : nil) : 1\nend\n", mutants[0], :m, TRUTH_PAIRS
    assert_same_behavior "def m(a, b)\n  (a && b) ? 1 : ((!a || b) ? nil : 2)\nend\n", mutants[1], :m, TRUTH_PAIRS
  end

  def test_low_precedence_predicate_keyword_swap
    mutants = inline_mutants("def m(a, b)\n  1 if a or not b\nend\n", :if)

    assert_mutants ["def m(a, b)\n  1 unless a or not b\nend\n"], mutants
    assert_same_behavior "def m(a, b)\n  (a || !b) ? nil : 1\nend\n", mutants.first, :m, TRUTH_PAIRS
  end

  def test_if_nested_in_elsif_body
    source = "def m(a, b, c)\n  if a\n    1\n  elsif b\n    if c\n      2\n    else\n      3\n    end\n  end\nend\n"
    mutants = inline_mutants(source, :if)

    assert_mutants ["def m(a, b, c)\n  if !(a)\n    1\n  elsif b\n    if c\n      2\n    else\n      3\n    end\n  end\nend\n",
                    "def m(a, b, c)\n  if a\n    1\n  elsif !(b)\n    if c\n      2\n    else\n      3\n    end\n  end\nend\n",
                    "def m(a, b, c)\n  if a\n    1\n  elsif b\n    unless c\n      2\n    else\n      3\n    end\n  end\nend\n"],
                   mutants
    triples = [true, false].product([true, false], [true, false])
    assert_same_behavior "def m(a, b, c)\n  a ? (b ? (c ? 2 : 3) : nil) : 1\nend\n", mutants[0], :m, triples
    assert_same_behavior "def m(a, b, c)\n  a ? 1 : (b ? nil : (c ? 2 : 3))\nend\n", mutants[1], :m, triples
    assert_same_behavior "def m(a, b, c)\n  a ? 1 : (b ? (c ? 3 : 2) : nil)\nend\n", mutants[2], :m, triples
  end

  def test_call
    expected = [
      <<~RUBY,
        def uses_call
          nil
        end
      RUBY
      <<~RUBY,
        def uses_call
          nil + some_other_func
        end
      RUBY
      <<~RUBY,
        def uses_call
          some_func + nil
        end
      RUBY
    ]

    assert_mutants expected, fixture_mutants("uses_call", :call)
  end

  def test_call_with_block_is_not_a_call
    expected = [
      <<~RUBY,
        def uses_callblock
          nil.y { 1 }
        end
      RUBY
    ]

    assert_mutants expected, fixture_mutants("uses_callblock", [:call])
  end

  def test_callblock
    expected = [
      <<~RUBY,
        def uses_callblock
          nil
        end
      RUBY
      <<~RUBY,
        def uses_callblock
          nil.y { 1 }
        end
      RUBY
    ]

    assert_mutants expected, fixture_mutants("uses_callblock", [:call, :iter])
  end

  def test_iter
    expected = [
      <<~RUBY,
        def uses_iter
          x = [ 1, 2, 3 ]
          nil
        end
      RUBY
    ]

    assert_mutants expected, fixture_mutants("uses_iter", [:call, :iter])
  end

  def mutation_kinds(source)
    def_node = Prism.parse(source).value.statements.body.first
    Heckle::Mutator.new(STUB).mutations_for(def_node).map(&:kind)
  end

  def test_block_pass_argument_is_a_call
    source = "def m(blk)\n  foo(&blk)\nend\n"

    assert_mutants ["def m(blk)\n  nil\nend\n"], inline_mutants(source, [:call, :iter])
    assert_equal [:call], mutation_kinds(source)
  end

  def test_do_block_is_an_iter_and_its_body_is_visited
    source = "def m\n  foo do\n    bar\n  end\nend\n"

    assert_mutants ["def m\n  nil\nend\n", "def m\n  foo do\n    nil\n  end\nend\n"],
                   inline_mutants(source, [:call, :iter])
    assert_equal [:iter, :call], mutation_kinds(source)
  end

  def test_lambda_is_not_mutated_but_its_body_is
    assert_mutants ["def m\n  -> { nil }\nend\n"],
                   inline_mutants("def m\n  -> { foo }\nend\n", [:call, :iter])
  end

  def test_super_and_yield_are_not_mutated_but_their_arguments_are
    source = "def m\n  super(foo)\n  super\n  yield bar\nend\n"

    assert_mutants ["def m\n  super(nil)\n  super\n  yield bar\nend\n",
                    "def m\n  super(foo)\n  super\n  yield nil\nend\n"],
                   inline_mutants(source, [:call, :iter])
  end

  def test_super_with_block_is_not_an_iter
    assert_mutants ["def m\n  super { nil }\nend\n"],
                   inline_mutants("def m\n  super { foo }\nend\n", [:call, :iter])
  end

  def test_attribute_write
    mutants = inline_mutants("def m\n  self.foo = 1\nend\n", :call)

    assert_mutants ["def m\n  nil\nend\n"], mutants
  end

  def test_index_call
    mutants = inline_mutants("def m(a)\n  a[0]\nend\n", :call)

    assert_mutants ["def m(a)\n  nil\nend\n"], mutants
    assert_nil call_mutant(mutants.first, :m, [1])
  end

  def test_operator_call
    assert_mutants ["def m(x)\n  nil\nend\n"], inline_mutants("def m(x)\n  !x\nend\n", :call)
  end

  def test_safe_navigation_call
    assert_mutants ["def m(a)\n  nil\nend\n"], inline_mutants("def m(a)\n  a&.b\nend\n", :call)
  end

  def test_call_inside_interpolation
    assert_mutants ["def m\n  \"s\#{nil}\"\nend\n"],
                   inline_mutants("def m\n  \"s\#{foo}\"\nend\n", :call)
  end

  def test_command_call_without_parentheses
    source = "def m\n  foo bar, baz\nend\n"

    assert_mutants ["def m\n  nil\nend\n",
                    "def m\n  foo nil, baz\nend\n",
                    "def m\n  foo bar, nil\nend\n"],
                   inline_mutants(source, :call)
  end

  def test_mutation_containing_a_heredoc_opening_is_dropped
    source = <<~'SOURCE'
      def m
        foo(<<~X, baz)
          a #{bar}
        X
      end
    SOURCE
    expected = [
      <<~'RUBY',
        def m
          foo(<<~X, nil)
            a #{bar}
          X
        end
      RUBY
      <<~'RUBY',
        def m
          foo(<<~X, baz)
            a #{nil}
          X
        end
      RUBY
    ]

    assert_mutants expected, inline_mutants(source, :call)
  end

  def test_heredoc_receiver_drops_the_call
    source = "def m\n  <<~X.strip\n    a\n  X\nend\n"

    assert_empty inline_mutants(source, :call)
  end

  ASGN_KINDS = [:lasgn, :iasgn, :gasgn, :cvasgn]

  def test_lasgn
    expected = [
      <<~RUBY,
        def uses_lasgn
          lvar = nil
          lvar = nil
        end
      RUBY
      <<~RUBY,
        def uses_lasgn
          lvar = 5
          lvar = 42
        end
      RUBY
    ]

    assert_mutants expected, fixture_mutants("uses_lasgn", :lasgn)
  end

  def test_operator_writes_are_assignments
    expected = [
      <<~RUBY,
        def uses_numeric_literals
          i = nil
          i += 2147483648
          i -= 3.5
        end
      RUBY
      <<~RUBY,
        def uses_numeric_literals
          i = 1
          i += nil
          i -= 3.5
        end
      RUBY
      <<~RUBY,
        def uses_numeric_literals
          i = 1
          i += 2147483648
          i -= nil
        end
      RUBY
    ]

    assert_mutants expected, fixture_mutants("uses_numeric_literals", [:lasgn])
  end

  def test_lasgn_compound_forms
    source = "def m(a)\n  a += 1\n  a ||= 2\n  a &&= nil\nend\n"

    assert_mutants ["def m(a)\n  a += nil\n  a ||= 2\n  a &&= nil\nend\n",
                    "def m(a)\n  a += 1\n  a ||= nil\n  a &&= nil\nend\n",
                    "def m(a)\n  a += 1\n  a ||= 2\n  a &&= 42\nend\n"],
                   inline_mutants(source, :lasgn)
  end

  def test_constant_write_is_not_an_assignment
    source = "def m\n  self.class::X += 1\n  self.class::Y ||= 2\nend\n"

    assert Prism.parse(source).success?
    assert_empty inline_mutants(source, ASGN_KINDS)
  end

  def test_assignment_of_a_call_mutates_both
    source = "def m\n  x = foo(bar)\nend\n"

    assert_mutants ["def m\n  x = nil\nend\n",
                    "def m\n  x = nil\nend\n",
                    "def m\n  x = foo(nil)\nend\n"],
                   inline_mutants(source, [:lasgn, :call])
    assert_equal [:lasgn, :call, :call], mutation_kinds(source)
  end

  def test_assignment_of_a_heredoc_is_dropped
    source = <<~'SOURCE'
      def m
        x = <<~X
          a #{bar}
        X
      end
    SOURCE
    expected = <<~'RUBY'
      def m
        x = <<~X
          a #{nil}
        X
      end
    RUBY

    assert_mutants [expected], inline_mutants(source, [:lasgn, :call])
  end

  def test_iasgn
    expected = [
      <<~RUBY,
        def uses_iasgn
          @ivar = nil
          @ivar = nil
        end
      RUBY
      <<~RUBY,
        def uses_iasgn
          @ivar = 5
          @ivar = 42
        end
      RUBY
    ]

    assert_mutants expected, fixture_mutants("uses_iasgn", :iasgn)
  end

  def test_iasgn_compound_forms
    source = "def m\n  @a += 1\n  @a ||= 2\n  @a &&= nil\nend\n"

    assert_mutants ["def m\n  @a += nil\n  @a ||= 2\n  @a &&= nil\nend\n",
                    "def m\n  @a += 1\n  @a ||= nil\n  @a &&= nil\nend\n",
                    "def m\n  @a += 1\n  @a ||= 2\n  @a &&= 42\nend\n"],
                   inline_mutants(source, :iasgn)
  end

  def test_gasgn
    expected = [
      <<~RUBY,
        def uses_gasgn
          $gvar = nil
          $gvar = nil
        end
      RUBY
      <<~RUBY,
        def uses_gasgn
          $gvar = 5
          $gvar = 42
        end
      RUBY
    ]

    assert_mutants expected, fixture_mutants("uses_gasgn", :gasgn)
  end

  def test_gasgn_compound_forms
    source = "def m\n  $a += 1\n  $a ||= 2\n  $a &&= nil\nend\n"

    assert_mutants ["def m\n  $a += nil\n  $a ||= 2\n  $a &&= nil\nend\n",
                    "def m\n  $a += 1\n  $a ||= nil\n  $a &&= nil\nend\n",
                    "def m\n  $a += 1\n  $a ||= 2\n  $a &&= 42\nend\n"],
                   inline_mutants(source, :gasgn)
  end

  def test_cvasgn
    expected = [
      <<~RUBY,
        def uses_cvasgn
          @@cvar = nil
          @@cvar = nil
        end
      RUBY
      <<~RUBY,
        def uses_cvasgn
          @@cvar = 5
          @@cvar = 42
        end
      RUBY
    ]

    assert_mutants expected, fixture_mutants("uses_cvasgn", :cvasgn)
  end

  def test_cvasgn_compound_forms
    source = "def m\n  @@a += 1\n  @@a ||= 2\n  @@a &&= nil\nend\n"

    assert_mutants ["def m\n  @@a += nil\n  @@a ||= 2\n  @@a &&= nil\nend\n",
                    "def m\n  @@a += 1\n  @@a ||= nil\n  @@a &&= nil\nend\n",
                    "def m\n  @@a += 1\n  @@a ||= 2\n  @@a &&= 42\nend\n"],
                   inline_mutants(source, :cvasgn)
  end

  def test_mutations_are_sorted_by_start_then_widest_first
    def_node = Prism.parse("def m\n  [true, false, true]\nend\n").value.statements.body.first
    mutations = Heckle::Mutator.new(STUB).mutations_for(def_node)

    assert_equal mutations.sort_by { |m| [m.start_offset, -m.end_offset] }, mutations
    assert_equal %i[true false true], mutations.map(&:kind)
  end
end
