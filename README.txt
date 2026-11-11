= heckle

home :: http://ruby.sadi.st/Heckle.html
code :: https://github.com/seattlerb/heckle
rdoc :: http://seattlerb.rubyforge.org/heckle

== DESCRIPTION:

Heckle is unit test sadism(tm) at its core. Heckle is a mutation tester. It modifies your code and runs your tests to make sure they fail. The idea is that if code can be changed and your tests don't notice, either that code isn't being covered or it doesn't do anything.

It's like hiring a white-hat hacker to try to break into your server and making sure you detect it. You learn the most by trying to break things and watching the outcome in an act of unit test sadism.

== FEATURES/PROBLEMS:

* Heckles a single method or every method a class defines itself.
* Class methods work: name them as "self.name". Both "def self.name" and
  defs inside "class << self" are found.
* Private and protected methods keep their visibility while mutated.
* Each mutant is evaluated inside the method's original module and class
  nesting, so constant lookup behaves as it does in your file.
* Tests are plain Minitest, run in-process. Other test frameworks are not
  supported.
* Mutation kinds (the names the -n and -x flags take):
  * true, false: true becomes false and false becomes true.
  * lit: integers and floats change by a random amount. Symbols, regexes
    without interpolation, and ranges with integer ends become random ones.
  * str: string literals become a random string. Heredocs and parts of
    interpolated strings are left alone.
  * if: an if or unless swaps its branches. Ternaries and if/elsif chains
    negate the condition instead.
  * while, until: each becomes the other.
  * call: a method call is replaced by nil.
  * iter: a method call with a block is replaced by nil.
  * lasgn, iasgn, gasgn, cvasgn: an assignment to a local, instance, global
    or class variable gets nil as its value (42 when the value was already
    nil). Targets of multiple assignment, for loops and "rescue => e", and
    block parameters, are renamed so the value goes nowhere.
  * dasgn and dasgn_curr are still accepted as names for lasgn.
* Constants, super, yield, method parameters, nil and self are not mutated.

== SYNOPSIS:

Run heckle from the root of your project. It loads the files matching the
test pattern (test/**/test_*.rb and test/**/*_test.rb by default) with
lib and test on the load path, so your tests must require the code they
test. The unmutated tests are run once first and must pass.

    % heckle Doubler                  # every method Doubler defines
    % heckle Doubler double           # one instance method
    % heckle Tally self.start         # one class method
    % heckle Name::Spaced::Class meth # nested names are fine

Main options:

    -t, --tests PATTERN  test files to load (a glob); repeat it to load
                         several patterns. Any -t replaces the default
                         patterns, and each one given must match a file
    -n, --nodes KINDS    only these mutation kinds, comma separated
    -x, --exclude-nodes KINDS
                         every kind except these
    -b, --branches       only if, while and until
        --assignments    only the assignment kinds
    -T, --timeout SECS   time limit per test run; without it the limit is
                         twice the unmutated run, at least 5 seconds
    -F, --force          go on even if the unmutated tests fail
    -v, --verbose        show each mutant and the test output

For example, to heckle only the branches of one method against one test
file:

    % heckle Doubler double -b -t test/test_doubler_with_a_number.rb

Each mutant the tests did not catch is printed as a diff against the
original method. The exit status is 0 when every mutant was caught and 1
otherwise.

After each method, a line such as "2 of 9 mutants survived" gives the
number of its mutants the tests did not catch and the number heckle ran.
A method with nothing to mutate gets the thick skin warning and no such
line. The Heckle Results block at the end counts methods (Passed, Failed
and Thick Skin) and then mutants:

    Mutants   :  31 killed, 4 survived

A mutant counts as killed when it was run and did not survive: the tests
failed or raised, timed out, or the mutant raised a SyntaxError when
installed. Killed plus survived is the number of mutants run across all
the methods heckled. Passed and Failed count methods, so one method with
many survivors shows as one failure there and as many in the mutant
line.

== USING HECKLE IN A PROJECT:

This version of heckle is not published as a gem. Add it to the
project's Gemfile by path:

    gem "heckle", path: "/path/to/heckle", group: :test

