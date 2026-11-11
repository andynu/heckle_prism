require "test_helper"

# Only this file covers Halver#quarter. 16 / 3 and 16 / 5 both miss 4, so
# every literal mutant dies; 8 / 3 would still give 2.
class TestQuarter < Minitest::Test
  def test_quarter
    assert_equal 4, Halver.new.quarter(16)
  end
end
