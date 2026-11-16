# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

Versions 3.0.0 and 3.0.1 were bridge versions during the rewrite, still
named heckle. They were never published and exist only as tags of this
repository. Versions 2.0.0.b1 and earlier are versions of the original
heckle by Ryan Davis, Kevin Clark and contributors, recorded here as that
project's History.txt recorded them.

## [Unreleased]

### Added

- LICENSE. Code written for heckle_prism is dedicated to the public
  domain under CC0 1.0; the parts from heckle stay under its MIT License.
- A Provenance section in the README.

### Changed

- README.txt is now README.md, and History.txt is now this file.
- The gemspec names heckle_prism's author and homepage instead of
  heckle's.

## [4.0.0] - 2026-11-16

### Changed

- Renamed the gem and executable to heckle_prism, the class to
  HecklePrism and lib/heckle to lib/heckle_prism.
- Requires Ruby 3.4, prism 2.0 and minitest 6.1 or later.

### Removed

- Support for Ruby 2.7 to 3.3, prism 1, minitest 5 and minitest 6.0.
  Use the v3.0.1 tag for those.

## [3.0.1] - 2026-11-11

### Added

- Mutants that were not judged (timed out, ran out of memory, crashed,
  failed to install, had a syntax error, canceled, not run) are counted
  apart from killed and survived, per method and in the results.
- Every warning for a mutant that was not judged is followed by that
  mutant's diff.
- Reporter#not_judged, and a third argument to Reporter#mutant_totals
  with the counts by reason.
- After a timeout, heckle runs the teardown hooks Minitest skipped and
  replaces Minitest's parallel executor before the next mutant.

### Changed

- In-process, once heckle cannot clean up after a timeout it runs no
  more mutants and reports each later one as not run.

### Fixed

- A run with mutants that were not run no longer reports success.

## [3.0.0] - 2026-11-11

### Added

- Class methods, named as "self.name", including defs inside
  "class << self".
- Classes defined by a block (Data.define, Struct.new, Class.new,
  Module.new and any other call with a literal block assigned to a
  constant).
- `--fork`, which runs each mutant in a forked child process.
- A watchdog that ends the process when the code under test swallows
  the timeout.
- `--memory-limit`, a resident memory limit per test run in both modes,
  backed by a lowered RLIMIT_DATA on Linux.
- Mutant totals per method and for the whole run.
- `-t` can be repeated.
- A gemspec, so projects can use heckle by Gemfile path.

### Changed

- Rebuilt on Prism. A mutation is a splice of the original source,
  evaluated in the method's original module and class nesting.
- Tests are plain Minitest, run in-process.
- The default test pattern is test/**/test_*.rb and test/**/*_test.rb.
- Private and protected methods keep their visibility while mutated.
- Methods defined outside the project are left out of whole-class runs.
- A SimpleCov started by the tests no longer writes its report.
- Heckle::Timeout is an Exception, not a StandardError.
- Standard output is unbuffered, and heckle exits 1 when it is closed
  mid-run.
- Random replacements come from heckle's own generator, and random
  strings are printable ASCII.
- A timeout must be a positive whole number of seconds.
- Requires Ruby 2.7, prism 1.5.1 and minitest 5.16 or later.

### Removed

- ruby_parser, ruby2ruby, sexp_processor and Hoe.
- The Test::Unit heckler, the autotest plugin and the sample project.
- `-f`, `--focus`. Choose the tests to load with `-t` instead.

### Fixed

- The original method is restored when installing a mutant raises.

## 2.0.0.b1 - 2012-10-02

Prepared for release in the original repository but not published as a
gem.

### Added

- Ruby 1.9 support (phiggins).

### Changed

- Works with ruby_parser (phiggins).

### Fixed

- Ruby2Ruby usage (raggi).
- Dependencies, so heckle doesn't use ruby_parser 3 and friends.
- Grammar in the description. Reported by Jean Lange.

## [1.4.3] - 2009-06-23

### Added

- autotest/heckle plugin.

### Changed

- Testing is skipped on 1.9.

## [1.4.2] - 2009-02-08

### Fixed

- Ruby2Ruby dependency and references (name changed). Reported by David
  Chelimsky.
- Bug #11435, where [:iter, [:call], ...] caused an endless loop.
  Reported by Thomas Preymesser.

## [1.4.1] - 2007-06-05

### Fixed

- zentest added as a heckle dependency. Closes #10996.
- Heckling of calls with blocks.
- test_unit_heckler's test_pass? returns the result of the run rather
  than ARGV.clear.

## [1.4.0] - 2007-05-18

### Added

- Method calls are heckled (by removal).
- Assignments are heckled (by value changing).
- `--focus` to specify the unit tests to run.
- `-n` and `-x` to include or exclude nodes.
- `--assignments` to test only assignments.

## [1.3.0] - 2007-02-12

### Added

- Unified diffs for mutated methods.
- Exit status 1 on failure.
- A simple report at the end.

### Changed

- Runs are sorted by method.
- Rails is detected and the test pattern changed to suit it.

### Fixed

- Aborts when an unknown method is supplied.
- Slashes in random regexps are escaped.

## [1.2.0] - 2007-01-15

### Added

- A timeout for tests, set dynamically and overridable with `-T`.
- Class method support with "self.method_name".
- `-b` to heckle branches only.

### Changed

- Restructured the class hierarchy and removed Base and others.
- Revamped the tests and reduced their size by 60%.

### Fixed

- The infinite loop caused by syntax errors.

## [1.1.1] - 2006-12-20

### Fixed

- Tests load properly when a method name is supplied.
- Random symbols have at least one character.
- Removed all extra warnings from the unit tests.

## [1.1.0] - 2006-12-19

### Added

- Rolls back the original method after processing.
- Mutates numeric literals, strings, true and false, if/unless,
  while/until, regexes, ranges and symbols.
- Mutates one node at a time.
- Runs against entire classes.
- Command line options.

### Changed

- Decoupled from Test::Unit.
- Cleaner output.

## [1.0.0] - 2006-10-22

### Added

- First release.

[unreleased]: https://github.com/andynu/heckle_prism/compare/v4.0.0...HEAD
[4.0.0]: https://github.com/andynu/heckle_prism/compare/v3.0.1...v4.0.0
[3.0.1]: https://github.com/andynu/heckle_prism/compare/v3.0.0...v3.0.1
[3.0.0]: https://github.com/andynu/heckle_prism/tree/v3.0.0
[1.4.3]: https://rubygems.org/gems/heckle/versions/1.4.3
[1.4.2]: https://rubygems.org/gems/heckle/versions/1.4.2
[1.4.1]: https://rubygems.org/gems/heckle/versions/1.4.1
[1.4.0]: https://rubygems.org/gems/heckle/versions/1.4.0
[1.3.0]: https://rubygems.org/gems/heckle/versions/1.3.0
[1.2.0]: https://rubygems.org/gems/heckle/versions/1.2.0
[1.1.1]: https://rubygems.org/gems/heckle/versions/1.1.1
[1.1.0]: https://rubygems.org/gems/heckle/versions/1.1.0
[1.0.0]: https://rubygems.org/gems/heckle/versions/1.0.0
