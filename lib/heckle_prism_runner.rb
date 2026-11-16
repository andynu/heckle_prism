require "optparse"
require "heckle_prism"

class HecklePrismRunner
  ##
  # Raised for a usage problem; bin/heckle_prism reports its message without a
  # backtrace.

  class Error < StandardError; end

  ##
  # Parses +argv+, heckles, and returns true when no mutant survived and
  # every mutant was run.
  # Aborts with a one-line message on a usage error.

  def self.run(argv = ARGV)
    options = parse_args(argv)
    class_name, method_name = argv
    abort "Usage: #{File.basename $0} class_name [method_name]" unless class_name

    new(class_name, method_name, options).run
  rescue OptionParser::ParseError, Error, HecklePrism::SourceNotFound => e
    abort e.message
  end

  ##
  # Test files loaded unless -t is given.

  DEFAULT_TEST_PATTERNS = %w[test/**/test_*.rb test/**/*_test.rb].freeze

  ##
  # Removes the options from +argv+, leaving the class and method names,
  # sets HecklePrism's run-wide settings from them and returns the rest
  # as a Hash.

  def self.parse_args(argv)
    options = { force: false, nodes: HecklePrism::MUTATABLE_NODES, debug: false,
                timeout: nil, test_pattern: DEFAULT_TEST_PATTERNS }
    tests = []
    announce = ->(text) { HecklePrism::Reporter.new.warning(text) }

    parser = OptionParser.new
    parser.version = HecklePrism::VERSION
    parser.banner = "Usage: #{parser.program_name} [options] class_name [method_name]\n\n" \
                    "Mutates the method, or every method the class defines, and reports\n" \
                    "each mutant the tests still pass.\n\n"

    parser.on("-v", "--verbose", "Show each mutant and the test output") { options[:debug] = true }

    parser.on("-t", "--tests TEST_PATTERN",
              "Glob of test files to load",
              "Repeat to load more; any -t replaces the default",
              "default: #{DEFAULT_TEST_PATTERNS.join(' and ')}") { |pattern| tests << pattern }

    parser.on("-F", "--force", "Heckle even when the unmutated tests fail") { options[:force] = true }

    parser.on("--assignments", "Mutate only #{HecklePrism::ASGN_NODES.join(', ')}") do
      announce.("Heckling assignments only")
      options[:nodes] = HecklePrism::ASGN_NODES
    end

    parser.on("-b", "--branches", "Mutate only #{HecklePrism::BRANCH_NODES.join(', ')}") do
      announce.("Heckling branches only")
      options[:nodes] = HecklePrism::BRANCH_NODES
    end

    parser.on("-T", "--timeout SECONDS", Integer, "Seconds a test run may take before its mutant",
              "is stopped and counted as timed out; default:",
              "twice the unmutated run, at least 5") do |seconds|
      raise OptionParser::InvalidArgument, seconds.to_s if seconds < 1

      puts "Setting timeout at #{seconds} seconds."
      options[:timeout] = seconds
    end

    parser.on("--memory-limit MB", Integer, "Most resident memory a test run may use",
              "0 turns the limit off; default: the memory used",
              "after the unmutated run plus the larger of",
              "1024 MB and that amount again") do |megabytes|
      raise OptionParser::InvalidArgument, megabytes.to_s if megabytes < 0

      options[:memory_limit] = megabytes
    end

    parser.on("--fork", "Run each mutant in a forked child",
              "The heckle process never loads a mutant") do
      unless Process.respond_to?(:fork)
        raise Error, "--fork needs Process.fork, which this Ruby does not have"
      end

      options[:fork] = true
    end

    parser.on("-n", "--nodes NODES", Array, "Comma-separated mutation kinds to apply, from",
              HecklePrism::MUTATABLE_NODES.join(",")) do |names|
      options[:nodes] = names.map(&:to_sym)
      puts "Mutating nodes: #{options[:nodes]}"
    end

    parser.on("-x", "--exclude-nodes NODES", Array, "Comma-separated mutation kinds to leave out") do |names|
      left_out = names.map(&:to_sym)
      options[:nodes] = canonical(options[:nodes]) - canonical(left_out)
      puts "Mutating without nodes: #{left_out}"
    end

    parser.parse!(argv)
    options[:test_pattern] = tests unless tests.empty?
    puts options.inspect if options[:debug]

    HecklePrism.debug = options[:debug]
    HecklePrism.timeout = options[:timeout] if options[:timeout]
    # Absent unless given, so -v prints the options as without the flag.
    HecklePrism.fork = options.fetch(:fork, false)

    options
  end

  ##
  # The summary's mutant counts, which add up to the mutants run. Mutants
  # not judged appear by reason, between killed and survived, only when
  # there are some.

  def self.mutants_line killed, not_judged, survived
    judged_not = HecklePrism::Reporter.tally(not_judged)
    judged_not += ", " unless judged_not.empty?
    "Mutants   : %3d killed, %s%d survived" % [killed, judged_not, survived]
  end

  ##
  # The closing line when +count+ mutants were not run.

  def self.not_run_line count
    if count == 1
      "1 mutant was not run. Run heckle_prism with --fork to judge it."
    else
      "#{count} mutants were not run. Run heckle_prism with --fork to judge them."
    end
  end

  def self.canonical nodes
    nodes.map { |node| HecklePrism::NODE_ALIASES.fetch(node, node) }
  end

  def initialize(class_name, method_name = nil, options = {})
    @class_name = class_name
    @method_name = method_name
    @options = options
  end

  ##
  # Loads the tests, checks they pass unmutated (unless forced), heckles
  # the method or every method of the class, and prints a summary. Returns
  # true when no mutant survived and every mutant was run.

  def run
    check_nodes
    load_tests
    hecklers = build_hecklers

    passed = initial_run

    if passed then
      puts "Initial tests pass. Let's rumble."
    else
      puts "Initial tests failed but you forced things. Let's rumble."
    end
    puts

    counts = Hash.new(0)
    survived = killed = 0
    not_judged = Hash.new(0)
    hecklers.each do |heckler|
      result = heckler.validate
      # A method with mutants not run and no survivor has not passed.
      result = :not_run if result && heckler.not_judged.key?(:unsettled)
      counts[result] += 1
      survived += heckler.failures.size
      heckler.not_judged.each { |reason, count| not_judged[reason] += count }
      killed += heckler.count - heckler.failures.size - heckler.not_judged.values.sum
    end
    not_run = not_judged[:unsettled]
    all_good = counts[false] == 0 && not_run == 0

    puts "Heckle Results:"
    puts
    puts "Passed    : %3d" % counts[true]
    puts "Failed    : %3d" % counts[false]
    puts "Thick Skin: %3d" % counts[nil]
    puts "Not Run   : %3d" % counts[:not_run] if counts[:not_run] > 0
    puts self.class.mutants_line(killed, not_judged, survived)
    puts

    if all_good then
      puts "All heckling was thwarted! YAY!!!"
    else
      puts "Improve the tests and try again." if counts[false] > 0
      puts self.class.not_run_line(not_run) if not_run > 0
    end

    all_good
  end

  private

  def check_nodes
    unknown = self.class.canonical(@options[:nodes]) - HecklePrism::MUTATABLE_NODES
    raise Error, "Unknown mutation kind: #{unknown.join(',')}" unless unknown.empty?
  end

  # Each given pattern must match a file, since a mistyped one would quietly
  # leave its tests out. A project need only match one default pattern.
  def load_tests
    patterns = Array(@options[:test_pattern])
    matches = patterns.map { |pattern| Dir.glob(pattern) }
    empty = patterns.zip(matches).select { |_pattern, files| files.empty? }.map(&:first)
    empty = [] if patterns == DEFAULT_TEST_PATTERNS && empty.size < patterns.size
    raise Error, "No test files match #{empty.join(' or ')}" unless empty.empty?

    HecklePrism.load_tests(matches.flatten.uniq)
  end

  def build_hecklers
    klass = resolve_class
    return [heckler(@method_name)] if @method_name

    method_names(klass).filter_map do |name|
      next unless in_project?(klass, name)

      heckler(name)
    rescue HecklePrism::SourceNotFound => e
      puts "Skipping #{e.message}"
    end
  end

  # Methods a gem or Ruby defines in the class (Rails' class_attribute
  # accessors, say) are not the user's to heckle; -v still names them.
  def in_project? klass, name
    owner = name.start_with?("self.") ? klass.singleton_class : klass
    file, line = owner.instance_method(name.delete_prefix("self.")).source_location
    return true if file && inside_project?(file)

    if HecklePrism.debug
      where = file ? "defined outside the project, at #{file}:#{line}" : "no source location"
      puts "Skipping #{@class_name}##{name}: #{where}"
    end
    false
  end

  def inside_project? file
    path = File.expand_path(file)
    return false unless File.exist?(path)

    root = File.realpath(Dir.pwd)
    File.realpath(path).start_with?(root + File::SEPARATOR)
  end

  def heckler name
    HecklePrism.new(@class_name, name, @options[:nodes])
  end

  # Every method the class defines itself, whatever its visibility.
  def method_names klass
    own = ->(mod) { mod.instance_methods(false) + mod.private_instance_methods(false) }

    names = own.(klass).map(&:to_s) + own.(klass.singleton_class).map { |name| "self.#{name}" }
    names.sort
  end

  def resolve_class
    klass = @class_name.split("::").inject(Object) { |scope, name| scope.const_get(name, false) }
    raise NameError unless klass.is_a?(Module)

    klass
  rescue NameError
    raise Error, "Unknown class: #{@class_name}"
  end

  # Without -T the timeout is twice the unmutated run, at least 5 seconds.
  def initial_run
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    passed = HecklePrism.tests_pass?

    unless @options[:force] or passed then
      raise Error, "Initial run of tests failed... fix and run heckle_prism again"
    end

    if HecklePrism.guess_timeout? then
      running_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      HecklePrism.timeout = (running_time * 2 < 5) ? 5 : (running_time * 2).ceil
    end

    puts "Timeout set to #{HecklePrism.timeout} seconds."
    puts memory_limit

    passed
  end

  # Sets HecklePrism.memory_limit and returns the line that says what it is.
  # Measured after the unmutated run, which has grown the heap to what
  # the tests need.
  def memory_limit
    megabytes = @options[:memory_limit]
    HecklePrism.memory_limit = nil
    return "Memory limit off." if megabytes == 0

    unless HecklePrism::Memory.readable?
      return "Memory limit not enforced: resident memory cannot be read on this platform."
    end

    limit = megabytes ? megabytes * HecklePrism::Memory::MB : HecklePrism::Memory.default_limit(HecklePrism::Memory.resident)
    HecklePrism.memory_limit = limit
    "Memory limit set to #{limit / HecklePrism::Memory::MB} MB."
  end
end
