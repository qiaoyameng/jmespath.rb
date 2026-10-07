# frozen_string_literal: true
module JMESPath
  # @api private
  module Nodes
    module ArithmeticMath
      private

      def number(value, disable_visit_errors)
        return value if value.is_a?(Numeric)

        raise Errors::InvalidTypeError, 'arithmetic expressions expect JSON numbers' unless disable_visit_errors

        nil
      end

      def finite_number(value)
        return value if value.nil?
        return value unless value.is_a?(Numeric)

        nonfinite = value.respond_to?(:nan?) &&
                    (value.nan? || (value.respond_to?(:infinite?) && !value.infinite?.nil?))
        raise Errors::NonFiniteResultError, 'arithmetic expressions require finite numbers' if nonfinite

        value
      end

      def within_budget(value, budget)
        return value if value.nil? || budget.nil?
        return value unless value.is_a?(Numeric)

        if value.abs > budget
          raise Errors::NumberBudgetExceededError, "numeric value exceeds configured budget #{budget}"
        end

        value
      end

      def prepare(value, disable_visit_errors, budget)
        value = number(value, disable_visit_errors)
        finite_number(value)
        within_budget(value, budget)
      end

      def finish(value, budget)
        finite_number(value)
        within_budget(value, budget)
      end
    end

    class Arithmetic < Node
      include ArithmeticMath

      attr_reader :operator, :left, :right

      def initialize(operator, left, right, options = {})
        @operator = operator
        @left = left
        @right = right
        @disable_visit_errors = options[:disable_visit_errors]
        @number_budget = options[:number_budget]
      end

      def visit(value)
        left_value = prepare(@left.visit(value), @disable_visit_errors, @number_budget)
        right_value = prepare(@right.visit(value), @disable_visit_errors, @number_budget)
        return if left_value.nil? || right_value.nil?

        result = calculate(left_value, right_value)
        finish(result, @number_budget)
        result
      end

      def optimize
        self.class.new(
          @operator,
          @left.optimize,
          @right.optimize,
          disable_visit_errors: @disable_visit_errors,
          number_budget: @number_budget
        )
      end

      private

      def calculate(left_value, right_value)
        case @operator
        when :plus then left_value + right_value
        when :minus then left_value - right_value
        when :multiply then left_value * right_value
        when :modulo then modulo(left_value, right_value)
        when :divide then divide(left_value, right_value)
        end
      end

      def divide(left_value, right_value)
        raise Errors::DivisionByZeroError, 'division by zero' if right_value.zero?

        left_value.to_f / right_value.to_f
      end

      def modulo(left_value, right_value)
        raise Errors::DivisionByZeroError, 'modulo by zero' if right_value.zero?

        left_value % right_value
      end
    end

    class UnaryArithmetic < Node
      include ArithmeticMath

      attr_reader :operator, :child

      def initialize(operator, child, options = {})
        @operator = operator
        @child = child
        @disable_visit_errors = options[:disable_visit_errors]
        @number_budget = options[:number_budget]
      end

      def visit(value)
        child_value = prepare(@child.visit(value), @disable_visit_errors, @number_budget)
        return if child_value.nil?

        result = @operator == :plus ? child_value : -child_value
        finish(result, @number_budget)
        result
      end

      def optimize
        self.class.new(
          @operator,
          @child.optimize,
          disable_visit_errors: @disable_visit_errors,
          number_budget: @number_budget
        )
      end
    end
  end
end
