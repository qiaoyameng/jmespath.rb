# frozen_string_literal: true
require 'spec_helper'

module JMESPath
  describe 'let expressions' do
    it 'evaluates a bound expression once and makes it available to nested projections' do
      data = { 'items' => [{ 'name' => 'a', 'age' => 2 }, { 'name' => 'b', 'age' => 1 }] }
      runtime = Runtime.new(cache_expressions: false)
      expression = 'let $threshold = length(@.items) in items[?age >= $threshold].name'

      expect(runtime.search(expression, data)).to eq(['a'])
    end

    it 'visits the bound expression only once for multiple variable references' do
      count = 0
      value_node = Class.new(Nodes::Node) do
        define_method(:initialize) { |counter| @counter = counter }
        define_method(:visit) do |_value, _bindings|
          @counter << @counter.size
          @counter.size
        end
      end.new(count)
      body = Nodes::MultiSelectList.new([
                                          Nodes::Variable.new('$x', 0),
                                          Nodes::Variable.new('$x', 4)
                                        ])

      expect(Nodes::Let.new('$x', value_node, body).visit(nil)).to eq([1, 1])
    end

    it 'lets nested bindings shadow outer bindings' do
      expression = 'let $value = `1` in let $value = `2` in $value'
      expect(JMESPath.search(expression, {})).to eq(2)
    end

    it 'restores an outer binding after a nested let' do
      expression = '[let $value = `1` in $value, $value]'
      expect { JMESPath.search(expression, {}) }.to raise_error(Errors::UnboundVariableError)
    end

    it 'rejects forward references' do
      expression = 'let $value = $other in let $other = `2` in $value'
      expect { JMESPath.search(expression, {}) }.to raise_error(Errors::UnboundVariableError) do |error|
        expect(error.position).to eq(13)
      end
    end

    it 'reports the source position of an unbound variable' do
      expect { JMESPath.search('length($x)', {}) }.to raise_error(Errors::UnboundVariableError) do |error|
        expect(error.message).to include('unbound variable `$x` at position 7')
        expect(error.position).to eq(7)
      end
    end

    it 'keeps variables in a separate namespace from data fields' do
      expression = 'let $x = `bound` in {variable: $x, field: x}'
      expect(JMESPath.search(expression, { 'x' => 'field' })).to eq(
        'variable' => 'bound',
        'field' => 'field'
      )
    end

    it 'does not evaluate a let in an untaken short-circuit branch' do
      expression = '`true` || let $boom = boom in $boom'
      expect(JMESPath.search(expression, {})).to eq(true)
    end

    it 'captures declaration-time bindings in expression references while @ stays applied data' do
      expression = 'let $prefix = @.prefix in map(&[@.name, $prefix], items)'
      data = {
        'prefix' => 'top',
        'items' => [{ 'name' => 'a' }, { 'name' => 'b' }]
      }

      expect(JMESPath.search(expression, data)).to eq([['a', 'top'], ['b', 'top']])
    end

    it 'reuses one compiled expression concurrently without sharing binding values' do
      runtime = Runtime.new
      expression = 'let $expected = @.threshold in items[?score >= $expected].name'
      parsed = runtime.parser.parse(expression).optimize
      first = { 'threshold' => 10, 'items' => [{ 'name' => 'a', 'score' => 10 }] }
      second = { 'threshold' => 20, 'items' => [{ 'name' => 'b', 'score' => 20 }] }
      queue = Queue.new
      threads = [first, second].cycle(8).map.with_index do |data, index|
        Thread.new do
          queue << [index, parsed.visit(data)]
        end
      end
      results = threads.map { queue.pop }.sort_by(&:first).map(&:last)

      expect(results).to all(be_an(Array)).and all(have_attributes(size: 1))
      expect(results.uniq).to contain_exactly(['a'], ['b'])
    end
  end
end
