require "minitest/autorun"
require "relay"

# Outside test/; select with -t. setup fails while the state teardown
# resets is still set, as a test fails on a transaction left open.
class TeardownRelayTest < Minitest::Test
  def setup
    flunk "the state of an earlier test was left set" if $relay_state_set
    $relay_state_set = true
  end

  def teardown
    $relay_state_set = false
  end

  def test_pass_on
    assert_equal 5, Relay.new([5, 6, 7]).pass_on
  end
end
