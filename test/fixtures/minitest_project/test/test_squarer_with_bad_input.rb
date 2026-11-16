require "minitest/autorun"
require "squarer"

class TestSquarerWithBadInput < Minitest::Test
  def test_square_of_a_string
    assert_equal "not a number", Squarer.new.square("3")
  end

  def test_square_of_nil
    assert_equal "not a number", Squarer.new.square(nil)
  end
end
