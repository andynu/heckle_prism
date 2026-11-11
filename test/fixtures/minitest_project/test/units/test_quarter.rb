require "test_helper"

# Only this file covers Halver#quarter.
class TestQuarter < Minitest::Test
  def test_quarter
    assert_equal 2, Halver.new.quarter(8)
  end
end
