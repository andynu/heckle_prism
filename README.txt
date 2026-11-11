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
test pattern (test/test_*.rb by default) with lib and test on the load
path, so your tests must require the code they test. The unmutated tests
are run once first and must pass.

    % heckle Doubler                  # every method Doubler defines
    % heckle Doubler double           # one instance method
    % heckle Tally self.start         # one class method
    % heckle Name::Spaced::Class meth # nested names are fine

Main options:

    -t, --tests PATTERN  test files to load (a glob)
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

== REQUIREMENTS:

* Ruby with Prism 2.1 or later
* minitest 6.1 or later
* diff(1) on the PATH, which prints each surviving mutant against the
  original method

ruby2ruby, ParseTree and ruby_parser are no longer used.

== INSTALL:

* gem install heckle

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
