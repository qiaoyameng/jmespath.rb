# frozen_string_literal: true
module JMESPath
  module Nodes
    class Variable < Node
      attr_reader :position

      def initialize(name, position)
        @name = name
        @position = position
      end

      def visit(_value, bindings = nil)
        if bindings.nil? || !bindings.key?(@name)
          raise Errors::UnboundVariableError.new(@name, @position)
        end

        bindings[@name]
      end
    end
  end
end
