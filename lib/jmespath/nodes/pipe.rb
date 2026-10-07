# frozen_string_literal: true
module JMESPath
  # @api private
  module Nodes
    class Pipe < Node
      def initialize(left, right)
        @left = left
        @right = right
      end

      def visit(value)
        @right.visit(@left.visit(value))
      end

      def optimize
        self.class.new(@left.optimize, @right.optimize)
      end
    end
  end
end
