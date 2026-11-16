require_relative "lib/heckle_prism/version"

Gem::Specification.new do |spec|
  spec.name = "heckle_prism"
  spec.version = HecklePrism::VERSION
  spec.authors = ["Andy Nutter-Upham"]
  # The new code is CC0 (see LICENSE), but every copy carries heckle's MIT
  # notice, so MIT is the license that governs the gem as a whole.
  spec.license = "MIT"
  spec.homepage = "https://github.com/andynu/heckle_prism"
  spec.metadata = {
    "source_code_uri" => spec.homepage,
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md",
    "bug_tracker_uri" => "#{spec.homepage}/issues"
  }

  spec.summary = "A mutation tester for Minitest, built on Prism."
  spec.description = <<~TEXT.tr("\n", " ").strip
    heckle_prism is a mutation tester. It modifies your code and runs your
    tests to make sure they fail. If code can be changed and your tests don't
    notice, either that code isn't being covered or it doesn't do anything.
    It is a Prism rewrite of heckle by Ryan Davis and Kevin Clark, written by
    Claude (Fable 5.2) under the direction of Andy Nutter-Upham. The original
    authors were not involved in it.
  TEXT

  spec.required_ruby_version = ">= 3.4.0"

  spec.files = Dir.chdir(__dir__) do
    `git ls-files -z lib bin README.md CHANGELOG.md LICENSE`.split("\x0")
  end
  spec.bindir = "bin"
  spec.executables = ["heckle_prism"]
  spec.require_paths = ["lib"]

  spec.add_dependency "prism", ">= 2.0.0"
  # 6.0.x requires prism ~> 1.5, so 6.1.0 is the oldest that loads beside prism 2.
  spec.add_dependency "minitest", ">= 6.1.0"
end
