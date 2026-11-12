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

  spec.required_ruby_version = ">= 3.4.0"

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z lib bin README.txt History.txt`.split("\x0")
  end
  spec.bindir = "bin"
  spec.executables = ["heckle"]
  spec.require_paths = ["lib"]

  spec.add_dependency "prism", ">= 2.0.0"
  # 6.0.x requires prism ~> 1.5, so 6.1.0 is the oldest that loads beside prism 2.
  spec.add_dependency "minitest", ">= 6.1.0"
end
