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

  def test_mutations_are_sorted_by_start_then_widest_first
    def_node = Prism.parse("def m\n  [true, false, true]\nend\n").value.statements.body.first
    mutations = Heckle::Mutator.new(STUB).mutations_for(def_node)

    assert_equal mutations.sort_by { |m| [m.start_offset, -m.end_offset] }, mutations
    assert_equal %i[true false true], mutations.map(&:kind)
  end
end
