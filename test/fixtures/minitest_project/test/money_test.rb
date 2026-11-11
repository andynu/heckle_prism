require "minitest/autorun"
require "money"

class MoneyTest < Minitest::Test
  # Only a divisor of 100 gives both.
  def test_dollars
    assert_equal 3, Money.new(cents: 399).dollars
    assert_equal 4, Money.new(cents: 400).dollars
  end

  def test_zero
    assert_equal 0, Money.zero.cents
  end
end
