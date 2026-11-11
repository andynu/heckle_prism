require "minitest/autorun"
require "relay"

# Outside test/; select with -t. The test swallows one timeout, then
# fails, so its run returns normally after the timeout was raised.
class StubbornRelayTest < Minitest::Test
  def test_pass_on
    result = begin
      Relay.new([5, 6, 7]).pass_on
    rescue Exception
      :swallowed
    end
    assert_equal 5, result
  end
end
