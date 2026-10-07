# frozen_string_literal: true
module JMESPath
  # @api private
  module Nodes
    class MultiSelectList < Node
      def initialize(children)
        @children = children
      end

      def visit(value, scope = nil)
        if value.nil?
          value
        else
          @children.map { |n| n.visit(value, scope) }
        end
      end

      def optimize
        self.class.new(@children.map(&:optimize))
      end
    end
  end
end
