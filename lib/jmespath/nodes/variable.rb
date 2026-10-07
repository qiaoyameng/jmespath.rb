# frozen_string_literal: true
module JMESPath
  # @api private
  module Nodes
    # Represents a `$name` variable reference. Variables live in their
    # own namespace, separate from data fields, and resolve against the
    # lexical bindings introduced by enclosing `let` expressions.
    class Variable < Node
      def initialize(name, position = nil)
        @name = name
        @position = position
      end

      def visit(_value, scope = nil)
        if scope && scope.key?(@name)
          scope[@name]
        else
          msg = "unbound variable `$#{@name}`"
          msg += " at position #{@position}" if @position
          raise Errors::UnboundVariableError, msg
        end
      end
    end
  end
end
