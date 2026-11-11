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
* Classes defined by a block are heckled like any other. A constant
  assigned a method call with a literal block is treated as a class body
  named by that constant:

      Point = Data.define(:x, :y) do ... end
      Pair = Struct.new(:a, :b) { ... }
      Child = Class.new(Parent) do ... end
      Helpers = Module.new do ... end
      A::B = Struct.new(:v) do ... end

  Any call counts, whatever its receiver or name. Instance methods, "def
  self.name" and "class << self" in the block all work. The mutant is
  evaluated with class_eval inside the enclosing nesting, so a constant
  named in the method resolves as it does in the block, from the
  enclosing module first. A class or module keyword inside such a block
  defines a constant of the enclosing scope, so its methods are not
  found under the block-defined class's name.
* With --fork, each mutant runs in a forked child process and the heckle
  process itself never loads a mutant. See FORK MODE below.
* Each mutant's test run is limited in time and in resident memory, and
  --fork is the mode that can always enforce both. See TIMEOUTS AND
  MEMORY below.
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
    -T, --timeout SECS   time limit per test run, a whole number of seconds;
                         without it the limit is twice the unmutated run,
                         at least 5 seconds
        --memory-limit MB
                         most resident memory a test run may use; 0 turns
                         the limit off. See TIMEOUTS AND MEMORY below
    -F, --force          go on even if the unmutated tests fail
        --fork           run each mutant in a forked child process
    -v, --verbose        show each mutant and the test output

For example, to heckle only the branches of one method against one test
file:

    % heckle Doubler double -b -t test/test_doubler_with_a_number.rb

Each mutant the tests did not catch is printed as a diff against the
original method. The exit status is 0 when no mutant survived and 1
otherwise, or 2 when heckle had to end the process itself (see TIMEOUTS
AND MEMORY).

Each mutant ends one of three ways. It is killed when the tests failed
against it, and it survived when they passed. Otherwise it was not
judged: its test run timed out, went over the memory limit or crashed
in fork mode, the mutant could not be installed or had a syntax error,
or the run was stopped with ^C. A mutant that was not judged gets a warning, followed by the
same diff a survivor gets, so the warning says which mutant it was:

    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    !!! Your tests timed out. Heckle may have caused an infinite loop.
    !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!

    --- original
    +++ mutation
     def tally
       @notes << :tallied
       rows = 0
    -  (1..@entries.size).each { rows += 1 }
    +  (1..nil).each { rows += 1 }
       rows
     end

The lines marked - are the original code and the lines marked + are
what the mutant ran in their place. Here @entries.size was replaced by
nil, which made the range endless.

A timeout is weaker evidence than a failed test: the mutant made the
run slow or endless, and the tests did not necessarily notice it. So
heckle counts timed out mutants apart from killed ones, and like every
mutant that was not judged they are not survivors and do not change
the exit status.

After each method, a line such as "2 of 9 mutants survived" gives the
number of its mutants the tests did not catch and the number heckle ran.
When some of the method's mutants were not judged, a second line says
how many and why:

    1 of 2 mutants survived
    1 timed out

The reasons are "timed out", "ran out of memory" (fork mode, over the
memory limit or out of memory in the child), "crashed" (fork mode: the
test run raised, the child died by a signal or exited with an
unexpected status), "failed to install" (fork mode), "had a syntax
error", "canceled" (^C) and "not run" (in-process, after heckle could
not clean up after an earlier mutant; see TIMEOUTS AND MEMORY). Several
are listed in that order, separated by commas, as in "2 timed out, 1
crashed".

A method with nothing to mutate gets the thick skin warning and no such
lines. The Heckle Results block at the end counts methods (Passed,
Failed and Thick Skin) and then mutants:

    Mutants   :  31 killed, 4 survived

When some mutants were not judged, their counts by reason come between
killed and survived:

    Mutants   : 389 killed, 2 timed out, 81 survived
    Mutants   : 389 killed, 1 timed out, 1 crashed, 81 survived

The figures on the line add up to the number of mutants run across all
the methods heckled. Passed and Failed count methods, so one method with
many survivors shows as one failure there and as many in the mutant
line. A method whose mutants were all killed or not judged counts as
Passed.

Heckle.new takes a reporter as its fourth argument, Heckle::Reporter by
default. A reporter that subclasses Heckle::Reporter can override any
of its methods. One that does not must define every method validate
calls: no_mutations, method_loaded, remaining_mutations, replacing,
report_test_failures, no_failures, failure, no_surviving_mutants,
mutant_totals and not_judged. Two of these differ from heckle 3.0.0.
not_judged(reason, message, original, mutant) is new: it gets each
mutant that was not judged, with its reason (a key of
Heckle::NOT_JUDGED), the warning text and the dedented original and
mutant sources, and it replaces the warning calls validate made for
those mutants. mutant_totals gets a third argument, a hash of counts by
reason, when some of the method's mutants were not judged, and the same
two arguments as before otherwise.

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
without -F. It is 2 when heckle ended the process because a mutant could
not be contained in-process, after a report on standard error.

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
* Mutants run inside the heckle process, or with --fork inside its
  child. Tests that start a new program (a system call, a spawned
  server) run the original code, not the mutant, so they cannot catch
  it.
