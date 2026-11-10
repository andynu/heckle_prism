require "minitest/autorun"
require "prism"
require "heckle/mutation"

class TestMutation < Minitest::Test
  def mutation(start_offset, end_offset, replacement, kind: :lit)
    Heckle::Mutation.new(kind: kind, start_offset: start_offset,
                         end_offset: end_offset, replacement: replacement)
  end

  def test_attributes
    m = mutation(1, 3, "x", kind: :true)

    assert_equal :true, m.kind
    assert_equal 1, m.start_offset
    assert_equal 3, m.end_offset
    assert_equal "x", m.replacement
  end

  def test_replaces_span
    assert_equal "a = 7", mutation(4, 5, "7").apply("a = 1")
  end

  def test_replacement_longer_than_span
    assert_equal "x = false && y", mutation(4, 8, "false").apply("x = true && y")
  end

  def test_replacement_shorter_than_span
    assert_equal "x = nil", mutation(4, 16, "nil").apply("x = some_func(1)")
  end

  def test_base_offset
    file = "# header\ndef foo\n  1\nend\n"
    def_start = file.index("def")
    def_text = file[def_start..]
    one = file.index("1")

    assert_equal "def foo\n  2\nend\n", mutation(one, one + 1, "2").apply(def_text, def_start)
  end

  def test_multibyte_source_before_span
    source = "def foo\n  s = \"héllo 日本\"\n  1 + 2\nend\n"
    node = Prism.parse(source).value.statements.body[0].body.body[1].arguments.arguments[0]
    assert_instance_of Prism::IntegerNode, node

    result = mutation(node.location.start_offset, node.location.end_offset, "7").apply(source)

    assert_equal "def foo\n  s = \"héllo 日本\"\n  1 + 7\nend\n", result
    assert_equal Encoding::UTF_8, result.encoding
    assert result.valid_encoding?
    assert Prism.parse(result).success?
  end

  def test_does_not_modify_argument
    source = +"a = 1"

    mutation(4, 5, "7").apply(source)

    assert_equal "a = 1", source
  end

  def test_works_on_frozen_string
    source = "a = 1".freeze

    result = mutation(4, 5, "7").apply(source)

    assert_equal "a = 7", result
    refute_same source, result
  end
end
