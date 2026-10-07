# frozen_string_literal: true
require 'spec_helper'

module JMESPath
  describe 'let expressions' do
    it 'binds a variable and reads it back' do
      expect(JMESPath.search('let $x = foo in $x', 'foo' => 1)).to eq(1)
    end

    it 'evaluates the bound expression once and reuses the value' do
      expression = 'let $x = foo.bar in [$x, $x, $x.baz]'
      data = { 'foo' => { 'bar' => { 'baz' => 2 } } }
      expect(JMESPath.search(expression, data)).to eq([
        { 'baz' => 2 }, { 'baz' => 2 }, 2
      ])
    end

    it 'supports multiple bindings in a single let' do
      expect(JMESPath.search('let $a = `1`, $b = `2` in [$a, $b]', {})).to eq([1, 2])
    end

    it 'binds values derived from the current node' do
      expression = 'items[].let $n = name in {name: $n, size: length($n)}'
      data = { 'items' => [{ 'name' => 'a' }, { 'name' => 'b' }] }
      expect(JMESPath.search(expression, data)).to eq([
        { 'name' => 'a', 'size' => 1 },
        { 'name' => 'b', 'size' => 1 }
      ])
    end

    it 'allows nested lets to shadow outer bindings' do
      expression = 'let $x = `1` in let $x = `2` in $x'
      expect(JMESPath.search(expression, {})).to eq(2)
    end

    it 'restores the outer binding after a nested let' do
      expression = 'let $x = `1` in [let $x = `2` in $x, $x]'
      expect(JMESPath.search(expression, {})).to eq([2, 1])
    end

    it 'allows nested lets to read outer bindings' do
      expression = 'let $a = `1` in let $b = `2` in [$a, $b]'
      expect(JMESPath.search(expression, {})).to eq([1, 2])
    end

    it 'rejects duplicate bindings at the same level' do
      expect do
        JMESPath.search('let $x = `1`, $x = `2` in $x', {})
      end.to raise_error(Errors::SyntaxError, /duplicate binding for `\$x`/)
    end

    it 'rejects self references in a binding' do
      expect do
        JMESPath.search('let $x = $x in $x', {})
      end.to raise_error(Errors::UnboundVariableError, /`\$x`/)
    end

    it 'rejects forward references to sibling bindings' do
      expect do
        JMESPath.search('let $a = $b, $b = `1` in $a', {})
      end.to raise_error(Errors::UnboundVariableError, /`\$b`/)
    end

    it 'raises an unbound variable error with the source position' do
      expression = 'let $x = foo in [$x, $missing]'
      expect do
        JMESPath.search(expression, {})
      end.to raise_error(
        Errors::UnboundVariableError,
        "unbound variable `$missing` at position 21 in expression `#{expression}`"
      )
    end

    it 'keeps variables and data fields in separate namespaces' do
      expression = 'let $threshold = `10` in {bound: $threshold, field: threshold}'
      expect(JMESPath.search(expression, 'threshold' => 5)).to eq(
        'bound' => 10, 'field' => 5
      )
    end

    it 'captures let bindings in expression references' do
      expression = 'let $x = `1` in map(&[$x, @], items)'
      data = { 'items' => [10, 20] }
      expect(JMESPath.search(expression, data)).to eq([[1, 10], [1, 20]])
    end

    it 'captures bindings at declaration time, not at application time' do
      expression = 'let $x = `1` in map(&$x, [let $x = `2` in $x])'
      expect(JMESPath.search(expression, {})).to eq([1])
    end

    it 'applies @ to the data node the expression is applied to' do
      expression = 'let $x = `1` in map(&{applied: @, captured: $x}, items)'
      data = { 'items' => [10, 20] }
      expect(JMESPath.search(expression, data)).to eq([
        { 'applied' => 10, 'captured' => 1 },
        { 'applied' => 20, 'captured' => 1 }
      ])
    end

    it 'does not evaluate lets on untaken short-circuit branches' do
      expect(JMESPath.search('a || let $x = b in $x', 'a' => 1, 'b' => 2)).to eq(1)
      expect(JMESPath.search('a && let $x = b in $x', 'a' => false, 'b' => 2)).to be(false)
      expect(JMESPath.search('a || let $x = b in $x', 'a' => nil, 'b' => 2)).to eq(2)
    end

    it 'reads outer thresholds from nested projections' do
      expression = 'let $t = `2` in items[?qty > $t].name'
      data = { 'items' => [{ 'qty' => 1, 'name' => 'a' }, { 'qty' => 3, 'name' => 'b' }] }
      expect(JMESPath.search(expression, data)).to eq(['b'])
    end

    it 'does not share bindings between searches of a cached expression' do
      runtime = Runtime.new
      expression = 'let $x = a in $x'
      expect(runtime.search(expression, 'a' => 1)).to eq(1)
      expect(runtime.search(expression, 'a' => 2)).to eq(2)
    end

    it 'supports concurrent reuse of the same compiled expression' do
      runtime = Runtime.new
      expression = 'let $t = threshold in items[?qty > $t].name'
      results = 20.times.map do |i|
        Thread.new do
          data = { 'threshold' => i, 'items' => [{ 'qty' => i, 'name' => 'lo' }, { 'qty' => i + 1, 'name' => 'hi' }] }
          runtime.search(expression, data)
        end
      end.map(&:value)
      expect(results).to eq(20.times.map { ['hi'] })
    end

    it 'still parses let as a field name when not followed by a variable' do
      expect(JMESPath.search('let', 'let' => 1)).to eq(1)
      expect(JMESPath.search('foo.let', 'foo' => { 'let' => 2 })).to eq(2)
    end

    it 'still parses in as a field name' do
      expect(JMESPath.search('foo.in', 'foo' => { 'in' => 3 })).to eq(3)
    end

    it 'requires an equals sign after the variable name' do
      expect do
        JMESPath.search('let $x foo in $x', {})
      end.to raise_error(Errors::SyntaxError, /expected `=/)
    end

    it 'requires in after the bindings' do
      expect do
        JMESPath.search('let $x = `1` $x', {})
      end.to raise_error(Errors::SyntaxError, /expected `in`/)
    end
  end
end
