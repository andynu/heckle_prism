require "prism"
require "tempfile"
require "minitest"
require "heckle/version"
require "heckle/method_finder"
require "heckle/mutation"
require "heckle/mutator"
require "heckle/forking"
require "heckle/memory"
require "heckle/watchdog"

##
# Test Unit Sadism

class Heckle

  # Minitest records any other exception as a test error, which would spend
  # the timeout on one test and let the next one loop forever.
  Minitest::Test::PASSTHROUGH_EXCEPTIONS << Timeout

  ##
  # Raised when the method to heckle, or its source, cannot be found.

  class SourceNotFound < StandardError; end

  ##
  # All mutation kinds Heckle knows. The names are the legacy node names.

  MUTATABLE_NODES = [:call, :cvasgn, :false, :gasgn, :iasgn, :if, :iter, :lasgn,
                     :lit, :str, :true, :until, :while].freeze

  ##
  # Old kind names still accepted. Prism has no separate block-local assignment.

  NODE_ALIASES = { dasgn: :lasgn, dasgn_curr: :lasgn }.freeze

  ##
  # Branch node types.

  BRANCH_NODES = [:if, :until, :while].freeze

  ##
  # All assignment nodes that can be mutated by Heckle.

  ASGN_NODES = [:cvasgn, :gasgn, :iasgn, :lasgn].freeze

  ##
  # diff(1) executable

  DIFF = "diff"

  ##
  # Mutation count

  attr_reader :count

  ##
  # Mutations that caused failures

  attr_accessor :failures

  ##
  # Class being heckled

  attr_reader :klass

  ##
  # Name of class being heckled

  attr_reader :klass_name

  ##
  # Name of method being heckled

  attr_reader :method_name

  @@debug = false
  @@guess_timeout = true
  @@timeout = 60 # default to something longer (can be overridden by runners)
  @@fork = false
  @@memory_limit = nil

  def self.debug
    @@debug
  end

  def self.debug=(value)
    @@debug = value
  end

  def self.timeout
    @@timeout
  end

  def self.timeout=(value)
    @@timeout = value
    @@guess_timeout = false # We've set the timeout, don't guess
  end

  def self.guess_timeout?
    @@guess_timeout
  end

  ##
  # True when validate runs each mutant in a forked child.

  def self.fork?
    @@fork
  end

  def self.fork=(value)
    @@fork = value
  end

  ##
  # The most resident memory, in bytes, a mutant's test run may use, or
  # nil for no limit. In-process the limit applies to the heckle process,
  # in fork mode to each child.

  def self.memory_limit
    @@memory_limit
  end

  def self.memory_limit=(bytes)
    @@memory_limit = bytes
  end

  ##
  # Loads the test files at +paths+. A <tt>require "minitest/autorun"</tt>
  # in them does not schedule a run at exit: Heckle runs the suite itself.

  def self.load_tests(paths)
    # Minitest.autorun installs its at_exit hook only while this is false.
    Minitest.class_variable_set(:@@installed_at_exit, true)
    paths.each { |path| require File.expand_path(path) }
    leave_coverage_alone
  end

  ##
  # A SimpleCov started by the tests would write its report at exit and
  # replace the project's own with the coverage of a heckle run. Setting
  # external_at_exit (simplecov 0.19 and later) makes its at_exit hook do
  # nothing.

  def self.leave_coverage_alone
    return unless defined?(::SimpleCov) && ::SimpleCov.respond_to?(:external_at_exit=)

    ::SimpleCov.external_at_exit = true
  end
  private_class_method :leave_coverage_alone

  ##
  # Creates a new Heckle that will heckle +klass_name+ and +method_name+,
  # sending results to +reporter+. +method_name+ is "foo" for an instance
  # method and "self.foo" for a class method.

  def initialize(klass_name, method_name,
                 nodes = Heckle::MUTATABLE_NODES, reporter = Reporter.new)
    @klass_name = klass_name.to_s
    @method_name = method_name.to_sym
    @reporter = reporter
    @nodes = resolve_nodes(nodes)

    @count = 0
    @failures = []

    @klass = resolve_class
    @name = @method_name.to_s.delete_prefix("self.").to_sym
    @owner = @method_name.to_s.start_with?("self.") ? @klass.singleton_class : @klass
    @original_method = resolve_method
    @file, @line = @original_method.source_location
    @found = locate_source
    @visibility = visibility
    @installed = false
  end

  ##
  # The mutations of the method restricted to the requested kinds, keeping
  # only those whose mutant still parses. Computed once per instance, so the
  # random replacements stay fixed.

  def mutations
    @mutations ||= Mutator.new(self).mutations_for(def_node)
      .select { |mutation| @nodes.include?(mutation.kind) }
      .select { |mutation| Prism.parse(mutant_source(mutation)).success? }
  end

  ##
  # The source text of the method's def.

  def original_source
    def_node.slice
  end

  ##
  # The def's source text with +mutation+ applied.

  def mutant_source(mutation)
    mutation.apply(original_source, def_node.location.start_offset)
  end

  ##
  # Replaces the live method with the mutant for +mutation+. The def is
  # evaluated inside its original lexical nesting, at its original file and
  # line, so constant lookup and backtraces match the original. Visibility
  # is preserved.

  def install(mutation)
    # Built while the original method is live: heckling Heckle itself
    # replaces methods that building the source calls.
    source, line = install_source(mutation)

    remove_live_method
    # Set before the eval, so restore puts the original back if it raises.
    @installed = true
    eval(source, TOPLEVEL_BINDING, @file, line)
    @owner.send(@visibility, @name)
  end

  ##
  # Puts the original method back. Does nothing unless a mutant is installed.

  def restore
    return unless @installed

    remove_live_method
    @owner.send(:define_method, @name, @original_method)
    @owner.send(@visibility, @name)
    @installed = false
  end

  ##
  # Runs the tests against whatever is installed. Override for another test
  # framework.

  def tests_pass?
    self.class.tests_pass?
  end

  ##
  # Runs every loaded Minitest runnable in-process and returns true when all
  # passed (skips count as passing). Silent unless Heckle.debug.

  def self.tests_pass?
    Minitest.seed ||= Random.new_seed % 0xFFFF
    options = { seed: Minitest.seed, args: "--seed #{Minitest.seed}" }

    quietly do
      reporter = Minitest::CompositeReporter.new
      if @@debug
        reporter << Minitest::SummaryReporter.new($stdout, options)
        reporter << Minitest::ProgressReporter.new($stdout, options)
      else
        reporter << Minitest::StatisticsReporter.new(nil, options)
      end

      # The same sequence as Minitest.run, without argument parsing or plugins.
      executor = Minitest.parallel_executor
      executor.start if executor.respond_to?(:start)
      reporter.start
      run_all_suites(reporter, options)
      executor.shutdown if executor.respond_to?(:shutdown)
      reporter.report

      reporter.passed?
    end
  end

  # Minitest 6 renamed Minitest.__run to Minitest.run_all_suites.
  def self.run_all_suites(reporter, options)
    if Minitest.respond_to?(:run_all_suites)
      Minitest.run_all_suites(reporter, options)
    else
      Minitest.__run(reporter, options)
    end
  end
  private_class_method :run_all_suites

  def self.quietly
    return yield if @@debug

    stdout, stderr = $stdout, $stderr
    File.open(File::NULL, "w") do |null|
      $stdout = $stderr = null
      yield
    ensure
      $stdout, $stderr = stdout, stderr
    end
  end
  private_class_method :quietly

  ##
  # Runs the tests against each mutant in turn. Returns nil when there is
  # nothing to mutate, true when every mutant was killed, false otherwise.
  # Any exception other than SyntaxError, a timeout or Interrupt propagates,
  # with the original method restored. In fork mode the tests' exceptions
  # stay in the child, which is warned about and not counted a survivor.
  # In-process, a test run that swallows its timeout ends the process
  # (see Watchdog).

  def validate
    @count = 0
    @failures = []

    if mutations.empty? then
      @reporter.no_mutations(klass_name, method_name)
      return
    end

    @reporter.method_loaded(klass_name, method_name, mutations.size)

    mutations.each_with_index do |mutation, index|
      @reporter.remaining_mutations(mutations.size - index)
      # Survivor text is taken before install, for the same reason as there.
      @current_mutant = mutant_source(mutation)
      begin
        if @@debug
          @reporter.replacing(klass_name, method_name,
                              dedent(original_source), dedent(@current_mutant))
        end

        @count += 1
        if @@fork then
          run_forked mutation
        else
          reports = [swallowed_timeout_report, memory_report]
          install mutation
          run_tests(*reports)
        end
      rescue SyntaxError => e
        @reporter.warning "Mutation caused a syntax error:\n\n#{e.message}"
      rescue Heckle::Timeout
        @reporter.warning "Your tests timed out. Heckle may have caused an infinite loop."
      rescue Interrupt
        @reporter.warning 'Mutation canceled, hit ^C again to exit'
        sleep 2
      ensure
        restore
      end
    end

    unless @failures.empty?
      @reporter.no_failures
      @failures.each do |failure|
        @reporter.failure(dedent(original_source), dedent(failure))
      end
      @reporter.mutant_totals(@failures.size, @count)
      false
    else
      @reporter.no_surviving_mutants
      @reporter.mutant_totals(0, @count)
      true
    end
  end

  ##
  # Returns a random nonzero Integer from -100 to 100.

  def rand_number
    (rand(100) + 1)*((-1)**rand(2))
  end

  ##
  # Returns a random String of 0 to 49 printable ASCII characters (space
  # through tilde), so survivor diffs stay readable.

  def rand_string
    size = rand(50)
    str = +""
    size.times { str << (32 + rand(95)).chr }
    str
  end

  ##
  # Returns a random Symbol

  def rand_symbol
    letters = ('a'..'z').to_a + ('A'..'Z').to_a
    str = +""
    (rand(50) + 1).times { str << letters[rand(letters.size)] }
    :"#{str}"
  end

  ##
  # Returns a random Range

  def rand_range
    min = rand(50)
    max = min + rand(50)
    min..max
  end

  class Reporter
    def no_mutations(klass_name, method_name)
      warning "#{klass_name}\##{method_name} has a thick skin. There's nothing to heckle."
    end

    def method_loaded(klass_name, method_name, mutations_left)
      info "#{klass_name}\##{method_name} loaded with #{mutations_left} possible mutations"
    end

    def remaining_mutations(mutations_left)
      puts "#{mutations_left} mutations remaining..."
    end

    def warning(message)
      puts "!" * 70
      puts "!!! #{message}"
      puts "!" * 70
      puts
    end

    def info(message)
      puts "*"*70
      puts "***  #{message}"
      puts "*"*70
      puts
    end

    def no_failures
      puts
      puts "The following mutations didn't cause test failures:"
      puts
    end

    def diff(original, mutation)
      length = [original.split(/\n/).size, mutation.split(/\n/).size].max

      Tempfile.open("orig") do |a|
        a.puts(original)
        a.flush

        Tempfile.open("fail") do |b|
          b.puts(mutation)
          b.flush

          output = `#{Heckle::DIFF} -U #{length} --label original #{a.path} --label mutation #{b.path}`
          puts output.sub(/^@@.*?\n/, '')
          puts
        end
      end
    end

    def failure(original, failure)
      self.diff original, failure
    end

    def no_surviving_mutants
      puts "No mutants survived. Cool!\n\n"
    end

    def mutant_totals(survived, total)
      puts "#{survived} of #{total} mutants survived"
      puts
    end

    def replacing(klass_name, method_name, original, src)
      puts "Replacing #{klass_name}##{method_name} with:\n\n"
      diff(original, src)
    end

    def report_test_failures
      puts "Tests failed -- this is good" if Heckle.debug
    end
  end

  private

  # The source for the rand_* methods. Not Kernel#rand: Minitest reseeds
  # the global generator on every suite run, which would repeat the same
  # replacements for each method heckled after one.
  def rand(max)
    (@random ||= Random.new).rand(max)
  end

  # Once the timeout has fired the outcome says nothing, even if the code
  # under test swallowed it and the tests went on to pass.
  # Under a memory limit, a NoMemoryError out of the tests is the
  # backstop failing an allocation, and ends the process as polling does.
  def run_tests(report, memory_report)
    Memory.backstop(@@memory_limit) if @@memory_limit
    watchdog = Watchdog.new(@@timeout, report, memory_limit: @@memory_limit, memory_report: memory_report)
    passed = begin
      watchdog.watch { tests_pass? }
    rescue NoMemoryError
      raise unless @@memory_limit

      Watchdog.end_process(memory_report.call(nil))
    end
    raise Heckle::Timeout if watchdog.fired?

    if passed then
      record_passing_mutation
    else
      @reporter.report_test_failures
    end
  end

  # The reports are built before install, so the watchdog writes them
  # while the mutant runs without calling code the mutant may replace.
  def swallowed_timeout_report
    <<~TEXT
      heckle: #{klass_name}##{method_name}: the tests were still running #{Watchdog::GRACE} seconds
      after the #{@@timeout} second timeout was raised in them. The code under test
      swallowed the timeout, with a rescue of Exception or a retry, say.
      #{ended_the_process}
      #{plain_diff(dedent(original_source), dedent(@current_mutant))}
      Run heckle with --fork to contain a mutant like this one: each mutant
      then runs in a child process, which heckle kills when it runs over.
    TEXT
  end

  # Called with the resident memory in bytes, or nil when an allocation
  # failed at the backstop.
  def memory_report
    head = "heckle: #{klass_name}##{method_name}: the tests went over the memory limit of #{megabytes(@@memory_limit)}"
    tail = <<~TEXT
      #{ended_the_process}
      #{plain_diff(dedent(original_source), dedent(@current_mutant))}
      Run heckle with --fork to contain a mutant like this one: each mutant
      then runs in a child process, which heckle kills when it goes over
      the limit. --memory-limit MB sets the limit, and 0 turns it off.
    TEXT
    lambda do |resident|
      seen = resident ? "resident memory #{megabytes(resident)}" : "an allocation failed under the limit heckle sets"
      "#{head}\n(#{seen}).\n#{tail}"
    end
  end

  def ended_the_process
    "Heckle ended the process without restoring the method, printing\n" \
      "results or running at_exit handlers. The mutant:\n"
  end

  def megabytes(bytes)
    "#{bytes.to_i / Memory::MB} MB"
  end

  # Both texts in full, as "diff -U" with the whole text as context shows
  # a mutation, which changes one run of lines. Needs no diff(1) process.
  def plain_diff(original, mutant)
    before = original.split("\n")
    after = mutant.split("\n")
    shorter = [before.size, after.size].min
    head = 0
    head += 1 while head < shorter && before[head] == after[head]
    tail = 0
    tail += 1 while tail < shorter - head && before[-1 - tail] == after[-1 - tail]

    lines = ["--- original", "+++ mutation"]
    lines.concat(before.first(head).map { |line| " #{line}" })
    lines.concat(before[head...(before.size - tail)].map { |line| "-#{line}" })
    lines.concat(after[head...(after.size - tail)].map { |line| "+#{line}" })
    lines.concat(before.last(tail).map { |line| " #{line}" })
    lines.join("\n") + "\n"
  end

  def record_passing_mutation
    @failures << @current_mutant
  end

  def def_node
    @found.def_node
  end

  # For display only. Strips the def line's leading whitespace from each
  # later line that starts with it; other lines (string or heredoc content
  # indented less than the def) are left as they are.
  def dedent(source)
    indent = def_node.location.start_line_slice[/\A[ \t]*/]
    return source if indent.empty?

    source.gsub(/\n#{Regexp.escape(indent)}/, "\n")
  end

  def not_found(reason)
    raise SourceNotFound, "#{klass_name}##{method_name}: #{reason}"
  end

  def resolve_nodes(nodes)
    nodes.map do |node|
      kind = NODE_ALIASES.fetch(node.to_sym, node.to_sym)
      raise ArgumentError, "unknown mutation kind: #{node}" unless MUTATABLE_NODES.include?(kind)

      kind
    end.uniq
  end

  def resolve_class
    found = klass_name.split("::").inject(Object) { |scope, name| scope.const_get(name, false) }
    not_found("#{klass_name} is not a class or module") unless found.is_a?(Module)

    found
  rescue NameError
    not_found("no such class #{klass_name}")
  end

  # The live method must be defined by the class itself, since only that
  # definition is located in source and replaced.
  def resolve_method
    method = @owner.instance_method(@name)
    unless method.owner == @owner
      not_found("no such method in #{klass_name} itself; it is defined by #{method.owner}")
    end

    method
  rescue NameError
    not_found("no such method")
  end

  def locate_source
    not_found("no source location") unless @file
    not_found("source file #{@file} is not readable") unless File.file?(@file)

    source = File.read(@file)
    found = MethodFinder.new(source).find(klass_name, method_name, line: @line)
    not_found("no def at #{@file}:#{@line}") unless found

    @frozen_string_literal = leading_frozen_string_literal(source)
    found
  end

  # Ruby honours frozen_string_literal only before the first token, and the
  # last such comment wins. Prism reports comments anywhere in the file.
  def leading_frozen_string_literal(source)
    result = Prism.parse(source)
    first_token = result.value.location.start_offset
    result.magic_comments
      .select { |comment| comment.key == "frozen_string_literal" }
      .select { |comment| comment.key_loc.start_offset < first_token }
      .last&.value
  end

  # The source install evaluates for +mutation+, and its first line.
  def install_source(mutation)
    prelude = magic_comments
    [prelude + wrapped(mutant_source(mutation)), def_node.location.start_line - prelude.count("\n")]
  end

  # One line per comment; install starts the eval that many lines earlier.
  def magic_comments
    return "" unless @frozen_string_literal

    "# frozen_string_literal: #{@frozen_string_literal}\n"
  end

  def visibility
    if @owner.private_method_defined?(@name, false)
      :private
    elsif @owner.protected_method_defined?(@name, false)
      :protected
    else
      :public
    end
  end

  # Removing first keeps -w from warning about a redefinition. Ruby also
  # warns on removing initialize, which is harmless here because a
  # definition goes straight back.
  def remove_live_method
    defined = @owner.method_defined?(@name, false) || @owner.private_method_defined?(@name, false)
    return unless defined

    verbose, $VERBOSE = $VERBOSE, nil
    @owner.send(:remove_method, @name)
  ensure
    $VERBOSE = verbose if defined
  end

  # `module A; class B; class << self; <def>\nend; end; end` on the def's
  # first line. No superclass, so reopening a subclass cannot mismatch.
  # A block-defined class (`C = Struct.new do`) is entered with class_eval
  # rather than reopened, so constant lookup stays that of the block, whose
  # lexical scope is the enclosing nesting.
  def wrapped(def_source)
    nesting = @found.nesting
    header = nesting.map { |node| "#{scope_header(node)}; " }.join
    footer = (["end"] * nesting.size).join("; ")
    "#{header}#{def_source}\n#{footer}\n"
  end

  def scope_header(node)
    case node
    when Prism::SingletonClassNode then "class << self"
    when Prism::ClassNode then "class #{node.constant_path.slice}"
    when Prism::ModuleNode then "module #{node.constant_path.slice}"
    when Prism::ConstantWriteNode then "#{node.name}.class_eval do"
    when Prism::ConstantPathWriteNode then "#{node.target.slice}.class_eval do"
    end
  end

end
