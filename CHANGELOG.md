# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/).

heckle_prism began as a fork of heckle 2.0.0.b1, so 3.0.0 lists its
changes from that version. For heckle's own history, see
https://github.com/seattlerb/heckle. Versions 3.0.0 and 3.0.1 were bridge
versions during the rewrite, still named heckle. They were never
published and exist only as tags of this repository.

## [Unreleased]

### Added

- LICENSE. Code written for heckle_prism is dedicated to the public
  domain under CC0 1.0; the parts from heckle stay under its MIT License.
- A Provenance section in the README.

### Changed

- README.txt is now README.md, and History.txt is now this file.
- The gemspec names heckle_prism's author and homepage instead of
  heckle's.
- A renamed assignment target or block parameter is now named _heckled
  (or @_heckled, $_heckled, @@_heckled) instead of _heckle_dummy.

### Removed

- heckle's entries from this file, and heckle's commits from the
  repository's history.

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

[unreleased]: https://github.com/andynu/heckle_prism/compare/v4.0.0...HEAD
[4.0.0]: https://github.com/andynu/heckle_prism/compare/v3.0.1...v4.0.0
[3.0.1]: https://github.com/andynu/heckle_prism/compare/v3.0.0...v3.0.1
[3.0.0]: https://github.com/andynu/heckle_prism/tree/v3.0.0
