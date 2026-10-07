# frozen_string_literal: true
require 'spec_helper'

module JMESPath
  describe 'arithmetic extension' do
    def parse(expression, options = {})
      ArithmeticParser.new(options).parse(expression)
    end

    def search(expression, data, options = {})
      JMESPath.search(expression, data, options.merge(use_arithmetic: true))
    end

    describe 'evaluation' do
      it 'computes unit price times quantity' do
        data = { 'price' => 3, 'quantity' => 4 }
        expect(search('price * quantity', data)).to eq(12)
      end

      it 'supports addition and subtraction' do
        expect(search('a + b', 'a' => 1, 'b' => 2)).to eq(3)
        expect(search('a - b', 'a' => 5, 'b' => 2)).to eq(3)
      end

      it 'supports multiplication, division and modulo' do
        expect(search('a * b', 'a' => 6, 'b' => 7)).to eq(42)
        expect(search('a / b', 'a' => 6, 'b' => 3)).to eq(2)
        expect(search('a % b', 'a' => 8, 'b' => 3)).to eq(2)
      end

      it 'supports unary plus and minus' do
        expect(search('+a', 'a' => 3)).to eq(3)
        expect(search('-a', 'a' => 3)).to eq(-3)
        expect(search('--a', 'a' => 3)).to eq(3)
      end

      it 'is left associative within the same precedence level' do
        expect(search('10 - 2 - 3', {})).to eq(5)
        expect(search('2 * 3 / 4', {})).to eq(1.5)
      end

      it 'gives multiplicative operators higher precedence than additive' do
        expect(search('2 + 3 * 4', {})).to eq(14)
        expect(search('2 * 3 + 4', {})).to eq(10)
        expect(search('10 / 2 + 1', {})).to eq(6)
        expect(search('10 % 3 + 1', {})).to eq(2)
      end

      it 'gives unary operators higher precedence than multiplicative' do
        expect(search('2 * -3', {})).to eq(-6)
        expect(search('-2 * 3', {})).to eq(-6)
        expect(search('+2 + +3', {})).to eq(5)
      end

      it 'gives arithmetic higher precedence than comparisons' do
        expect(search('a > 1 + 1', 'a' => 5)).to eq(true)
        expect(search('1 + 1 == 2', {})).to eq(true)
      end

      it 'gives arithmetic higher precedence than logical operators' do
        expect(search('`true` && 1 + 1', {})).to eq(2)
        expect(search('`false` || 2 * 3', {})).to eq(6)
      end

      it 'gives pipe lower precedence than arithmetic' do
        data = { 'a' => { 'b' => 3 } }
        expect(search('a | b * 2', data)).to eq(6)
      end

      it 'gives subexpression access higher precedence than unary operators' do
        expect(search('-a.b', 'a' => { 'b' => 4 })).to eq(-4)
      end

      it 'honors parentheses for grouping' do
        expect(search('(2 + 3) * 4', {})).to eq(20)
        expect(search('-(a + b)', 'a' => 1, 'b' => 2)).to eq(-3)
      end

      it 'accepts float literals and JSON literals' do
        expect(search('1.5 / 0.25', {})).to eq(6.0)
        expect(search('1.5e2 * 2', {})).to eq(300.0)
        expect(search('`1.5` * 2', {})).to eq(3.0)
      end

      it 'works inside filters' do
        data = {
          'items' => [
            { 'price' => 3, 'quantity' => 4, 'name' => 'a' },
            { 'price' => 1, 'quantity' => 1, 'name' => 'b' }
          ]
        }
        expect(search('items[?price * quantity > 10].name', data)).to eq(['a'])
      end

      it 'works with projections and pipes' do
        expect(search('items[].price * quantity',
                      'items' => [{ 'price' => 2, 'quantity' => 3 }])).to eq([6])
        expect(search('foo.* | [0].a * 2', 'foo' => { 'x' => { 'a' => 3 } })).to eq(6)
      end

      it 'works inside multi-select lists and function arguments' do
        expect(search('[1 + 1, 2 * 3]', {})).to eq([2, 6])
        expect(search('sum(foo[].a * quantity)',
                      'foo' => [{ 'a' => 2, 'quantity' => 3 }])).to eq(6)
      end
    end

    describe 'numeric typing' do
      it 'only accepts JSON numbers' do
        expect { search('a * b', 'a' => true, 'b' => 2) }
          .to raise_error(Errors::InvalidTypeError)
        expect { search('a + b', 'a' => '1', 'b' => 2) }
          .to raise_error(Errors::InvalidTypeError)
        expect { search('-a', 'a' => nil) }
          .to raise_error(Errors::InvalidTypeError)
        expect { search('+a', 'a' => false) }
          .to raise_error(Errors::InvalidTypeError)
      end

      it 'returns nil for invalid operands when visit errors are disabled' do
        runtime = Runtime.new(use_arithmetic: true, disable_visit_errors: true)
        expect(runtime.search('a * b', 'a' => true, 'b' => 2)).to be_nil
        expect(runtime.search('-a', 'a' => 'x')).to be_nil
      end
    end

    describe 'division and modulo' do
      it 'keeps integer results exact for dividing integers' do
        expect(search('8 / 2', {})).to eql(4)
        expect(search('9007199254740994 / 2', {})).to eql(4503599627370497)
      end

      it 'uses true division when the quotient is fractional' do
        expect(search('7 / 2', {})).to eq(3.5)
        expect(search('10 / -4', {})).to eq(-2.5)
      end

      it 'preserves arbitrary integer precision' do
        expect(search('a * b', 'a' => 10**40, 'b' => 10**20)).to eq(10**60)
        expect(search('a / b', 'a' => 10**60, 'b' => 10**20)).to eq(10**40)
      end

      it 'uses floor semantics for integer modulo' do
        expect(search('7 % 3', {})).to eq(1)
        expect(search('-7 % 3', {})).to eq(2)
      end

      it 'raises a dedicated error on zero division or modulo' do
        expect { search('1 / 0', {}) }.to raise_error(Errors::DivisionByZeroError)
        expect { search('a / b', 'a' => 1.0, 'b' => 0.0) }
          .to raise_error(Errors::DivisionByZeroError)
        expect { search('1 % 0', {}) }.to raise_error(Errors::DivisionByZeroError)
      end

      it 'still raises on zero division when visit errors are disabled' do
        runtime = Runtime.new(use_arithmetic: true, disable_visit_errors: true)
        expect { runtime.search('1 / 0', {}) }
          .to raise_error(Errors::DivisionByZeroError)
      end

      it 'raises a dedicated error for non-finite results' do
        expect { search('1e308 * 10', {}) }.to raise_error(Errors::NonFiniteNumberError)
      end

      it 'rejects non-finite numeric literals at parse time' do
        expect { parse('1e400') }.to raise_error(Errors::SyntaxError)
      end
    end

    describe 'numeric budget' do
      it 'allows results within the configured limit' do
        expect(search('a * b', { 'a' => 5, 'b' => 3 }, max_number: 100)).to eq(15)
      end

      it 'raises when an operation exceeds the configured limit' do
        expect { search('a * b', { 'a' => 50, 'b' => 3 }, max_number: 100) }
          .to raise_error(Errors::NumberBudgetExceededError)
        expect { search('-a', { 'a' => 101 }, max_number: 100) }
          .to raise_error(Errors::NumberBudgetExceededError)
      end

      it 'still raises when visit errors are disabled' do
        runtime = Runtime.new(use_arithmetic: true,
                              disable_visit_errors: true,
                              max_number: 10)
        expect { runtime.search('9 * 9', {}) }
          .to raise_error(Errors::NumberBudgetExceededError)
      end
    end

    describe 'AST' do
      it 'builds the expected node tree' do
        ast = parse('(a + -b) * c')
        expect(ast).to be_a(Nodes::Multiply)
        expect(ast.left).to be_a(Nodes::Add)
        expect(ast.left.left).to be_a(Nodes::Field)
        expect(ast.left.right).to be_a(Nodes::Negate)
        expect(ast.right).to be_a(Nodes::Field)
      end
    end

    describe 'lexer compatibility' do
      it 'keeps negative indices and projection stars distinct' do
        types = Lexer.new.tokenize('a[*-1]').map(&:type)
        expect(types).to eq(%i[identifier lbracket star minus number
                               rbracket eof])
      end

      it 'still lexes projection stars as before' do
        expect(Lexer.new.tokenize('foo[*]').map(&:value))
          .to eq(['foo', '[', '*', ']', nil])
      end

      it 'supports negative indices and slices with the extension on' do
        expect(search('a[-1]', 'a' => [1, 2])).to eq(2)
        expect(search('a[::-1]', 'a' => [1, 2, 3])).to eq([3, 2, 1])
        expect(search('a[10:0:-1]', 'a' => (0..10).to_a))
          .to eq([10, 9, 8, 7, 6, 5, 4, 3, 2, 1])
      end

      it 'keeps index brackets and arithmetic list brackets distinct' do
        expect(search('[1]', 'a' => 1)).to be_nil
        expect(search('[1 + 1]', {})).to eq([2])
      end
    end

    describe 'opt-in behavior' do
      it 'rejects arithmetic operators without the extension' do
        expect { JMESPath.search('a + b', 'a' => 1, 'b' => 2) }
          .to raise_error(Errors::SyntaxError)
        expect { JMESPath.search('-a', 'a' => 1) }
          .to raise_error(Errors::SyntaxError)
        expect { JMESPath.search('a / b', 'a' => 1, 'b' => 2) }
          .to raise_error(Errors::SyntaxError)
      end

      it 'keeps negative indices and projections working without the extension' do
        expect(JMESPath.search('a[-1]', 'a' => [1, 2])).to eq(2)
        expect(JMESPath.search('a[*]', 'a' => [1, 2])).to eq([1, 2])
        expect(JMESPath.search('a[::-1]', 'a' => [1, 2, 3])).to eq([3, 2, 1])
      end
    end
  end
end
