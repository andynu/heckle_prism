require "minitest/autorun"
require "doubler"

# Fails on purpose. Outside test/, so the default patterns miss it; select with -t.
class BrokenDoublerTest < Minitest::Test
  def test_double_is_triple
    assert_equal 6, Doubler.new.double(2)
  end
end
