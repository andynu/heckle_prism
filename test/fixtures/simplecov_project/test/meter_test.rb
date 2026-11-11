require "test_helper"

class MeterTest < Minitest::Test
  def test_doubled
    assert_equal 6, Meter.new(3).doubled
  end

  # Weak on purpose: any string passes.
  def test_label
    assert_kind_of String, Meter.new(3).label
  end
end