* A mutant can change state that outlives one test run, such as a
  global, a class variable or a cache, and that change is seen by the
  runs of later mutants. With --fork it is not, since each mutant's
  changes end with its child process: --fork is the mode that keeps
  mutants apart from each other.
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

== TIMEOUTS AND MEMORY:

A mutant can make a method loop forever or allocate without end. Heckle
limits each mutant's test run in time and in resident memory. How
firmly it can hold those limits depends on the mode.

The timeout. Each test run gets -T seconds, or without -T twice the time
of the unmutated run, at least 5 seconds. When it runs over, heckle
raises Heckle::Timeout in it, prints the timeout warning and the
mutant's diff, counts the mutant as timed out and goes on. Heckle::Timeout is an Exception, not a
StandardError, so neither a bare rescue nor "rescue StandardError" in
the code under test catches it, and Minitest lets it through.

After a timeout. Minitest skips the teardown of a test that the timeout
(or ^C) stopped, and leaves the workers of its parallel executor
waiting. Before the next mutant runs, heckle puts the original method
back, then runs that test's teardown hooks quietly, as Minitest runs
them after a failure, and replaces the executor with a fresh one,
killing any of its workers still running a test. Left alone, the
waiting workers would make every later mutant in the process time out
too, and state a teardown resets, such as an open transaction, would
carry into later mutants' tests. Two things heckle cannot clean up in-process: a teardown that
does not finish within the timeout, and a worker that Thread#kill does
not stop (one in a long C call, say). After either, heckle runs no more
mutants in that process. It reports each later one as "Not run", with
the reason and its diff, rather than give a verdict the earlier mutant
may have caused. Run heckle with --fork to judge them.

How a timeout gets lost. Ruby's Timeout raises once and does not raise
again. Heckle::Timeout used to be a StandardError. On a Rails
application, a mutant turned

    (book.first_row(sheet)..book.last_row(sheet)).map do |row|

into an endless range, (book.first_row(sheet)..nil), inside code that
rescued StandardError around the call. The rescue caught the timeout,
the test carried on, and the next test reached the same loop with no
timer. Memory use on the machine grew from 34 GB to 115 GB over about
four hours, until the system's out-of-memory killer ended the whole
terminal session. Code that rescues Exception, or rescues and retries,
can still swallow the timeout, which is what the watchdog is for.

The watchdog. In-process, a thread of heckle's own keeps the deadline.
At the deadline it raises the timeout in the test run, and again every
half second while the run goes on. If the run is still going two
seconds after the first raise, the watchdog writes a report to standard
error, naming the method, the mutant as a diff, that the timeout was
swallowed, and --fork, and ends the process at once with exit status 2.
It does not restore the method, print results or run at_exit handlers.
A test run that returns normally after its timeout was swallowed counts
as timed out, never as a survivor. From the deadline to the end of the
process took 2.1 to 2.5 seconds on Ruby 2.7.8 through 4.0.9.

The memory limit. heckle prints it on the line after "Timeout set to N
seconds.". By default it is the heckle process's resident memory after
the unmutated run, plus the larger of 1024 MB and that amount again.
--memory-limit MB sets it in megabytes of 1048576 bytes, and
--memory-limit 0 turns it off. Resident memory is read from
/proc/PID/status, every 50 milliseconds while a mutant runs, or where
there is no /proc from ps(1), every half second. Where it cannot be
read at all, heckle says once that the limit is not enforced.

In-process, the watchdog reads the heckle process's memory and, over
the limit, writes a report like the one above and ends the process with
exit status 2. In fork mode, heckle reads the child's memory, kills the
child's process group with KILL when it goes over, warns that the
mutant was not counted as a survivor, and goes on with the next one.
Only the child itself is measured, not processes it starts.

On Linux the process that runs the mutant, heckle itself in-process or
the child in fork mode, also lowers its soft RLIMIT_DATA to about 1024
MB above what the limit allows. An allocation that crosses it, such as
one C call asking for gigabytes at once, fails with NoMemoryError
before the polling could see it, and is reported the same way.
Processes the tests start inherit the lowered limit.

With tight allocation loops, against a limit 1 GiB above the starting
memory, resident memory peaked 2 to 298 MB over the limit in-process
and 0 to 149 MB over it in fork mode, on Ruby 2.7.8 through 4.0.9.
In-process the polling thread has to wait for Ruby's global VM lock,
and a long garbage collection holds it.

What in-process mode cannot contain:

* A mutant stuck in one C call that never gives up the global VM lock,
  such as a loop in a C extension or one enormous bignum computation.
  Heckle's own thread cannot run until the call returns, so neither the
  timeout nor the memory polling acts, and if the call never returns,
  heckle never ends. The RLIMIT_DATA backstop still bounds memory, but
  on Ruby 3.2 and 3.3 a process that reaches it with small objects can
  then spin in garbage collection, using a CPU, until it is killed.
