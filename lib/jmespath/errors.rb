# frozen_string_literal: true

module JMESPath
  module Errors
    class Error < StandardError; end

    class RuntimeError < Error; end

    class SyntaxError < Error; end

    class InvalidTypeError < Error; end

    class InvalidValueError < Error; end

    class InvalidArityError < Error; end

    class UnknownFunctionError < Error; end

    # Raised when a transform expression uses JMESPath features that
    # cannot be mapped back to concrete paths in the original document
    # (functions, multi-selects, pipes, flatten, etc).
    class UnsupportedExpressionError < Error; end

    # Raised when the targets selected by transform rules overlap: two
    # rules select the same node, or one selects an ancestor of another.
    class TransformConflictError < Error; end

    # Raised when a transform block fails. Carries the expression and
    # the path (in the original document) of the node being transformed.
    class TransformError < Error
      def initialize(message, expression:, path:)
        @expression = expression
        @path = path
        super(message)
      end

      # @return [String]
      attr_reader :expression

      # @return [Array<String, Integer>] Path of the node in the
      #   original document.
      attr_reader :path
    end
  end
end
