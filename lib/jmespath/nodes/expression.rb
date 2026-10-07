# frozen_string_literal: true
module JMESPath
  # @api private
  module Nodes
    class Expression < Node
      attr_reader :expression

      def initialize(expression, bindings = nil)
        @expression = expression
        @bindings = bindings
      end

      def visit(_value, bindings = nil)
        bindings.nil? ? self : self.class.new(@expression, bindings)
      end

      def eval(value, bindings = @bindings)
        @expression.visit(value, bindings)
      end

      def optimize
        self.class.new(@expression.optimize, @bindings)
      end
    end
  end
end
