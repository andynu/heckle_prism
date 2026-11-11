require 'optparse'
require 'heckle'

class HeckleRunner
  ##
  # Raised for a usage problem; bin/heckle reports its message without a
  # backtrace.

  class Error < StandardError; end

  ##
  # Parses +argv+, heckles, and returns true when no mutant survived.
  # Aborts with a one-line message on a usage error.

  def self.run argv=ARGV
    options = parse_args argv

    class_or_module, method = argv.shift, argv.shift
    abort "Usage: #{File.basename $0} class_name [method_name]" unless class_or_module

    new(class_or_module, method, options).run
  rescue OptionParser::ParseError, Error, Heckle::SourceNotFound => e
    abort e.message
  end

  ##
  # Test files loaded unless -t is given.

  DEFAULT_TEST_PATTERNS = %w[test/**/test_*.rb test/**/*_test.rb].freeze

  def self.parse_args argv
    options = {
      :force => false,
      :nodes => Heckle::MUTATABLE_NODES,
      :debug => false,
      :timeout => nil,
      :test_pattern => DEFAULT_TEST_PATTERNS,
    }

    OptionParser.new do |opts|
      opts.version = Heckle::VERSION
      opts.program_name = File.basename $0
      opts.banner = "Usage: #{opts.program_name} class_name [method_name]"
      opts.on("-v", "--verbose", "Loudly explain heckle run") do
        options[:debug] = true
      end

      opts.on("-t", "--tests TEST_PATTERN",
              "Location of tests (glob)",
              "default: #{DEFAULT_TEST_PATTERNS.join(' and ')}") do |pattern|
        options[:test_pattern] = pattern
      end

      opts.on("-F", "--force", "Ignore initial test failures") do
        options[:force] = true
      end

      opts.on(      "--assignments", "Only mutate assignments") do
        puts "!"*70
        puts "!!! Heckling assignments only"
        puts "!"*70
        puts

        options[:nodes] = Heckle::ASGN_NODES
      end

      opts.on("-b", "--branches", "Only mutate branches") do
        puts "!"*70
        puts "!!! Heckling branches only"
        puts "!"*70
        puts

        options[:nodes] = Heckle::BRANCH_NODES
      end

      opts.on("-T", "--timeout SECONDS", "The maximum time for a test run in seconds",
                                         "Used to catch infinite loops") do |timeout|
        timeout = timeout.to_i
        puts "Setting timeout at #{timeout} seconds."
        options[:timeout] = timeout
      end

      opts.on("-n", "--nodes NODES", "Nodes to mutate",
              "Possible values: #{Heckle::MUTATABLE_NODES.join(',')}") do |opt|
        nodes = opt.split(',').collect {|n| n.to_sym }
        options[:nodes] = nodes
        puts "Mutating nodes: #{nodes.inspect}"
      end

      opts.on("-x", "--exclude-nodes NODES", "Nodes to exclude") do |opt|
        exclusions = opt.split(',').collect {|n| n.to_sym }
        options[:nodes] = canonical(options[:nodes]) - canonical(exclusions)
        puts "Mutating without nodes: #{exclusions.inspect}"
      end
    end.parse! argv

    p options if options[:debug]

    Heckle.debug = options[:debug]
    Heckle.timeout = options[:timeout] if options[:timeout]

    options
  end

  def self.canonical nodes
    nodes.map { |node| Heckle::NODE_ALIASES.fetch(node, node) }
  end

  def initialize class_or_module, method, options={}
    @class_or_module = class_or_module
    @method = method
    @options = options
  end

  ##
  # Loads the tests, checks they pass unmutated (unless forced), heckles
  # the method or every method of the class, and prints a summary. Returns
  # true when no mutant survived.

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
    hecklers.each { |heckler| counts[heckler.validate] += 1 }
    all_good = counts[false] == 0

    puts "Heckle Results:"
    puts
    puts "Passed    : %3d" % counts[true]
    puts "Failed    : %3d" % counts[false]
    puts "Thick Skin: %3d" % counts[nil]
    puts

    if all_good then
      puts "All heckling was thwarted! YAY!!!"
    else
      puts "Improve the tests and try again."
    end

    all_good
  end

  private

  def check_nodes
    unknown = self.class.canonical(@options[:nodes]) - Heckle::MUTATABLE_NODES
    raise Error, "Unknown mutation kind: #{unknown.join(',')}" unless unknown.empty?
  end

  def load_tests
    patterns = Array(@options[:test_pattern])
    files = Dir.glob(patterns).uniq
    raise Error, "No test files match #{patterns.join(' or ')}" if files.empty?

    Heckle.load_tests(files)
  end

  def build_hecklers
    klass = resolve_class
    return [heckler(@method)] if @method

    method_names(klass).filter_map do |name|
      next unless in_project?(klass, name)

      heckler(name)
    rescue Heckle::SourceNotFound => e
      puts "Skipping #{e.message}"
    end
  end

  # Methods a gem or Ruby defines in the class (Rails' class_attribute
  # accessors, say) are not the user's to heckle; -v still names them.
  def in_project? klass, name
    owner = name.start_with?("self.") ? klass.singleton_class : klass
    file, line = owner.instance_method(name.delete_prefix("self.")).source_location
    return true if file && inside_project?(file)

    if Heckle.debug
      where = file ? "defined outside the project, at #{file}:#{line}" : "no source location"
      puts "Skipping #{@class_or_module}##{name}: #{where}"
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
    Heckle.new(@class_or_module, name, @options[:nodes])
  end

  # Every method the class defines itself, whatever its visibility.
  def method_names klass
    own = ->(mod) { mod.instance_methods(false) + mod.private_instance_methods(false) }

    names = own.(klass).map(&:to_s) + own.(klass.singleton_class).map { |name| "self.#{name}" }
    names.sort
  end

  def resolve_class
    klass = @class_or_module.split("::").inject(Object) { |scope, name| scope.const_get(name, false) }
    raise NameError unless klass.is_a?(Module)

    klass
  rescue NameError
    raise Error, "Unknown class: #{@class_or_module}"
  end

  # Without -T the timeout is twice the unmutated run, at least 5 seconds.
  def initial_run
    started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
    passed = Heckle.tests_pass?

    unless @options[:force] or passed then
      raise Error, "Initial run of tests failed... fix and run heckle again"
    end

    if Heckle.guess_timeout? then
      running_time = Process.clock_gettime(Process::CLOCK_MONOTONIC) - started
      Heckle.timeout = (running_time * 2 < 5) ? 5 : (running_time * 2).ceil
    end

    puts "Timeout set to #{Heckle.timeout} seconds."

    passed
  end
end
