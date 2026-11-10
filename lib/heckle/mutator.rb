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
      @heredoc_openings = []
      def_node.accept(self)
      @mutations
        .reject { |mutation| strands_heredoc?(mutation) }
        .sort_by { |mutation| [mutation.start_offset, -mutation.end_offset] }
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

    # A label key (`foo:` or `"foo":`) stays a label. %i[] elements have
    # neither opening nor closing.
    def visit_symbol_node(node)
      closing = node.closing_loc&.slice
      if closing&.end_with?(":")
        replace(:lit, node.location, "#{@randomizer.rand_symbol.to_s.inspect}:")
      elsif node.opening_loc
        replace(:lit, node.location, @randomizer.rand_symbol.inspect)
      end
      super
    end

    # Regexp#inspect of an escaped pattern is valid source for any string:
    # it escapes `/`, `#` and control characters. The flags are kept.
    def visit_regular_expression_node(node)
      pattern = Regexp.new(Regexp.escape(@randomizer.rand_string)).inspect
      replace(:lit, node.location, pattern + node.closing_loc.slice[1..])
      super
    end

    def visit_while_node(node)
      replace(:while, node.keyword_loc, "until")
      super
    end

    def visit_until_node(node)
      replace(:until, node.keyword_loc, "while")
      super
    end

    # Every form must behave as the node with its branches swapped. `unless`
    # cannot take an `elsif`, so an `if` with one, the `elsif` itself and a
    # ternary (no keyword) negate the predicate instead.
    def visit_if_node(node)
      keyword = node.if_keyword_loc
      if keyword&.slice == "if" && !node.subsequent.is_a?(Prism::IfNode)
        replace(:if, keyword, "unless")
      else
        predicate = node.predicate.location
        replace(:if, predicate, "!(#{predicate.slice})")
      end
      super
    end

    def visit_unless_node(node)
      replace(:if, node.keyword_loc, "if")
      super
    end

    # A range of two integer literals is one site; its ends are not mutated
    # separately. Any other range is descended into. Always inclusive.
    def visit_range_node(node)
      unless node.left.is_a?(Prism::IntegerNode) && node.right.is_a?(Prism::IntegerNode)
        return super
      end

      range = @randomizer.rand_range
      replace(:lit, node.location, "#{range.begin}..#{range.end}")
    end

    # Method names here are not values.
    def visit_alias_method_node(node)
    end

    def visit_undef_node(node)
    end

    # Interpolated parts and %w[] elements have no opening. A heredoc's body
    # lies outside its node's span, so replacing the node would strand it.
    def visit_string_node(node)
      note_heredoc(node)
      if node.opening_loc && !node.heredoc?
        replace(:str, node.location, @randomizer.rand_string.inspect)
      end
      super
    end

    def visit_interpolated_string_node(node)
      note_heredoc(node)
      super
    end

    def visit_x_string_node(node)
      note_heredoc(node)
    end

    def visit_interpolated_x_string_node(node)
      note_heredoc(node)
      super
    end

    # A literal block makes the call an :iter. A block-pass (`&blk`) is an
    # argument, so that call stays a :call.
    def visit_call_node(node)
      kind = node.block.is_a?(Prism::BlockNode) ? :iter : :call
      replace(kind, node.location, "nil")
      super
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

    def note_heredoc(node)
      @heredoc_openings << node.opening_loc.start_offset if node.heredoc?
    end

    # A heredoc's body lies outside its opening's span, so replacing a range
    # that holds the opening would leave the body behind as stray code.
    def strands_heredoc?(mutation)
      @heredoc_openings.any? do |offset|
        offset >= mutation.start_offset && offset < mutation.end_offset
      end
    end

    def replace(kind, location, replacement)
      @mutations << Mutation.new(kind, location.start_offset, location.end_offset, replacement)
    end
  end
end
