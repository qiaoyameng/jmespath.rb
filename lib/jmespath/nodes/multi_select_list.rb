# frozen_string_literal: true
module JMESPath
  # @api private
  module Nodes
    class MultiSelectList < Node
      def initialize(children)
        @children = children
      end

      def visit(value, bindings = nil)
        if value.nil?
          value
        else
          @children.map { |n| n.visit(value, bindings) }
        end
      end

      def optimize
        self.class.new(@children.map(&:optimize))
      end
    end
  end
end