Run bundle install, then run heckle with bundle exec from the project
root:

    % bundle exec heckle Widget                # every method Widget defines
    % bundle exec heckle Widget label          # one instance method
    % bundle exec heckle Widget self.restock   # one class method

Every mutant runs every loaded test, so the time a heckle run takes is
the number of mutants times the time of the whole loaded suite. Use -t
to load only the tests that cover the class:

    % bundle exec heckle Widget -t test/models/widget_test.rb

When the tests that cover the class live in more than one file, give -t
once per pattern:

    % bundle exec heckle Widget -t test/models/widget_test.rb -t 'test/jobs/widget_*_test.rb'

The run time is the per-mutant cost of the loaded tests, not of the
method being heckled. A suite whose tests each make round trips to a
remote test database stays bound by those round trips however few
mutants the method has, which is another reason to narrow the run with
-t.

The exit status is 0 when no mutant survived, which includes a class or
method with nothing to mutate. It is 1 when at least one mutant
survived, and also on a usage error or when the unmutated tests fail
without -F.

Rails works. It was tried on a Rails 8.1 application with SQLite and the
default minitest setup: all three forms above ran, the suite did not
run again at exit, and rows created by tests were rolled back between
mutant runs as they are in rails test. The parallelize line was removed
from test/test_helper.rb first, and heckle has not been tried with it.
When heckling a whole class, heckle leaves out methods whose source is
outside the project directory, such as the ones Rails generates in a
model (self.__class_attr___callbacks and the like); -v lists them. A
method defined inside the project without def, such as an
attr_accessor, gets a "Skipping" line.

SimpleCov can stay in test/test_helper.rb. After loading the tests,
heckle sets SimpleCov.external_at_exit when SimpleCov is loaded, which
turns off the report SimpleCov writes at exit. A heckle run then leaves
the coverage directory as it was and prints nothing from SimpleCov.
This holds for simplecov 0.19 and later (checked through 1.3.2).
Heckle does not require simplecov and does nothing when it is not
loaded.

Known limits:

* Only methods written with def are heckled. Methods made by
  define_method, attr_accessor, class_attribute and similar are skipped.
* Mutants run inside the heckle process. Tests that start a subprocess
  (a system call, a forked server) run the original code, not the
  mutant, so they cannot catch it.
* A mutant can change state that outlives one test run, such as a
  global, a class variable or a cache, and that change is seen by the
  runs of later mutants.
* Equivalent mutants are reported like any other survivor. A mutant
  that changes the code without changing what the method does cannot be
  caught by any test, and heckle cannot tell it apart from a gap in the
  tests. Two patterns seen in a real project:
  * A guard made redundant by a later guard. In

        return [] if text.blank?
        return [] unless text.match?(/\d/)

    replacing text.blank? with nil survives for any string, because
    blank text has no digit and the second line returns [] for it.
  * A method wrapped in "rescue StandardError". A mutant of a guard
    before the rescue (its condition replaced by nil, or its if turned
    into unless) often makes later code raise. When the rescue returns
    the value the guard would have returned, the mutant survives, so
    the rescue hides the mutants of the guards ahead of it.
* Only method bodies are mutated. Constants are not, so data held in
  constants, such as a hash of regexes or a lookup table, is never
  changed, even when the methods that use it are heckled. A survivor
  count of zero says nothing about whether the tests check that data.

== REQUIREMENTS:

* Ruby 4.0.9. Older Rubies have not been tried.
* prism 1.5.1 or later. 1.5.1, 1.8.0, 1.8.2, 1.9.0 and 2.1.0 pass the
  test suite; 1.4.0 does not.
* minitest 5.27.0 or later. 5.27.0, 6.0.6 and 6.1.0 pass the test suite.
* diff(1) on the PATH, which prints each surviving mutant against the
  original method

ruby2ruby, ParseTree and ruby_parser are no longer used.

== INSTALL:

* Add the Gemfile line under USING HECKLE IN A PROJECT, or run
  bin/heckle from a checkout.

== LICENSE:

(The MIT License)

Copyright (c) Ryan Davis, seattle.rb, and Kevin Clark

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
'Software'), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED 'AS IS', WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT.
IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY
CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT,
TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE
SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
