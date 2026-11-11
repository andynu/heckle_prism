require "minitest/autorun"
require "open3"
require "rbconfig"
require "heckle"

class TestGemspec < Minitest::Test
  ROOT = File.expand_path("..", __dir__)

  def spec
    @spec ||= Dir.chdir(ROOT) { Gem::Specification.load("heckle.gemspec") }
  end

  def test_version_matches_the_library
    assert_equal Heckle::VERSION, spec.version.to_s
  end

  # 3, so this fork's releases are not confused with the original's 2.x.
  def test_version
    assert_equal "3.0.0", Heckle::VERSION
  end

  def test_packages_only_the_library_and_executable
    assert_includes spec.files, "bin/heckle"
    assert_includes spec.files, "lib/heckle.rb"
    assert_includes spec.files, "lib/heckle/version.rb"
    assert_includes spec.files, "README.txt"
    assert_empty spec.files.grep(%r{\Atest/})
    assert_equal ["heckle"], spec.executables
  end

  def test_runtime_dependencies
    deps = spec.runtime_dependencies.to_h { |dep| [dep.name, dep.requirement.to_s] }

    assert_equal({ "minitest" => ">= 5.16.0", "prism" => ">= 1.5.1" }, deps)
  end

  # Ruby 2.7 is the oldest Ruby any prism release installs on.
  def test_ruby_floor
    assert_equal ">= 2.7.0", spec.required_ruby_version.to_s
  end

  # The gemspec reads the version without loading prism or minitest.
  def test_version_file_loads_nothing_else
    script = 'require "heckle/version"; p [defined?(Prism), defined?(Minitest), Heckle::VERSION]'
    out, err, status = Open3.capture3(RbConfig.ruby, "-I", File.join(ROOT, "lib"), "-e", script)

    assert status.success?, err
    assert_equal "[nil, nil, #{Heckle::VERSION.inspect}]\n", out
  end
end
