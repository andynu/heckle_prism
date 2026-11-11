require "minitest/autorun"
require "baton"

# Outside test/; select with -t. teardown takes five seconds after a test
# that did not get past its call to pass, as after a timeout.
class SlowTeardownBatonTest < Minitest::Test
  def test_first
    assert_equal 5, Baton.new([5, 6, 7]).first
  end

  def test_pass
    $baton_in_call = true
    result = Baton.new([5, 6, 7]).pass
    $baton_in_call = false
    assert_equal 7, result
  end

  def test_peek
    assert_equal 7, Baton.new([5, 6, 7]).peek
  end

  def teardown
    sleep 5 if $baton_in_call
  end
end
