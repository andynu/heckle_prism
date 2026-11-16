require "minitest/autorun"
require "heckle_prism/method_finder"

class TestMethodFinder < Minitest::Test
  FIXTURE = File.expand_path("fixtures/specimen.rb", __dir__)
  INNER_CLASS = "Specimen::Freezer::Shelf::Box"

  def fixture_finder
    @fixture_finder ||= HecklePrism::MethodFinder.new(File.read(FIXTURE))
  end

  def find_in_fixture(klass_name, method_name)
    fixture_finder.find(klass_name, method_name)
  end

  def find_in(source, klass_name, method_name)
    HecklePrism::MethodFinder.new(source).find(klass_name, method_name)
  end

  def body_of(result)
    result.def_node.body.slice
  end

  def test_instance_method
    result = find_in_fixture("Specimen", "branch_if")

    assert_instance_of Prism::DefNode, result.def_node
    assert_equal :branch_if, result.def_node.name
    assert_equal 51, result.def_node.location.start_line
    assert_nil result.def_node.receiver
  end

  def test_class_method
    result = find_in_fixture("Specimen", "self.sterile?")

    assert_equal 143, result.def_node.location.start_line
    assert_instance_of Prism::SelfNode, result.def_node.receiver
    assert_equal "false", body_of(result)
  end

  def test_method_name_may_be_a_symbol
    result = find_in_fixture("Specimen", :branch_if)

    assert_equal 51, result.def_node.location.start_line
  end

  def test_outer_module_position
    result = find_in_fixture("Specimen::Freezer", "position")

    assert_equal ":freezer", body_of(result)
    assert_equal 148, result.def_node.location.start_line
  end

  def test_inner_class_capacity
    result = find_in_fixture(INNER_CLASS, "capacity")

    assert_equal "81", body_of(result)
    assert_equal 158, result.def_node.location.start_line
  end

  def test_inner_class_position_in_reopened_class
    result = find_in_fixture(INNER_CLASS, "position")

    assert_equal ":box", body_of(result)
    assert_equal 176, result.def_node.location.start_line
  end

  def test_lookalike_module_position
    result = find_in_fixture("#{INNER_CLASS}::Lookalike", "position")

    assert_equal ":lookalike", body_of(result)
    assert_equal 171, result.def_node.location.start_line
  end

  def test_reopened_module_position_selected_by_line
    first = fixture_finder.find("Specimen::Freezer::Shelf", "position", line: 153)
    second = fixture_finder.find("Specimen::Freezer::Shelf", "position", line: 165)

    assert_equal ":upper_shelf", body_of(first)
    assert_equal 147, first.nesting[1].location.start_line
    assert_equal 152, first.nesting[2].location.start_line
    assert_equal ":lower_shelf", body_of(second)
    assert_equal 164, second.nesting[2].location.start_line
  end

  def test_last_definition_wins_without_line
    result = find_in_fixture("Specimen::Freezer::Shelf", "position")

    assert_equal ":lower_shelf", body_of(result)
    assert_equal 165, result.def_node.location.start_line
  end

  def test_line_matching_no_def_is_nil
    assert_nil fixture_finder.find("Specimen::Freezer::Shelf", "position", line: 154)
    assert_nil fixture_finder.find("Specimen", "branch_if", line: 52)
  end

  def test_line_uses_the_def_keyword_line
    source = <<~RUBY
      class A
        private \\
          def foo
            :split
          end
      end
    RUBY

    assert_nil HecklePrism::MethodFinder.new(source).find("A", "foo", line: 2)
    assert_equal ":split", body_of(HecklePrism::MethodFinder.new(source).find("A", "foo", line: 3))
  end

  def test_missing_method_is_nil
    assert_nil find_in_fixture("Specimen", "no_such_method")
  end

  def test_missing_class_is_nil
    assert_nil find_in_fixture("Specimen::NoSuchClass", "position")
    assert_nil find_in_fixture("NoSuchClass", "branch_if")
  end

  def test_nesting_is_outermost_first
    nesting = find_in_fixture(INNER_CLASS, "position").nesting

    assert_equal [Prism::ClassNode, Prism::ModuleNode, Prism::ModuleNode, Prism::ClassNode],
                 nesting.map(&:class)
    assert_equal %w[Specimen Freezer Shelf Box],
                 nesting.map { |node| node.constant_path.slice }
    assert_equal [5, 147, 164, 169], nesting.map { |node| node.location.start_line }
  end

  def test_compact_class_header
    source = <<~RUBY
      class A::B
        def foo
          :compact
        end
      end
    RUBY

    result = find_in(source, "A::B", "foo")

    assert_equal ":compact", body_of(result)
    assert_equal ["A::B"], result.nesting.map { |node| node.constant_path.slice }
    assert_nil find_in(source, "A", "foo")
    assert_nil find_in(source, "B", "foo")
  end

  def test_compact_header_inside_module
    source = <<~RUBY
      module A
        class B::C
          def foo
            :deep
          end
        end
      end
    RUBY

    result = find_in(source, "A::B::C", "foo")

    assert_equal ":deep", body_of(result)
    assert_equal %w[A B::C], result.nesting.map { |node| node.constant_path.slice }
  end

  def test_rooted_header_inside_module_is_top_level
    source = <<~RUBY
      module A
        class ::D
          def foo
            :rooted
          end
        end
      end
    RUBY

    assert_equal ":rooted", body_of(find_in(source, "D", "foo"))
    assert_nil find_in(source, "A::D", "foo")
  end

  def test_singleton_class_block
    source = <<~RUBY
      class A
        class << self
          def foo
            :singleton
          end
        end
      end
    RUBY

    result = find_in(source, "A", "self.foo")

    assert_equal ":singleton", body_of(result)
    assert_equal [Prism::ClassNode, Prism::SingletonClassNode], result.nesting.map(&:class)
    assert_nil find_in(source, "A", "foo")
  end

  # `def self.foo` inside `class << self` defines a method on the singleton
  # class's own singleton, not A.foo.
  def test_self_def_inside_singleton_class_block_is_not_a_class_method
    source = <<~RUBY
      class A
        class << self
          def self.foo
            :meta
          end
        end
      end
    RUBY

    assert_nil find_in(source, "A", "self.foo")
    assert_nil find_in(source, "A", "foo")
  end

  def test_def_passed_to_a_call
    source = <<~RUBY
      class A
        private def foo
          :private
        end

        private memoize def bar
          :memoized
        end

        class << self
          private def baz
            :private_singleton
          end
        end
      end
    RUBY

    assert_equal ":private", body_of(find_in(source, "A", "foo"))
    assert_equal ":memoized", body_of(find_in(source, "A", "bar"))
    assert_equal ":private_singleton", body_of(find_in(source, "A", "self.baz"))
  end

  def test_class_reopened_twice
    source = <<~RUBY
      class A
        def first
          :first
        end
      end

      class B
      end

      class A
        def second
          :second
        end
      end

      class A
        def third
          :third
        end
      end
    RUBY

    assert_equal ":first", body_of(find_in(source, "A", "first"))
    assert_equal ":second", body_of(find_in(source, "A", "second"))

    third = find_in(source, "A", "third")

    assert_equal ":third", body_of(third)
    assert_equal 16, third.nesting.first.location.start_line
  end

  def test_instance_and_class_methods_do_not_cross_match
    instance_only = <<~RUBY
      class A
        def foo
        end
      end
    RUBY
    class_only = <<~RUBY
      class A
        def self.foo
        end
      end
    RUBY

    assert_nil find_in(instance_only, "A", "self.foo")
    assert_nil find_in(class_only, "A", "foo")
    refute_nil find_in(instance_only, "A", "foo")
    refute_nil find_in(class_only, "A", "self.foo")
  end

  def test_data_define_block
    source = <<~RUBY
      module M
        Point = Data.define(:x, :y) do
          def sum
            :data
          end
        end
      end
    RUBY

    result = find_in(source, "M::Point", "sum")

    assert_equal ":data", body_of(result)
    assert_equal [Prism::ModuleNode, Prism::ConstantWriteNode], result.nesting.map(&:class)
    assert_equal :Point, result.nesting.last.name
    assert_nil find_in(source, "Point", "sum")
    assert_nil find_in(source, "M", "sum")
  end

  def test_struct_new_brace_block
    source = <<~RUBY
      Pair = Struct.new(:a, :b) { def total; :braces; end }
    RUBY

    assert_equal ":braces", body_of(find_in(source, "Pair", "total"))
  end

  def test_class_new_with_parent
    source = <<~RUBY
      class Outer
        Child = Class.new(StandardError) do
          def message
            :child
          end
        end
      end
    RUBY

    assert_equal ":child", body_of(find_in(source, "Outer::Child", "message"))
  end

  def test_module_new_block
    source = <<~RUBY
      Helpers = Module.new do
        def help
          :module
        end
      end
    RUBY

    assert_equal ":module", body_of(find_in(source, "Helpers", "help"))
  end

  def test_constant_path_assignment
    source = <<~RUBY
      module A
        B::C = Struct.new(:v) do
          def v2
            :path
          end
        end
      end
      A::D = Struct.new(:v) do
        def v3
          :top
        end
      end
    RUBY

    result = find_in(source, "A::B::C", "v2")

    assert_equal ":path", body_of(result)
    assert_equal [Prism::ModuleNode, Prism::ConstantPathWriteNode], result.nesting.map(&:class)
    assert_equal ":top", body_of(find_in(source, "A::D", "v3"))
  end

  def test_rooted_constant_path_assignment_is_top_level
    source = <<~RUBY
      module A
        ::E = Struct.new(:v) do
          def v4
            :rooted
          end
        end
      end
    RUBY

    assert_equal ":rooted", body_of(find_in(source, "E", "v4"))
    assert_nil find_in(source, "A::E", "v4")
  end

  def test_block_scope_class_methods
    source = <<~RUBY
      Pair = Struct.new(:a) do
        def self.build
          :self_def
        end

        class << self
          def make
            :singleton
          end
        end

        private def hidden
          :private
        end
      end
    RUBY

    assert_equal ":self_def", body_of(find_in(source, "Pair", "self.build"))
    singleton = find_in(source, "Pair", "self.make")
    assert_equal ":singleton", body_of(singleton)
    assert_equal [Prism::ConstantWriteNode, Prism::SingletonClassNode], singleton.nesting.map(&:class)
    assert_equal ":private", body_of(find_in(source, "Pair", "hidden"))
    assert_nil find_in(source, "Pair", "build")
  end

  def test_block_scope_reopened_by_class_keyword
    source = <<~RUBY
      Pair = Struct.new(:a) do
        def first
          :block
        end
      end

      class Pair
        def second
          :reopened
        end
      end
    RUBY

    assert_equal ":block", body_of(find_in(source, "Pair", "first"))
    assert_equal ":reopened", body_of(find_in(source, "Pair", "second"))
  end

  # A class keyword inside the block names a constant of the enclosing
  # scope, not of the block-defined class.
  def test_scopes_inside_a_block_scope_are_not_searched
    source = <<~RUBY
      Pair = Struct.new(:a) do
        class Inner
          def foo
            :inner
          end
        end
      end
    RUBY

    assert_nil find_in(source, "Pair::Inner", "foo")
  end

  def test_constant_assignment_without_block_is_not_a_scope
    source = <<~RUBY
      Pair = Struct.new(:a)
      def foo
        :top
      end
      Value = 1
    RUBY

    assert_nil find_in(source, "Pair", "foo")
    assert_nil find_in(source, "Value", "foo")
  end

  def test_block_scope_selected_by_line
    source = <<~RUBY
      Pair = Struct.new(:a) do
        def foo
          :first
        end

        def foo
          :second
        end
      end
    RUBY

    assert_equal ":first", body_of(HecklePrism::MethodFinder.new(source).find("Pair", "foo", line: 2))
    assert_equal ":second", body_of(find_in(source, "Pair", "foo"))
  end

  def test_class_body_with_rescue
    source = <<~RUBY
      class A
        def foo
          :in_begin
        end
      rescue
        nil
      end
    RUBY

    assert_equal ":in_begin", body_of(find_in(source, "A", "foo"))
  end
end
