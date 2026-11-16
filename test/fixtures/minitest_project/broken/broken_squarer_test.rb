require "minitest/autorun"
require "squarer"

# Fails on purpose. Outside test/, so the default patterns miss it; select with -t.
# 10 is no power of 3, so no random exponent in a mutant can make it pass.
class BrokenSquarerTest < Minitest::Test
  def test_square_is_ten
    assert_equal 10, Squarer.new.square(3)
  end
end
