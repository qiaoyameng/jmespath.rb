# frozen_string_literal: true
require 'spec_helper'

module JMESPath
  describe 'arithmetic extension' do
    def search(expression, data = {}, options = {})
      JMESPath.search(expression, data, options.merge(arithmetic: true))
    end

    def parse(expression, options = {})
      Parser.new(options.merge(arithmetic: true, cache_expressions: false)).parse(expression)
    end

    it 'multiplies a unit price by a quantity' do
      data = { 'unit_price' => 12, 'quantity' => 3 }
      expect(search('unit_price * quantity', data)).to eq(36)
    end

    it 'keeps integer precision for integer addition, subtraction, multiplication and modulo' do
      expect(search('`7` + `2`', {})).to eq(9)
      expect(search('`7` - `2`', {})).to eq(5)
      expect(search('`7` * `2`', {})).to eq(14)
      expect(search('`7` % `2`', {})).to eq(1)
      expect(search('`7` % `-2`', {})).to eq(-1)
      expect(search('`9007199254740993` + `1`', {})).to eq(9007199254740994)
      expect(search('`9007199254740993` * `2`', {})).to eq(18014398509481986)
    end

    it 'always performs division as floating point division' do
      expect(search('`10` / `5`', {})).to eq(2.0)
      expect(search('`10` / `4`', {})).to eq(2.5)
    end

    it 'applies unary positive and negative signs' do
      expect(search('+`2`', {})).to eq(2)
      expect(search('-`2`', {})).to eq(-2)
      expect(search('`1` - -`2`', {})).to eq(3)
      expect(search('`-2` + `1`', {})).to eq(-1)
    end

    it 'parses arithmetic below comparisons and logical operators and above pipes' do
      ast = parse('(`a` + `b`) * `c`')
      expect(ast).to be_a(Nodes::Arithmetic)
      expect(ast.operator).to eq(:multiply)
      expect(ast.left).to be_a(Nodes::Arithmetic)
      expect(ast.left.operator).to eq(:plus)

      expect(parse('`1` + `2` * `3`').right.operator).to eq(:multiply)
      expect(parse('`2` * `3` + `1`').left.operator).to eq(:multiply)
      expect(search('`1` + `2` == `3` && `4` | `4`', {})).to eq(4)

      negation = parse('-a.b')
      expect(negation).to be_a(Nodes::UnaryArithmetic)
      expect(negation.operator).to eq(:minus)
      expect(negation.child).to be_a(Nodes::Subexpression)
    end

    it 'works inside filters and pipes' do
      data = {
        'items' => [
          { 'name' => 'small', 'unit_price' => 2, 'quantity' => 1 },
          { 'name' => 'large', 'unit_price' => 3, 'quantity' => 10 }
        ]
      }
      expression = 'items[?unit_price * quantity > `10`] | [0].name'
      ast = parse(expression)
      expect(ast).to be_a(Nodes::Subexpression)
      expect(search(expression, data)).to eq('large')
    end

    it 'does not turn booleans, strings or null into numbers' do
      expect { search('`true` + `1`', {}) }.to raise_error(Errors::InvalidTypeError)
      expect { search('`"2"` * `1`', {}) }.to raise_error(Errors::InvalidTypeError)
      expect { search('`null` - `1`', {}) }.to raise_error(Errors::InvalidTypeError)
    end

    it 'raises dedicated errors for zero division, non-finite results and budget violations' do
      expect { search('`1` / `0`', {}) }.to raise_error(Errors::DivisionByZeroError)
      expect { search('`1` % `0`', {}) }.to raise_error(Errors::DivisionByZeroError)
      expect { search('`1.0e308` * `1.0e100`', {}) }.to raise_error(Errors::NonFiniteResultError)
      expect { search('`2` * `3`', {}, number_budget: 5) }
        .to raise_error(Errors::NumericBudgetExceededError)
    end

    it 'keeps dedicated arithmetic errors enabled with disable_visit_errors' do
      options = { disable_visit_errors: true }
      budget_options = { disable_visit_errors: true, number_budget: 5 }
      expect { search('`true` + `1`', {}, options) }.not_to raise_error
      expect(search('`true` + `1`', {}, options)).to be_nil
      expect { search('`1` / `0`', {}, options) }.to raise_error(Errors::DivisionByZeroError)
      expect { search('`1.0e308` * `1.0e100`', {}, options) }
        .to raise_error(Errors::NonFiniteResultError)
      expect { search('`2` * `3`', {}, budget_options) }
        .to raise_error(Errors::NumericBudgetExceededError)
    end

    it 'checks numeric operands against the configured budget' do
      expect { search('`10` + `1`', {}, number_budget: 9) }
        .to raise_error(Errors::NumericBudgetExceededError)
    end

    it 'accepts explicit option aliases' do
      expect(JMESPath.search('`2` * `3`', {}, enable_arithmetic: true)).to eq(6)
      expect do
        JMESPath.search('`2` * `3`', {}, arithmetic_extensions: true, numeric_budget: 5)
      end.to raise_error(Errors::NumberBudgetExceededError)
    end

    it 'supports an explicitly configured arithmetic lexer' do
      parser = Parser.new(arithmetic: true, lexer: Lexer.new(arithmetic: true))
      expect(parser.parse('`2` * `3`')).to be_a(Nodes::Arithmetic)
    end

    it 'preserves negative array indexes and wildcard projections' do
      data = { 'numbers' => [1, 2, 3], 'object' => { 'a' => 1, 'b' => 2 } }
      expect(parse('numbers[-1]')).to be_a(Nodes::Subexpression)
      expect(search('numbers[-1]', data)).to eq(3)
      expect(search('numbers[ - 1]', data)).to eq(3)
      expect(parse('numbers[*]')).to be_a(Nodes::ArrayProjection)
      expect(parse('numbers.*')).to be_a(Nodes::ObjectProjection)
      expect(search('numbers[*]', data)).to eq([1, 2, 3])
      expect(search('object.*', data)).to contain_exactly(1, 2)
    end

    it 'is disabled by default' do
      expect { JMESPath.search('`1` + `1`', {}) }.to raise_error(Errors::SyntaxError)
      expect(JMESPath.search('foo[-1]', 'foo' => [1, 2])).to eq(2)
      expect(JMESPath.search('foo[*]', 'foo' => [1, 2])).to eq([1, 2])
    end
  end
end
