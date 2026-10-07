# frozen_string_literal: true
require 'spec_helper'

module GroupBySpecCounters
  class << self
    attr_accessor :evals, :comparisons, :inside_comparison
  end
  self.evals = 0
  self.comparisons = 0
  self.inside_comparison = false
end

module GroupByEvalCounter
  def eval(value)
    GroupBySpecCounters.evals += 1
    super
  end
end

module GroupByComparisonCounter
  def value_equal?(left, right)
    top_level = !GroupBySpecCounters.inside_comparison
    GroupBySpecCounters.comparisons += 1 if top_level
    GroupBySpecCounters.inside_comparison = true
    begin
      super
    ensure
      GroupBySpecCounters.inside_comparison = false if top_level
    end
  end
end

JMESPath::Nodes::Expression.prepend(GroupByEvalCounter)
JMESPath::Nodes::GroupByKey.singleton_class.prepend(GroupByComparisonCounter)

module JMESPath
  describe 'group_by()' do
    # O(n^2) naive reference implementation used to validate results.
    def naive_group_by(items)
      groups = []
      items.each do |item|
        key = yield(item)
        group = groups.find { |g| naive_equal?(g['key'], key) }
        if group
          group['items'] << item
        else
          groups << { 'key' => key, 'items' => [item] }
        end
      end
      groups
    end

    def naive_equal?(left, right)
      if left.is_a?(Numeric) || right.is_a?(Numeric)
        left.is_a?(Numeric) && right.is_a?(Numeric) && left == right
      elsif left.is_a?(Hash) && right.is_a?(Hash)
        left.size == right.size && left.all? do |k, v|
          right.any? { |k2, v2| k.to_s == k2.to_s && naive_equal?(v, v2) }
        end
      elsif left.is_a?(Array) && right.is_a?(Array)
        left.size == right.size && left.zip(right).all? { |a, b| naive_equal?(a, b) }
      else
        left == right
      end
    end

    it 'groups by first appearance and preserves input order within groups' do
      data = [{ 'k' => 'b' }, { 'k' => 'a' }, { 'k' => 'b' }, { 'k' => 'a' }, { 'k' => 'c' }]
      expect(JMESPath.search('group_by(@, &k)', data)).to eq([
        { 'key' => 'b', 'items' => [{ 'k' => 'b' }, { 'k' => 'b' }] },
        { 'key' => 'a', 'items' => [{ 'k' => 'a' }, { 'k' => 'a' }] },
        { 'key' => 'c', 'items' => [{ 'k' => 'c' }] }
      ])
    end

    it 'returns an empty array for an empty input array' do
      expect(JMESPath.search('group_by(`[]`, &@)', nil)).to eq([])
    end

    it 'keeps keys as their original JSON values instead of stringifying them' do
      data = [{ 'k' => { 'a' => 1 } }, { 'k' => [1, 2] }, { 'k' => 3 }, { 'k' => nil }]
      result = JMESPath.search('group_by(@, &k)', data)
      expect(result.map { |g| g['key'] }).to eq([{ 'a' => 1 }, [1, 2], 3, nil])
    end

    it 'groups 1 and 1.0 together but keeps true and 1 apart' do
      data = [{ 'k' => 1 }, { 'k' => 1.0 }, { 'k' => true }, { 'k' => '1' }]
      result = JMESPath.search('group_by(@, &k)', data)
      expect(result.size).to eq(3)
      expect(result[0]['key']).to be_an(Integer)
      expect(result[0]['items']).to eq([{ 'k' => 1 }, { 'k' => 1.0 }])
      expect(result[1]['key']).to be(true)
      expect(result[2]['key']).to eq('1')
    end

    it 'ignores object member order but respects nested array order' do
      data = [
        { 'k' => { 'a' => 1, 'b' => [1, 2] } },
        { 'k' => { 'b' => [1, 2], 'a' => 1 } },
        { 'k' => { 'a' => 1, 'b' => [2, 1] } }
      ]
      result = JMESPath.search('group_by(@, &k)', data)
      expect(result.size).to eq(2)
      expect(result[0]['items'].size).to eq(2)
      expect(result[1]['items']).to eq([{ 'k' => { 'a' => 1, 'b' => [2, 1] } }])
    end

    it 'does not modify elements or keys' do
      data = [
        { 'k' => { 'b' => [2, 1], 'a' => 'x' }, 'v' => 1 },
        { 'k' => { 'a' => 'x', 'b' => [2, 1] }, 'v' => 2 }
      ]
      snapshot = Marshal.load(Marshal.dump(data))
      JMESPath.search('group_by(@, &k)', data)
      expect(data).to eq(snapshot)
    end

    it 'matches a naive pairwise reference on complex composite keys' do
      rng = Random.new(42)
      pool = [
        { 'a' => [1, { 'x' => true, 'y' => nil }], 'b' => 's' },
        { 'b' => 's', 'a' => [1.0, { 'y' => nil, 'x' => true }] },
        { 'a' => [1, { 'x' => true }], 'b' => 's' },
        [1, [2, [3, { 'k' => 'v' }]]],
        [1, [2, [{ 'k' => 'v' }, 3]]],
        1,
        1.0,
        true,
        false,
        '1',
        nil,
        { 'n' => 2.5, 'list' => [%w[a b], { 'z' => [nil, false] }] },
        { 'list' => [%w[a b], { 'z' => [nil, false] }], 'n' => 2.50 },
        [],
        {}
      ]
      items = Array.new(80) { |i| { 'k' => pool[rng.rand(pool.size)], 'seq' => i } }
      expected = naive_group_by(items) { |item| item['k'] }
      expect(JMESPath.search('group_by(@, &k)', items)).to eq(expected)
    end

    it 'evaluates each key once and avoids quadratic comparisons on larger input' do
      rng = Random.new(99)
      key_pool = Array.new(50) do |i|
        { 'id' => i, 'tags' => [i.to_s, i.even?], 'w' => i * 1.5 }
      end
      items = Array.new(2000) { |i| { 'k' => key_pool[rng.rand(key_pool.size)], 'seq' => i } }
      GroupBySpecCounters.evals = 0
      GroupBySpecCounters.comparisons = 0
      result = JMESPath.search('group_by(@, &k)', items)
      evals = GroupBySpecCounters.evals
      comparisons = GroupBySpecCounters.comparisons
      puts format('group_by large input: n=%d groups=%d key_evals=%d comparisons=%d',
                  items.size, result.size, evals, comparisons)
      expect(result).to eq(naive_group_by(items) { |item| item['k'] })
      expect(evals).to eq(items.size)
      expect(comparisons).to be <= items.size
    end

    it 'raises an input-position error for non-JSON keys' do
      data = [{ 'k' => 'fine' }, { 'k' => Object.new }]
      expect { JMESPath.search('group_by(@, &k)', data) }
        .to raise_error(Errors::InvalidValueError, /index 1/)
    end

    it 'raises an input-position error for cyclic hash keys' do
      cyclic = { 'name' => 'loop' }
      cyclic['self'] = cyclic
      data = [{ 'k' => 'fine' }, { 'k' => cyclic }]
      expect { JMESPath.search('group_by(@, &k)', data) }
        .to raise_error(Errors::InvalidValueError, /cyclic key at index 1/)
    end

    it 'raises an input-position error for cyclic array keys' do
      cyclic = []
      cyclic << cyclic
      data = [{ 'k' => [1, cyclic] }]
      expect { JMESPath.search('group_by(@, &k)', data) }
        .to raise_error(Errors::InvalidValueError, /cyclic key at index 0/)
    end

    it 'validates arity and argument types' do
      expect { JMESPath.search('group_by(@)', []) }
        .to raise_error(Errors::InvalidArityError)
      expect { JMESPath.search('group_by(@, @)', []) }
        .to raise_error(Errors::InvalidTypeError)
      expect { JMESPath.search('group_by(`foo`, &@)', nil) }
        .to raise_error(Errors::InvalidTypeError)
    end
  end
end
