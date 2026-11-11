require "prism"

class Heckle
  # Locates a method definition in Ruby source by class path and method name.
  class MethodFinder
    Result = Struct.new(:def_node, :nesting)

    SCOPE_NODES = [Prism::ClassNode, Prism::ModuleNode].freeze

    def initialize(source)
      @program = Prism.parse(source).value
    end

    # klass_name is "A::B::C"; method_name is "foo" or "self.foo".
    # With line, only the def whose `def` keyword starts on that line matches.
    # Without it the last match wins, as Ruby keeps the last definition.
    # Returns a Result, or nil when not found.
    def find(klass_name, method_name, line: nil)
      target = klass_name.to_s.split("::").map(&:to_sym)
      name = method_name.to_s
      singleton = name.start_with?("self.")
      name = name.delete_prefix("self.").to_sym

      matches = []
      search_scopes(@program.statements, [], [], target) do |scope, nesting|
        collect_defs(scope, nesting, name, singleton, matches)
      end
      return matches.last unless line

      matches.find { |result| result.def_node.def_keyword_loc.start_line == line }
    end

    private

    # A block scope (`Name = Struct.new do ... end`) is a leaf: a class or
    # module keyword inside the block names a constant of the enclosing
    # scope, not of the block-defined class.
    def search_scopes(body, path, nesting, target, &block)
      statements_of(body).each do |node|
        block_scope = block_scope?(node)
        next unless block_scope || SCOPE_NODES.include?(node.class)

        candidate = scope_path(node, path)
        candidate = nil unless candidate && target.first(candidate.size) == candidate

        inner = nesting + [node]
        if candidate == target
          yield node, inner
        elsif !block_scope
          search_scopes(node.body, candidate, inner, target, &block)
        end
      end
    end

    # `Name = call(...) do ... end` or `A::B = call { ... }`, whatever the call.
    def block_scope?(node)
      return false unless node.is_a?(Prism::ConstantWriteNode) || node.is_a?(Prism::ConstantPathWriteNode)

      node.value.is_a?(Prism::CallNode) && node.value.block.is_a?(Prism::BlockNode)
    end

    # A nil path means the enclosing scope is off target; only a
    # `::`-rooted name, which names a top-level constant, can match there.
    def scope_path(node, path)
      parts = scope_name_parts(node)
      return parts.drop(1) if parts.first == :""

      path && path + parts
    rescue Prism::ConstantPathNode::DynamicPartsInConstantPathError
      nil
    end

    def scope_name_parts(node)
      case node
      when Prism::ConstantWriteNode then [node.name]
      when Prism::ConstantPathWriteNode then node.target.full_name_parts
      else node.constant_path.full_name_parts
      end
    end

    def scope_body(scope)
      block_scope?(scope) ? scope.value.block.body : scope.body
    end

    def collect_defs(scope, nesting, name, singleton, matches)
      statements_of(scope_body(scope)).each do |node|
        if singleton && node.is_a?(Prism::SingletonClassNode) && node.expression.is_a?(Prism::SelfNode)
          statements_of(node.body).each do |inner|
            each_def(inner) do |def_node|
              matches << Result.new(def_node, nesting + [node]) if def_node.name == name && def_node.receiver.nil?
            end
          end
        else
          each_def(node) do |def_node|
            next unless def_node.name == name
            next unless singleton ? def_node.receiver.is_a?(Prism::SelfNode) : def_node.receiver.nil?

            matches << Result.new(def_node, nesting)
          end
        end
      end
    end

    # Yields a DefNode statement, or DefNodes passed as call arguments
    # (`private def foo`, `private memoize def foo`).
    def each_def(node, &block)
      case node
      when Prism::DefNode
        yield node
      when Prism::CallNode
        node.arguments&.arguments&.each { |arg| each_def(arg, &block) }
      end
    end

    def statements_of(body)
      case body
      when Prism::StatementsNode then body.body
      when Prism::BeginNode then body.statements&.body || []
      else []
      end
    end
  end
end
