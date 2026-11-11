require "minitest/autorun"
require "doubler"

# Fails on purpose. Outside test/, so the default patterns miss it; select with -t.
# Odd, so no random multiplier in a mutant can make it pass.
class BrokenDoublerTest < Minitest::Test
  def test_double_is_odd
    assert_equal 5, Doubler.new.double(2)
  end
end
