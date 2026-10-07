# frozen_string_literal: true

module JMESPath
  module Errors
    class Error < StandardError; end

    class RuntimeError < Error; end

    class SyntaxError < Error; end

    class UnboundVariableError < SyntaxError
      attr_reader :position

      def initialize(name, position)
        @position = position
        super("unbound variable `#{name}` at position #{position}")
      end
    end

    class InvalidTypeError < Error; end

    class InvalidValueError < Error; end

    class InvalidArityError < Error; end

    class UnknownFunctionError < Error; end
  end
end
