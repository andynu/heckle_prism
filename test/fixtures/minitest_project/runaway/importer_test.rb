require "minitest/autorun"
require "importer"

# Outside test/, so the default patterns miss it; select with -t.
# Both tests reach count_rows through a rescue of StandardError.
class ImporterTest < Minitest::Test
  def test_import
    assert_equal 3, Importer.new(1..3).import
  end

  def test_import_again
    assert_equal 2, Importer.new(4..5).import
  end
end
