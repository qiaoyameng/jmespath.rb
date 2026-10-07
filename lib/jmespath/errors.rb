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

    class ArithmeticError < Error; end

    class DivisionByZeroError < ArithmeticError; end

    class NonFiniteResultError < ArithmeticError; end

    class NumberBudgetExceededError < ArithmeticError; end

    ZeroDivisionError = DivisionByZeroError
    NonFiniteNumberError = NonFiniteResultError
    NumericBudgetExceededError = NumberBudgetExceededError
    ArithmeticBudgetExceededError = NumberBudgetExceededError
  end
end
