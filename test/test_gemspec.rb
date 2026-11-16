require "minitest/autorun"
require "open3"
require "rbconfig"
require "heckle_prism"

class TestGemspec < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def spec
    @spec ||= Dir.chdir(ROOT) { Gem::Specification.load("heckle_prism.gemspec") }
  end

  def test_name
    assert_equal "heckle_prism", spec.name
  end

  def test_version_matches_the_library
    assert_equal HecklePrism::VERSION, spec.version.to_s
  end

  # 3 and later, so this fork's releases are not confused with the original's 2.x.
  def test_version
    assert_equal "4.0.0", HecklePrism::VERSION
  end

  def test_packages_only_the_library_and_executable
    assert_includes spec.files, "bin/heckle_prism"
    assert_includes spec.files, "lib/heckle_prism.rb"
    assert_includes spec.files, "lib/heckle_prism/version.rb"
    assert_includes spec.files, "README.md"
    assert_includes spec.files, "CHANGELOG.md"
    assert_empty spec.files.grep(%r{\Atest/})
    assert_equal ["heckle_prism"], spec.executables
  end

  def test_runtime_dependencies
    deps = spec.runtime_dependencies.to_h { |dep| [dep.name, dep.requirement.to_s] }

    assert_equal({ "minitest" => ">= 6.1.0", "prism" => ">= 2.0.0" }, deps)
  end

  def test_ruby_floor
    assert_equal ">= 3.4.0", spec.required_ruby_version.to_s
  end

  # The gemspec reads the version without loading prism or minitest.
  def test_version_file_loads_nothing_else
    script = 'require "heckle_prism/version"; p [defined?(Prism), defined?(Minitest), HecklePrism::VERSION]'
    out, err, status = Open3.capture3(RbConfig.ruby, "-I", File.join(ROOT, "lib"), "-e", script)

    assert status.success?, err
    assert_equal "[nil, nil, #{HecklePrism::VERSION.inspect}]\n", out
  end
end
