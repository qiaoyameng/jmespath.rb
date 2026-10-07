# frozen_string_literal: true
module JMESPath
  # @api private
  module Nodes
    class Current < Node
      def visit(value, _scope = nil)
        value
      end
    end
  end
end
