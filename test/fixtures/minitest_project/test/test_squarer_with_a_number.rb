require "minitest/autorun"
require "squarer"

class TestSquarerWithANumber < Minitest::Test
  def test_square_of_three
    assert_equal 9, Squarer.new.square(3)
  end
end
