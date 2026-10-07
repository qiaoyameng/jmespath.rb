# frozen_string_literal: true
module JMESPath
  module Nodes
    class And < Node
      def initialize(left, right)
        @left = left
        @right = right
      end

      def visit(value, bindings = nil)
        result = @left.visit(value, bindings)
        if JMESPath::Util.falsey?(result)
          result
        else
          @right.visit(value, bindings)
        end
      end

      def optimize
        self.class.new(@left.optimize, @right.optimize)
      end
    end
  end
end
