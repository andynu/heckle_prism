require "minitest/autorun"
require "prism"

class TestSmoke < Minitest::Test
  FIXTURE = File.expand_path("fixtures/heckle_dummy.rb", __dir__)

  def test_prism_parses_fixture
    result = Prism.parse_file(FIXTURE)

    assert result.success?, result.errors.map(&:message).join("\n")
  end
end
