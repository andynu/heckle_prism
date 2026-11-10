require "minitest/autorun"
require "heckle/method_finder"

class TestMethodFinder < Minitest::Test
  FIXTURE = File.expand_path("fixtures/heckle_dummy.rb", __dir__)
  INNER_CLASS = "HeckleDummy::OuterNesting::InnerNesting::InnerClass"

  def fixture_finder
    @fixture_finder ||= Heckle::MethodFinder.new(File.read(FIXTURE))
  end

  def find_in_fixture(klass_name, method_name)
    fixture_finder.find(klass_name, method_name)
  end

  def find_in(source, klass_name, method_name)
    Heckle::MethodFinder.new(source).find(klass_name, method_name)
  end

  def body_of(result)
    result.def_node.body.slice
  end

  def test_instance_method
    result = find_in_fixture("HeckleDummy", "uses_if")

    assert_instance_of Prism::DefNode, result.def_node
    assert_equal :uses_if, result.def_node.name
    assert_equal 109, result.def_node.location.start_line
    assert_nil result.def_node.receiver
  end

  def test_class_method
    result = find_in_fixture("HeckleDummy", "self.is_a_klass_method?")

    assert_equal 156, result.def_node.location.start_line
    assert_instance_of Prism::SelfNode, result.def_node.receiver
    assert_equal "true", body_of(result)
  end

  def test_method_name_may_be_a_symbol
    result = find_in_fixture("HeckleDummy", :uses_if)

    assert_equal 109, result.def_node.location.start_line
  end

  def test_outer_nesting_foo
    result = find_in_fixture("HeckleDummy::OuterNesting", "foo")

    assert_equal "-1", body_of(result)
    assert_equal 161, result.def_node.location.start_line
  end

  def test_inner_class_bar
    result = find_in_fixture(INNER_CLASS, "bar")

    assert_equal "-1", body_of(result)
    assert_equal 171, result.def_node.location.start_line
  end

  def test_inner_class_foo_in_reopened_class
    result = find_in_fixture(INNER_CLASS, "foo")

    assert_equal "1337", body_of(result)
    assert_equal 189, result.def_node.location.start_line
  end

  def test_decoy_nesting_foo
    result = find_in_fixture("#{INNER_CLASS}::DecoyNesting", "foo")

    assert_equal "-4", body_of(result)
    assert_equal 184, result.def_node.location.start_line
  end

  def test_reopened_module_foo_selected_by_line
    first = fixture_finder.find("HeckleDummy::OuterNesting::InnerNesting", "foo", line: 166)
    second = fixture_finder.find("HeckleDummy::OuterNesting::InnerNesting", "foo", line: 178)

    assert_equal "-2", body_of(first)
    assert_equal 160, first.nesting[1].location.start_line
    assert_equal 165, first.nesting[2].location.start_line
    assert_equal "-3", body_of(second)
    assert_equal 177, second.nesting[2].location.start_line
  end

  def test_last_definition_wins_without_line
    result = find_in_fixture("HeckleDummy::OuterNesting::InnerNesting", "foo")

    assert_equal "-3", body_of(result)
    assert_equal 178, result.def_node.location.start_line
  end

  def test_line_matching_no_def_is_nil
    assert_nil fixture_finder.find("HeckleDummy::OuterNesting::InnerNesting", "foo", line: 167)
    assert_nil fixture_finder.find("HeckleDummy", "uses_if", line: 110)
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

    assert_nil Heckle::MethodFinder.new(source).find("A", "foo", line: 2)
    assert_equal ":split", body_of(Heckle::MethodFinder.new(source).find("A", "foo", line: 3))
  end

  def test_missing_method_is_nil
    assert_nil find_in_fixture("HeckleDummy", "no_such_method")
  end

  def test_missing_class_is_nil
    assert_nil find_in_fixture("HeckleDummy::NoSuchClass", "foo")
    assert_nil find_in_fixture("NoSuchClass", "uses_if")
  end

  def test_nesting_is_outermost_first
    nesting = find_in_fixture(INNER_CLASS, "foo").nesting

    assert_equal [Prism::ClassNode, Prism::ModuleNode, Prism::ModuleNode, Prism::ClassNode],
                 nesting.map(&:class)
    assert_equal %w[HeckleDummy OuterNesting InnerNesting InnerClass],
                 nesting.map { |node| node.constant_path.slice }
    assert_equal [1, 160, 177, 182], nesting.map { |node| node.location.start_line }
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
