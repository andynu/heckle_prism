require_relative "lib/heckle/version"

Gem::Specification.new do |spec|
  spec.name = "heckle"
  spec.version = Heckle::VERSION
  spec.authors = ["Ryan Davis", "Pete Higgins"]
  spec.license = "MIT"

  spec.summary = "Heckle is unit test sadism(tm) at its core."
  spec.description = <<~TEXT.tr("\n", " ").strip
    Heckle is a mutation tester. It modifies your code and runs your tests
    to make sure they fail. The idea is that if code can be changed and your
    tests don't notice, either that code isn't being covered or it doesn't
    do anything.
  TEXT

  # The oldest Ruby any prism release installs on.
  spec.required_ruby_version = ">= 2.7.0"

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z lib bin README.txt History.txt`.split("\x0")
  end
  spec.bindir = "bin"
  spec.executables = ["heckle"]
  spec.require_paths = ["lib"]

  spec.add_dependency "prism", ">= 1.5.1"
  # Minitest.seed, which the in-process run reads, arrived in 5.16.0.
  spec.add_dependency "minitest", ">= 5.16.0"
end
