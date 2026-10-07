# frozen_string_literal: true
module JMESPath
  module Nodes
    class Not < Node
      def initialize(expression)
        @expression = expression
      end

      def visit(value, bindings = nil)
        JMESPath::Util.falsey?(@expression.visit(value, bindings))
      end

      def optimize
        self.class.new(@expression.optimize)
      end
    end
  end
end
