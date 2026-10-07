# frozen_string_literal: true
require 'set'

module JMESPath
  # Opt-in parser enabling the arithmetic extension.
  #
  # Adds unary `+`/`-` and the binary `+`, `-`, `*`, `/` and `%`
  # operators. Operator precedence, from loosest to tightest, is:
  #
  #   pipe (`|`) < or (`||`) < and (`&&`) < comparison (`<`, `<=`,
  #   `==`, `!=`, `>=`, `>`) < additive (`+`, `-`) < multiplicative
  #   (`*`, `/`, `%`) < unary (`+`, `-`) < subexpression (`.`, `[]`)
  #
  # Only JSON numbers are accepted as operands; booleans, strings and
  # `null` are never implicitly converted.
  #
  # @api private
  class ArithmeticParser < Parser
    UNARY_BINDING_POWER = 18
    ADDITIVE_BINDING_POWER = 12
    MULTIPLICATIVE_BINDING_POWER = 15

    ARITHMETIC_INFIX_OPERATORS = Set.new([
      Lexer::T_PLUS,
      Lexer::T_MINUS,
      Lexer::T_STAR,
      Lexer::T_SLASH,
      Lexer::T_PERCENT
    ]).freeze

    private

    def nud_number(stream)
      value = stream.token.value
      stream.next
      Nodes::Literal.new(value)
    end

    def nud_minus(stream)
      stream.next
      Nodes::Negate.new(expr(stream, UNARY_BINDING_POWER), arithmetic_options)
    end

    def nud_plus(stream)
      stream.next
      Nodes::UnaryPlus.new(expr(stream, UNARY_BINDING_POWER), arithmetic_options)
    end

    def led_plus(stream, left)
      binary(stream, left, Nodes::Add, ADDITIVE_BINDING_POWER)
    end

    def led_minus(stream, left)
      binary(stream, left, Nodes::Subtract, ADDITIVE_BINDING_POWER)
    end

    def led_star(stream, left)
      binary(stream, left, Nodes::Multiply, MULTIPLICATIVE_BINDING_POWER)
    end

    def led_slash(stream, left)
      binary(stream, left, Nodes::Divide, MULTIPLICATIVE_BINDING_POWER)
    end

    def led_percent(stream, left)
      binary(stream, left, Nodes::Modulo, MULTIPLICATIVE_BINDING_POWER)
    end

    def binary(stream, left, node_class, binding_power)
      stream.next
      right = expr(stream, binding_power)
      node_class.new(left, right, arithmetic_options)
    end

    def arithmetic_options
      {
        disable_visit_errors: @disable_visit_errors,
        max_number: @max_number
      }
    end

    def arithmetic_subscript?(stream)
      stream.token.type == Lexer::T_NUMBER &&
        ARITHMETIC_INFIX_OPERATORS.include?(stream.lookahead(1).type)
    end

    # Arithmetic tokens (binding power 12-18) are not projection
    # continuations; only subexpression-style tokens (dot, bracket,
    # filter, flatten, projection star at bp >= 20) continue one.
    def parse_projection(stream, binding_power)
      type = stream.token.type
      if stream.token.binding_power < 10
        CURRENT_NODE
      elsif type == :dot
        stream.next(match: AFTER_DOT)
        parse_dot(stream, binding_power)
      elsif type == :lbracket || type == :filter
        expr(stream, binding_power)
      else
        raise Errors::SyntaxError, 'syntax error after projection'
      end
    end

    def nud_lbracket(stream)
      stream.next
      type = stream.token.type
      if arithmetic_subscript?(stream)
        parse_multi_select_list(stream)
      elsif type == :number || type == :colon || type == :minus
        parse_array_index_expression(stream)
      else
        parse_wildcard_array(stream)
      end
    end

    def led_lbracket(stream, left)
      stream.next(match: Set.new([:number, :colon, :star, :minus]))
      if arithmetic_subscript?(stream)
        Nodes::Subexpression.new(left, parse_multi_select_list(stream))
      elsif stream.token.type == :number ||
            stream.token.type == :colon ||
            stream.token.type == :minus
        right = parse_array_index_expression(stream)
        Nodes::Subexpression.new(left, right)
      else
        parse_wildcard_array(stream, left)
      end
    end
  end
end
