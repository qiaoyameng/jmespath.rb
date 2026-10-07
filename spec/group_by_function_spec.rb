# frozen_string_literal: true
require 'spec_helper'

module JMESPath
  describe 'group_by function' do
    # Naive O(n^2) reference implementation used to cross-check the
    # hash-based implementation. Groups items by JMESPath value
    # equality, preserving first-appearance group order and input
    # order within each group.
    def reference_group_by(items)
      items.each_with_object([]) do |item, groups|
        if (group = groups.find { |g| json_value_equal?(g['key'], item) })
          group['items'] << item
        else
          groups << { 'key' => item, 'items' => [item] }
        end
      end
    end

    def json_value_equal?(left, right)
      normalize_json(left) == normalize_json(right)
    end

    def normalize_json(value)
      if value.nil?
        [:null]
      elsif value == true || value == false
        [:boolean, value]
      elsif value.is_a?(Numeric)
        [:number, value.to_r]
      elsif value.respond_to?(:to_str)
        [:string, value.to_str]
      elsif value.respond_to?(:to_ary)
        [:array, value.to_ary.map { |e| normalize_json(e) }]
      elsif value.respond_to?(:to_hash)
        pairs = value.to_hash.map { |k, v| [k.to_s, normalize_json(v)] }
        [:object, pairs.sort_by(&:first)]
      end
    end

    def normalized(result)
      normalize_json(result)
    end

    it 'groups by a string key expression in first-appearance order' do
      data = [
        { 'k' => 'b', 'n' => 1 },
        { 'k' => 'a', 'n' => 2 },
        { 'k' => 'b', 'n' => 3 }
      ]
      expect(JMESPath.search('group_by(@, &k)', data)).to eq([
        { 'key' => 'b', 'items' => [{ 'k' => 'b', 'n' => 1 }, { 'k' => 'b', 'n' => 3 }] },
        { 'key' => 'a', 'items' => [{ 'k' => 'a', 'n' => 2 }] }
      ])
    end

    it 'returns an empty array for an empty input array' do
      expect(JMESPath.search('group_by(@, &k)', [])).to eq([])
    end

    it 'does not stringify object keys' do
      data = [{ 'a' => 1, 'b' => 2 }, { 'a' => 1, 'b' => 3 }]
      result = JMESPath.search('group_by(@, &@)', data)
      expect(result.length).to eq(2)
      expect(result[0]['key']).to eq({ 'a' => 1, 'b' => 2 })
      expect(result[0]['key']).to be_a(Hash)
    end

    it 'ignores object member order when grouping' do
      data = [{ 'a' => 1, 'b' => 2 }, { 'b' => 2, 'a' => 1 }]
      result = JMESPath.search('group_by(@, &@)', data)
      expect(result.length).to eq(1)
      expect(result[0]['items']).to eq(data)
    end

    it 'groups 1 and 1.0 together but keeps true and 1 apart' do
      result = JMESPath.search('group_by(@, &@)', [1, 1.0, true, 2])
      expect(result).to eq([
        { 'key' => 1, 'items' => [1, 1.0] },
        { 'key' => true, 'items' => [true] },
        { 'key' => 2, 'items' => [2] }
      ])
    end

    it 'treats nested array order as significant' do
      result = JMESPath.search('group_by(@, &@)', [[1, 2], [2, 1], [1, 2]])
      expect(result).to eq([
        { 'key' => [1, 2], 'items' => [[1, 2], [1, 2]] },
        { 'key' => [2, 1], 'items' => [[2, 1]] }
      ])
    end

    it 'does not modify elements or their keys' do
      key = { 'a' => 1 }.freeze
      item = { 'k' => key }.freeze
      data = [item, { 'k' => { 'a' => 1.0 }.freeze }.freeze].freeze
      result = JMESPath.search('group_by(@, &k)', data)
      expect(result.length).to eq(1)
      expect(result[0]['key']).to be(key)
      expect(result[0]['items'][0]).to be(item)
    end

    it 'matches a naive pairwise reference on complex composite keys' do
      pool = [
        { 'a' => 1, 'b' => [1, 2, { 'c' => 'x' }], 'd' => true },
        { 'd' => true, 'b' => [1.0, 2, { 'c' => 'x' }], 'a' => 1.0 },
        { 'a' => 1, 'b' => [1, 2, { 'c' => 'x' }], 'd' => false },
        { 'a' => 1, 'b' => [1, 2, { 'c' => 'x' }, nil], 'd' => true },
        [1, [2, 3], { 'k' => nil }],
        [1, [3, 2], { 'k' => nil }],
        [[1, 2], { 'k' => nil }, 1],
        'str', 1, 1.0, 2, true, false, nil, 0.5,
        { 'nested' => { 'x' => [true, nil, 's'] } },
        { 'nested' => { 'x' => [true, nil, 's', 0] } }
      ]
      rng = Random.new(42)
      data = Array.new(200) { pool[rng.rand(pool.length)] }
      expected = reference_group_by(data)
      actual = JMESPath.search('group_by(@, &@)', data)
      expect(normalized(actual)).to eq(normalized(expected))
      expect(actual.length).to be < pool.length
    end

    it 'evaluates the key expression exactly once per element' do
      counting = Class.new(Nodes::Expression) do
        attr_reader :eval_count

        def initialize(*args)
          super
          @eval_count = 0
        end

        def eval(value)
          @eval_count += 1
          super
        end
      end.new(Nodes::Current.new)
      data = Array.new(10_000) { |i| i % 50 }
      function = Nodes::GroupByFunction.new([Nodes::Literal.new(data), counting])
      result = function.visit(nil)
      expect(counting.eval_count).to eq(10_000)
      expect(result.length).to eq(50)
      expect(result.first).to eq({ 'key' => 0, 'items' => Array.new(200, 0) })
    end

    describe Nodes::GroupByFunction::KeyTable do
      # Array with a forced hash code to simulate hash collisions.
      class CollidingKey < Array
        def hash
          42
        end
      end

      it 'verifies equality on hash collisions' do
        table = Nodes::GroupByFunction::KeyTable.new
        key_a = CollidingKey[:string, 'a']
        key_b = CollidingKey[:string, 'b']
        table.store(key_a, :group_a)
        expect(table.fetch(key_b)).to be_nil
        expect(table.fetch(CollidingKey[:string, 'a'])).to eq(:group_a)
        expect(table.comparisons).to eq(2)
      end

      it 'performs a linear number of comparisons for larger inputs' do
        table = Nodes::GroupByFunction::KeyTable.new
        inserts = 0
        20_000.times do |i|
          canonical = [:string, "key-#{i % 100}"]
          inserts += 1
          table.store(canonical, canonical) unless table.fetch(canonical)
        end
        # A pairwise all-to-all comparison would need on the order of
        # 20_000 * 100 comparisons; hashing stays close to one
        # comparison per insert.
        expect(table.comparisons).to be <= inserts + 1_000
      end
    end

    it 'raises an input-position error for cyclic keys' do
      cyclic = []
      cyclic << cyclic
      expect { JMESPath.search('group_by(@, &@)', ['ok', cyclic]) }
        .to raise_error(Errors::InvalidValueError, /cyclic key at index 1/)
    end

    it 'raises an input-position error for non-JSON keys' do
      expect { JMESPath.search('group_by(@, &@)', ['ok', Object.new]) }
        .to raise_error(Errors::InvalidTypeError, /index 1/)
    end

    it 'raises an input-position error for non-JSON numbers' do
      expect { JMESPath.search('group_by(@, &@)', [1.0 / 0.0]) }
        .to raise_error(Errors::InvalidValueError, /index 0/)
    end

    it 'raises an input-position error for non-string object keys' do
      expect { JMESPath.search('group_by(@, &@)', [{ 1 => 'a' }]) }
        .to raise_error(Errors::InvalidTypeError, /index 0/)
    end

    it 'raises on invalid arity' do
      expect { JMESPath.search('group_by(@)', []) }
        .to raise_error(Errors::InvalidArityError)
    end

    it 'raises when the first argument is not an array' do
      expect { JMESPath.search('group_by(@, &@)', 'nope') }
        .to raise_error(Errors::InvalidTypeError)
    end

    it 'returns nil instead of raising when visit errors are disabled' do
      runtime = Runtime.new(disable_visit_errors: true)
      expect(runtime.search('group_by(@)', [])).to be_nil
      expect(runtime.search('group_by(@, &@)', [Object.new])).to be_nil
    end
  end
end
