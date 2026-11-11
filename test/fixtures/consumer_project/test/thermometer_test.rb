require "test_helper"
require "minitest/autorun"

class ThermometerTest < Minitest::Test
  def test_boiling_in_fahrenheit
    assert_equal 212, Thermometer.new(100).fahrenheit
  end

  def test_freezing
    assert_equal 32, Thermometer.freezing.fahrenheit
  end
end
