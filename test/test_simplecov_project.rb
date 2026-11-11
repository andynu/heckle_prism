require "minitest/autorun"
require "digest"
require "open3"
require "rbconfig"

# A project whose test_helper starts SimpleCov. Its coverage directory is
# committed with one marker file, and a heckle run must leave it untouched.
class TestSimpleCovProject < Minitest::Test
  BIN = File.expand_path("../bin/heckle", __dir__)
  PROJECT = File.expand_path("fixtures/simplecov_project", __dir__)
  COVERAGE = File.join(PROJECT, "coverage")

  def heckle(*args)
    Open3.capture3(RbConfig.ruby, BIN, *args, chdir: PROJECT)
  end

  def coverage_snapshot
    entries = Dir.glob("**/*", File::FNM_DOTMATCH, base: COVERAGE).sort.map do |name|
      path = File.join(COVERAGE, name)
      [name, File.mtime(path), File.file?(path) ? Digest::SHA256.file(path).hexdigest : :dir]
    end
    [File.mtime(COVERAGE), entries]
  end

  def assert_coverage_untouched(*args)
    before = coverage_snapshot
    out, err, status = heckle(*args)

    assert_equal ["marker.txt"], Dir.children(COVERAGE)
    assert_equal before, coverage_snapshot
    [out, err].each do |stream|
      refute_includes stream, "SimpleCov"
      refute_includes stream, "Coverage"
    end
    [out, err, status]
  end

  def test_run_without_survivors_leaves_coverage_alone
    out, err, status = assert_coverage_untouched("Meter", "doubled")

    assert_equal "", err
    assert_includes out, "No mutants survived."
    assert_equal 0, status.exitstatus
  end

  def test_run_with_survivors_leaves_coverage_alone
    out, err, status = assert_coverage_untouched("Meter", "label")

    assert_equal "", err
    assert_includes out, "The following mutations didn't cause test failures:"
    assert_equal 1, status.exitstatus
  end
end
