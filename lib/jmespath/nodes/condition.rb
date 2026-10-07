# frozen_string_literal: true
module JMESPath
  # @api private
  module Nodes
    class Condition < Node
      def initialize(test, child)
        @test = test
        @child = child
      end

      def visit(value, bindings = nil)
        if JMESPath::Util.falsey?(@test.visit(value, bindings))
          nil
        else
          @child.visit(value, bindings)
        end
      end

      def optimize
        test = @test.optimize
        if (new_type = ComparatorCondition::COMPARATOR_TO_CONDITION[@test.class])
          new_type.new(test.left, test.right, @child).optimize
        else
          self.class.new(test, @child.optimize)
        end
      end
    end

    class ComparatorCondition < Node
      COMPARATOR_TO_CONDITION = {}
      COMPARABLE_TYPES = [Numeric, String].freeze

      def initialize(left, right, child)
        @left = left
        @right = right
        @child = child
      end

      def visit(_value, _bindings = nil)
        nil
      end

      private

      def comparable?(left_value, right_value)
        COMPARABLE_TYPES.any? do |type|
          left_value.is_a?(type) && right_value.is_a?(type)
        end
      end
    end

    class EqCondition < ComparatorCondition
      COMPARATOR_TO_CONDITION[Comparators::Eq] = self

      def visit(value, bindings = nil)
        Util.as_json(@left.visit(value, bindings)) == Util.as_json(@right.visit(value, bindings)) ? @child.visit(value, bindings) : nil
      end

      def optimize
        if @right.is_a?(Literal)
          LiteralRightEqCondition.new(@left, @right, @child)
        else
          self
        end
      end
    end

    class LiteralRightEqCondition < EqCondition
      def initialize(left, right, child)
        super
        @right = @right.value
      end

      def visit(value, bindings = nil)
        Util.as_json(@left.visit(value, bindings)) == @right ? @child.visit(value, bindings) : nil
      end
    end

    class NeqCondition < ComparatorCondition
      COMPARATOR_TO_CONDITION[Comparators::Neq] = self

      def visit(value, bindings = nil)
        Util.as_json(@left.visit(value, bindings)) != Util.as_json(@right.visit(value, bindings)) ? @child.visit(value, bindings) : nil
      end

      def optimize
        if @right.is_a?(Literal)
          LiteralRightNeqCondition.new(@left, @right, @child)
        else
          self
        end
      end
    end

    class LiteralRightNeqCondition < NeqCondition
      def initialize(left, right, child)
        super
        @right = @right.value
      end

      def visit(value, bindings = nil)
        Util.as_json(@left.visit(value, bindings)) != @right ? @child.visit(value, bindings) : nil
      end
    end

    class GtCondition < ComparatorCondition
      COMPARATOR_TO_CONDITION[Comparators::Gt] = self

      def visit(value, bindings = nil)
        left_value = @left.visit(value, bindings)
        right_value = @right.visit(value, bindings)
        comparable?(left_value, right_value) && left_value > right_value ? @child.visit(value, bindings) : nil
      end
    end

    class GteCondition < ComparatorCondition
      COMPARATOR_TO_CONDITION[Comparators::Gte] = self

      def visit(value, bindings = nil)
        left_value = @left.visit(value, bindings)
        right_value = @right.visit(value, bindings)
        comparable?(left_value, right_value) && left_value >= right_value ? @child.visit(value, bindings) : nil
      end
    end

    class LtCondition < ComparatorCondition
      COMPARATOR_TO_CONDITION[Comparators::Lt] = self

      def visit(value, bindings = nil)
        left_value = @left.visit(value, bindings)
        right_value = @right.visit(value, bindings)
        comparable?(left_value, right_value) && left_value < right_value ? @child.visit(value, bindings) : nil
      end
    end

    class LteCondition < ComparatorCondition
      COMPARATOR_TO_CONDITION[Comparators::Lte] = self

      def visit(value, bindings = nil)
        left_value = @left.visit(value, bindings)
        right_value = @right.visit(value, bindings)
        comparable?(left_value, right_value) && left_value <= right_value ? @child.visit(value, bindings) : nil
      end
    end
  end
end
