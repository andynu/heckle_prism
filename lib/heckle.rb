require "prism"
require "timeout"
require "tempfile"
require "heckle/method_finder"
require "heckle/mutation"
require "heckle/mutator"

##
# Test Unit Sadism

class Heckle

  class Timeout < ::Timeout::Error; end

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
  # Returns a random Fixnum.

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

    found = MethodFinder.new(File.read(@file)).find(klass_name, method_name, line: @line)
    not_found("no def at #{@file}:#{@line}") unless found

    found
  end

end
