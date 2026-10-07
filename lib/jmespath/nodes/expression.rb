# frozen_string_literal: true
module JMESPath
  # @api private
  module Nodes
    class Expression < Node
      attr_reader :expression

      def initialize(expression, scope = nil)
        @expression = expression
        @scope = scope
      end

      # Expression references capture the variable bindings in effect
      # where they are declared. The returned copy carries those
      # bindings, leaving the shared, compiled node untouched.
      def visit(_value, scope = nil)
        scope ? self.class.new(@expression, scope) : self
      end

      def eval(value)
        @expression.visit(value, @scope)
      end

      def optimize
        self.class.new(@expression.optimize)
      end
    end
  end
end
