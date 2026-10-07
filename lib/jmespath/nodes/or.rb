# frozen_string_literal: true
module JMESPath
  # @api private
  module Nodes
    class Or < Node
      def initialize(left, right)
        @left = left
        @right = right
      end

      def visit(value, bindings = nil)
        result = @left.visit(value, bindings)
        if JMESPath::Util.falsey?(result)
          @right.visit(value, bindings)
        else
          result
        end
      end

      def optimize
        self.class.new(@left.optimize, @right.optimize)
      end
    end
  end
end
