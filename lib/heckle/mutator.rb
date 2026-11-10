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

    def visit_integer_node(node)
      replace(:lit, node.location, number(node.value + @randomizer.rand_number))
      super
    end

    def visit_float_node(node)
      value = node.value + @randomizer.rand_number
      replace(:lit, node.location, number(value)) if value.finite?
      super
    end

    # Interpolated parts and %w[] elements have no opening. A heredoc's body
    # lies outside its node's span, so replacing the node would strand it.
    def visit_string_node(node)
      opening = node.opening_loc&.slice
      if opening && !opening.start_with?("<<")
        replace(:str, node.location, @randomizer.rand_string.inspect)
      end
      super
    end

    def visit_x_string_node(node)
    end

    # The numeric part of 2r or 3i is not a mutation site of its own.
    def visit_rational_node(node)
    end

    def visit_imaginary_node(node)
    end

    private

    # Parenthesized when negative so a preceding `-` or a following `**`
    # cannot rebind it (`-3 ** 2` is -9).
    def number(value)
      value.negative? ? "(#{value})" : value.to_s
    end

    def replace(kind, location, replacement)
      @mutations << Mutation.new(kind, location.start_offset, location.end_offset, replacement)
    end
  end
end
