require "minitest/autorun"
require "relay"

# Outside test/; select with -t.
class RelayTest < Minitest::Test
  def test_pass_on
    assert_equal 5, Relay.new([5, 6, 7]).pass_on
  end

  def test_gather
    assert_equal 5, Relay.new([5, 6, 7]).gather
  end
end
