require "minitest/autorun"
require "relay"

# Outside test/; select with -t. teardown takes five seconds after a test
# that did not get past the call to pass_on, as after a timeout.
class SlowTeardownRelayTest < Minitest::Test
  def test_pass_on
    $relay_in_call = true
    result = Relay.new([5, 6, 7]).pass_on
    $relay_in_call = false
    assert_equal 5, result
  end

  def teardown
    sleep 5 if $relay_in_call
  end
end
