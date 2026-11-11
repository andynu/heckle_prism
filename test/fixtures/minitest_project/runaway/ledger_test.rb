require "minitest/autorun"
require "ledger"

# Outside test/; select with -t.
class LedgerTest < Minitest::Test
  def test_first
    assert_equal 5, Ledger.new([5, 6, 7]).first
  end

  def test_tally
    assert_equal 3, Ledger.new([5, 6, 7]).tally
  end
end
