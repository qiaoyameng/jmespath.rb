# frozen_string_literal: true
module JMESPath
  module Nodes
    class Let < Node
      def initialize(name, value, body)
        @name = name
        @value = value
        @body = body
      end

      def visit(value, bindings = nil)
        bound_value = @value.visit(value, bindings)
        inner_bindings = bindings ? bindings.dup : {}
        inner_bindings[@name] = bound_value
        @body.visit(value, inner_bindings)
      end

      def optimize
        self.class.new(@name, @value.optimize, @body.optimize)
      end
    end
  end
end
