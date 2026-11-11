require "minitest/autorun"
require "gauge"

class GaugeTest < Minitest::Test
  def test_read
    gauge = Gauge.new
    gauge.level = 3
    assert_equal 3, gauge.read
  end

  def test_calibrated
    assert_equal 42, Gauge.new.calibrated
  end
end
