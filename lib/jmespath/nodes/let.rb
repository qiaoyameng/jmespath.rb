# frozen_string_literal: true
module JMESPath
  # @api private
  module Nodes
    # Represents a `let $name = expression in expression` expression.
    # Each binding's expression is evaluated exactly once, in the scope
    # enclosing the `let`, when the `let` is entered. The body is then
    # evaluated with the bindings visible. Bindings are stored per
    # evaluation, so a compiled expression can be safely shared across
    # threads and never retains values from a previous evaluation.
    class Let < Node
      EMPTY_SCOPE = {}.freeze

      def initialize(bindings, body)
        @bindings = bindings
        @body = body
      end

      def visit(value, scope = nil)
        outer_scope = scope || EMPTY_SCOPE
        inner_scope = @bindings.each_with_object(outer_scope.dup) do |(name, node), bound|
          bound[name] = node.visit(value, outer_scope)
        end
        @body.visit(value, inner_scope)
      end

      def optimize
        self.class.new(
          @bindings.map { |(name, node)| [name, node.optimize] },
          @body.optimize
        )
      end
    end
  end
end
