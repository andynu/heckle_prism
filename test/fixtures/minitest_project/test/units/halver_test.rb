require "test_helper"

# Only this file covers Halver#halve.
class HalverTest < Minitest::Test
  def test_halve
    assert_equal 2, Halver.new.halve(4)
  end
end
