require "minitest/autorun"
require "money"

class MoneyTest < Minitest::Test
  def test_dollars
    assert_equal 3, Money.new(cents: 345).dollars
  end

  def test_zero
    assert_equal 0, Money.zero.cents
  end
end
