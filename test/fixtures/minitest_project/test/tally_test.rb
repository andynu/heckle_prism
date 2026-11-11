require "minitest/autorun"
require "tally"

class TallyTest < Minitest::Test
  def test_start
    assert_instance_of Tally, Tally.start
  end

  def test_starts_at_zero
    assert_equal 0, Tally.new.count
  end

  def test_bump
    assert_equal 2, Tally.new.bump.bump.count
  end

  def test_label
    assert_nil Tally.new.label
  end
end
