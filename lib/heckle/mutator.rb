require "prism"
require "heckle/mutation"

class Heckle
  # Walks one def and collects a Mutation per mutation site. Nothing is
  # applied here. The default visitor descends into every child node, so a
  # visit method only needs to record its own mutation and call super.
  class Mutator < Prism::Visitor
    # randomizer responds to rand_number, rand_string, rand_symbol, rand_range.
    def initialize(randomizer)
      super()
      @randomizer = randomizer
    end

    # Returns the mutations sorted by [start_offset, -end_offset].
    def mutations_for(def_node)
      @mutations = []
      def_node.accept(self)
      @mutations.sort_by { |mutation| [mutation.start_offset, -mutation.end_offset] }
    end

    # Parameters are not mutated; only the body is visited.
    def visit_def_node(node)
      node.body&.accept(self)
    end

    def visit_true_node(node)
      replace(:true, node.location, "false")
      super
    end

    def visit_false_node(node)
      replace(:false, node.location, "true")
      super
    end

    private

    def replace(kind, location, replacement)
      @mutations << Mutation.new(kind, location.start_offset, location.end_offset, replacement)
    end
  end
end
