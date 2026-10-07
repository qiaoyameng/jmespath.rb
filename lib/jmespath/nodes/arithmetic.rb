# frozen_string_literal: true
module JMESPath
  # @api private
  module Nodes
    # Shared helpers for the opt-in arithmetic extension.
    module ArithmeticSupport
      private

      def numeric_operands(left_value, right_value)
        unless Numeric === left_value && Numeric === right_value
          return invalid_operand
        end

        result = yield(left_value, right_value)
        finalize(result)
      end

      def invalid_operand
        if @disable_visit_errors
          nil
        else
          raise Errors::InvalidTypeError, 'arithmetic operations require numeric operands'
        end
      end

      def finalize(result)
        unless result.is_a?(Numeric) && result.finite?
          raise Errors::NonFiniteNumberError, 'arithmetic result is not a finite number'
        end
        if @max_number && result.abs > @max_number
          raise Errors::NumberBudgetExceededError,
                "arithmetic result #{result} exceeds the configured numeric budget #{@max_number}"
        end
        result
      end
    end

    class Arithmetic < Node
      include ArithmeticSupport

      attr_reader :left, :right

      def initialize(left, right, options = {})
        @left = left
        @right = right
        @disable_visit_errors = options[:disable_visit_errors]
        @max_number = options[:max_number]
      end

      def visit(value)
        left_value = @left.visit(value)
        right_value = @right.visit(value)
        numeric_operands(left_value, right_value) { |l, r| operate(l, r) }
      end

      def optimize
        self.class.new(@left.optimize, @right.optimize, node_options)
      end

      private

      def node_options
        { disable_visit_errors: @disable_visit_errors, max_number: @max_number }
      end
    end

    class Add < Arithmetic
      private

      def operate(left, right)
        left + right
      end
    end

    class Subtract < Arithmetic
      private

      def operate(left, right)
        left - right
      end
    end

    class Multiply < Arithmetic
      private

      def operate(left, right)
        left * right
      end
    end

    class Divide < Arithmetic
      def visit(value)
        left_value = @left.visit(value)
        right_value = @right.visit(value)
        unless Numeric === left_value && Numeric === right_value
          return invalid_operand
        end
        raise Errors::DivisionByZeroError, 'division by zero' if right_value.zero?

        if left_value.is_a?(Integer) && right_value.is_a?(Integer)
          quotient, remainder = left_value.divmod(right_value)
          result = remainder.zero? ? quotient : left_value.to_f / right_value.to_f
        else
          result = left_value.to_f / right_value.to_f
        end
        finalize(result)
      end
    end

    class Modulo < Arithmetic
      def visit(value)
        left_value = @left.visit(value)
        right_value = @right.visit(value)
        unless Numeric === left_value && Numeric === right_value
          return invalid_operand
        end
        raise Errors::DivisionByZeroError, 'modulo by zero' if right_value.zero?

        result =
          if left_value.is_a?(Integer) && right_value.is_a?(Integer)
            left_value % right_value
          else
            left_value.to_f % right_value.to_f
          end
        finalize(result)
      end
    end

    class UnaryArithmetic < Node
      include ArithmeticSupport

      def initialize(child, options = {})
        @child = child
        @disable_visit_errors = options[:disable_visit_errors]
        @max_number = options[:max_number]
      end

      def visit(value)
        operand = @child.visit(value)
        unless Numeric === operand
          return invalid_operand
        end

        finalize(operate(operand))
      end

      def optimize
        self.class.new(@child.optimize,
                       disable_visit_errors: @disable_visit_errors,
                       max_number: @max_number)
      end

      private

      def operate(_operand)
        nil
      end
    end

    class Negate < UnaryArithmetic
      private

      def operate(operand)
        -operand
      end
    end

    class UnaryPlus < UnaryArithmetic
      private

      def operate(operand)
        +operand
      end
    end
  end
end
