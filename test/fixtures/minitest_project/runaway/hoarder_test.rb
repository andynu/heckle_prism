require "minitest/autorun"
require "hoarder"

# Outside test/; select with -t.
class HoarderTest < Minitest::Test
  def test_load
    assert_equal 3 * Hoarder::CHUNK, Hoarder.new([1, 2, 3]).load
  end
end
