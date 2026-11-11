require "minitest/autorun"
require "importer"

# Outside test/; select with -t. import_retrying rescues Exception and
# retries, so it swallows every timeout raised in it.
at_exit { $stderr.puts "at_exit ran" }

class RetryingImporterTest < Minitest::Test
  def test_import_retrying
    assert_equal 3, Importer.new([0, 3]).import_retrying
  end
end
