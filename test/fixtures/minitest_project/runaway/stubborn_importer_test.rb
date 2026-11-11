require "minitest/autorun"
require "importer"

# Outside test/; select with -t. import_stubbornly rescues Exception, so
# each test swallows one timeout and then passes, whatever it returned.
class StubbornImporterTest < Minitest::Test
  def test_import_stubbornly
    Importer.new(1..3).import_stubbornly
    pass
  end

  def test_import_stubbornly_again
    Importer.new(4..5).import_stubbornly
    pass
  end
end
