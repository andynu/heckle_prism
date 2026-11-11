require "prism"
require "timeout"
require "tempfile"
require "minitest"
require "heckle/method_finder"
require "heckle/mutation"
require "heckle/mutator"

##
# Test Unit Sadism

class Heckle

  class Timeout < ::Timeout::Error; end

  # Minitest records any other exception as a test error, which would spend
  # the timeout on one test and let the next one loop forever.
  Minitest::Test::PASSTHROUGH_EXCEPTIONS << Timeout

  ##
  # Raised when the method to heckle, or its source, cannot be found.

  class SourceNotFound < StandardError; end

  ##
  # The version of Heckle you are using.

  VERSION = '2.0.0.b1'

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
  # Is this platform MS Windows-like?

  WINDOZE = RUBY_PLATFORM =~ /mswin/

  ##
  # Path to the bit bucket.

  NULL_PATH = WINDOZE ? 'NUL:' : '/dev/null'

  ##
  # diff(1) executable

  DIFF = WINDOZE ? 'diff.exe' : 'diff'

  ##
  # Mutation count

  attr_accessor :count

  ##
  # Mutations that caused failures

  attr_accessor :failures

  ##
  # Class being heckled

  attr_accessor :klass

  ##
  # Name of class being heckled

  attr_accessor :klass_name

  ##
  # Name of method being heckled

  attr_accessor :method_name

  @@debug = false
  @@guess_timeout = true
  @@timeout = 60 # default to something longer (can be overridden by runners)

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
  # Loads the test files at +paths+. A <tt>require "minitest/autorun"</tt>
  # in them does not schedule a run at exit: Heckle runs the suite itself.

  def self.load_tests(paths)
    # Minitest.autorun installs its at_exit hook only while this is false.
    Minitest.class_variable_set(:@@installed_at_exit, true)
    paths.each { |path| require File.expand_path(path) }
  end

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
    remove_live_method
    prelude = magic_comments
    eval(prelude + wrapped(mutant_source(mutation)), TOPLEVEL_BINDING, @file,
         def_node.location.start_line - prelude.count("\n"))
    @owner.send(@visibility, @name)
    @installed = true
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
      Minitest.run_all_suites(reporter, options)
      executor.shutdown if executor.respond_to?(:shutdown)
      reporter.report

      reporter.passed?
    end
  end

  def self.quietly
    return yield if @@debug

    stdout, stderr = $stdout, $stderr
    File.open(NULL_PATH, "w") do |null|
      $stdout = $stderr = null
      yield
    ensure
      $stdout, $stderr = stdout, stderr
    end
  end
  private_class_method :quietly

  def run_tests
    if tests_pass? then
      record_passing_mutation
    else
      @reporter.report_test_failures
    end
  end

  ##
  # Runs the tests against each mutant in turn. Returns nil when there is
  # nothing to mutate, true when every mutant was killed, false otherwise.
  # Any exception other than SyntaxError, a timeout or Interrupt propagates,
  # with the original method restored.

  def validate
    @count = 0
    @failures = []

    if mutations.empty? then
      @reporter.no_mutations(method_name)
      return
    end

    @reporter.method_loaded(klass_name, method_name, mutations.size)

    mutations.each_with_index do |mutation, index|
      @reporter.remaining_mutations(mutations.size - index)
      @current_mutation = mutation
      begin
        if @@debug
          @reporter.replacing(klass_name, method_name,
                              dedent(original_source), dedent(mutant_source(mutation)))
        end

        self.count += 1
        install mutation
        ::Timeout::timeout(@@timeout, Heckle::Timeout) { run_tests }
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
      false
    else
      @reporter.no_surviving_mutants
      true
    end
  end

  def record_passing_mutation
    @failures << mutant_source(@current_mutation)
  end

  ##
  # Returns a random nonzero Integer from -100 to 100.

  def rand_number
    (rand(100) + 1)*((-1)**rand(2))
  end

  ##
  # Returns a random String

  def rand_string
    size = rand(50)
    str = +""
    size.times { str << rand(126).chr }
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
    def no_mutations(method_name)
      warning "#{method_name} has a thick skin. There's nothing to heckle."
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

    def replacing(klass_name, method_name, original, src)
      puts "Replacing #{klass_name}##{method_name} with:\n\n"
      diff(original, src)
    end

    def report_test_failures
      puts "Tests failed -- this is good" if Heckle.debug
    end
  end

  private

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
    end
  end

end