* Threads the tests start. A timeout ends the test run in heckle's
  thread, but such a thread keeps running until heckle exits. The
  workers of Minitest's parallelize_me! are the exception: heckle kills
  them after a timeout, and runs no more mutants when one cannot be
  killed.
* State a mutant changes that later mutants see (see Known limits).

--fork contains all of these. The heckle process never runs a mutant,
so it can always stop the child when the child runs over its time or
memory, whatever the child is doing.

== FORK MODE:

    % bundle exec heckle Widget --fork

Fork mode is off unless --fork is given. Without the flag heckle runs
as described above.

With --fork, heckle forks a child process for each mutant. The child
loads the mutant, runs the loaded tests and ends with exit!, so no
at_exit handler (Minitest's, SimpleCov's, a database cleanup) runs in
it. The child reports the outcome only through its exit status. The
heckle process prints the results, survivor diffs, totals and summary
itself, the same as without --fork, and never loads a mutant, so a
mutant cannot change state that later mutants or heckle itself see.

The timeout applies to the child. Each child runs in a process group
of its own, with any processes its tests start. When a child runs
over, heckle sends the group TERM, then KILL a second later if the
child is still running, then KILL to whatever is left of the group, and
prints the usual timeout warning. ^C stops the child's group the same
way. A child that goes over the memory limit is sent KILL at once, with
its group, and a child that runs out of memory gets a warning; both
are counted as "ran out of memory", never as survivors. A child that
ends any other way (an exception out of the test run, an unexpected
exit status, a signal) gets a warning, and its mutant is counted as
"crashed", never as survived. Each of these warnings is followed by
the mutant's diff. Fork mode needs
Process.fork; on a Ruby without it, such as Ruby on Windows, heckle
stops with a one-line message.

Use it when the code under test or its tests keep state from one test
run to the next (globals, class variables, memoized caches,
registries), since without --fork that state carries from one mutant's
run into the next; when a mutant could leave the process broken, for
example by changing something Minitest or heckle uses; and when
heckling heckle (below). Each mutant costs a fork on top of its test
run. On the Rails application mentioned above, one model's 15 mutants
took about 1.45 seconds with --fork and 1.15 seconds without.

Databases. In Rails 8.1 (read in the 8.1.4.1 source), Active Record
registers a callback with ActiveSupport::ForkTracker that discards
every connection pool in a forked child without closing the parent's
connections, so each child opens a connection of its own. For
PostgreSQL the child points the inherited socket at /dev/null instead
of closing it; for SQLite nothing is done. On that Rails 8.1
application with SQLite, --fork reported the same survivors as a run
without it, left the row counts of the test database unchanged, left
no processes behind and did not touch the coverage directory.
PostgreSQL, MySQL and other database servers have not been tried. With
one, each mutant opens a new connection to the server.

Heckling heckle. In the child, the code that decides whether the tests
passed runs after the mutant is loaded. So when heckle heckles its own
methods, a mutant of a method on that path judges itself, and its
result says nothing. Those methods are Heckle#tests_pass?,
Heckle.tests_pass?, Heckle.quietly and Heckle.run_all_suites, and any
tests_pass? a subclass defines. Their mutants still run; treat what
heckle reports for them as unknown. The other methods are judged by
unmutated code: install is already running when its mutant replaces
it, and the outcome is read in the parent.

== REQUIREMENTS:

* Ruby 2.7 or later, which is every Ruby that prism installs on. The
  test suite passes on 2.7.8, 3.0.7, 3.1.7, 3.2.11, 3.3.13, 3.4.12 and
  4.0.9.
* prism 1.5.1 or later. 1.5.1, 1.8.0, 1.8.2, 1.9.0 and 2.1.0 pass the
  test suite; 1.4.0 does not. Ruby 3.3 ships prism 0.19, so a newer
  prism gem is installed there. Before Ruby 3.3 there is no prebuilt
  prism 2 gem and it compiles on install. On Ruby 2.7 the RubyGems and
  Bundler that come with it pick a prebuilt gem that needs Ruby 3.3 and
  stop: use "gem install prism --platform ruby", or set Bundler's
  force_ruby_platform.
* minitest 5.16.0 or later. 5.16.0, 5.21.0, 5.26.1, 5.27.0, 6.0.6 and
  6.1.0 pass the test suite on at least one Ruby. The minitest that
  comes with Ruby 2.7, 3.0 and 3.1 (5.13 to 5.15) is too old, so a newer
  one is installed there. On Ruby 3.4 use minitest 5.25 or later:
  5.16 to 5.20 need mutex_m, which Ruby 3.4 no longer includes.
* With prism 1, a block whose parameter is named "it" loses that
  parameter's mutant on Ruby 3.3 and earlier, because prism 1 reads the
  source as the newest Ruby would. prism 2 reads it as the running Ruby
  does.
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
