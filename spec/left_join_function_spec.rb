# frozen_string_literal: true
require 'spec_helper'

module JMESPath
  describe 'left_join function' do
    def search(expression, data)
      JMESPath.search(expression, data)
    end

    let(:users) do
      [
        { 'id' => 1, 'name' => 'alice' },
        { 'id' => 2, 'name' => 'bob' },
        { 'id' => 3, 'name' => 'carol' }
      ]
    end

    let(:events) do
      [
        { 'user_id' => 2, 'event' => 'login' },
        { 'user_id' => 2, 'event' => 'logout' },
        { 'user_id' => 9, 'event' => 'orphan' }
      ]
    end

    it 'joins two arrays on key expressions into {left, right} records' do
      result = search('left_join(users, &id, events, &user_id)', 'users' => users, 'events' => events)
      expect(result).to eq([
        { 'left' => users[0], 'right' => nil },
        { 'left' => users[1], 'right' => events[0] },
        { 'left' => users[1], 'right' => events[1] },
        { 'left' => users[2], 'right' => nil }
      ])
    end

    it 'preserves left order and expands duplicate right keys in original order' do
      left = [{ 'k' => 'a' }, { 'k' => 'a' }, { 'k' => 'b' }]
      right = [
        { 'k' => 'a', 'n' => 1 },
        { 'k' => 'a', 'n' => 2 },
        { 'k' => 'b', 'n' => 3 }
      ]
      result = search('left_join(left, &k, right, &k)', 'left' => left, 'right' => right)
      expect(result).to eq([
        { 'left' => left[0], 'right' => right[0] },
        { 'left' => left[0], 'right' => right[1] },
        { 'left' => left[1], 'right' => right[0] },
        { 'left' => left[1], 'right' => right[1] },
        { 'left' => left[2], 'right' => right[2] }
      ])
    end

    it 'returns an empty array when the left side is empty' do
      expect(search('left_join(left, &k, right, &k)', 'left' => [], 'right' => [{ 'k' => 1 }])).to eq([])
    end

    it 'emits null right for every left item when the right side is empty' do
      left = [{ 'k' => 1 }, { 'k' => 2 }]
      expect(search('left_join(left, &k, right, &k)', 'left' => left, 'right' => [])).to eq([
        { 'left' => left[0], 'right' => nil },
        { 'left' => left[1], 'right' => nil }
      ])
    end

    it 'matches empty string keys against each other' do
      left = [{ 'k' => '' }]
      right = [{ 'k' => '', 'n' => 1 }]
      expect(search('left_join(left, &k, right, &k)', 'left' => left, 'right' => right)).to eq([
        { 'left' => left[0], 'right' => right[0] }
      ])
    end

    it 'does not match null keys by default' do
      left = [{ 'id' => nil }, { 'id' => 1 }]
      right = [{ 'user_id' => nil }, { 'user_id' => 1 }]
      result = search('left_join(left, &id, right, &user_id)', 'left' => left, 'right' => right)
      expect(result).to eq([
        { 'left' => left[0], 'right' => nil },
        { 'left' => left[1], 'right' => right[1] }
      ])
    end

    it 'matches null keys when the match_null option is set' do
      left = [{ 'id' => nil }]
      right = [{ 'user_id' => nil, 'n' => 1 }, { 'user_id' => nil, 'n' => 2 }]
      result = search(
        'left_join(left, &id, right, &user_id, `{"match_null": true}`)',
        'left' => left, 'right' => right
      )
      expect(result).to eq([
        { 'left' => left[0], 'right' => right[0] },
        { 'left' => left[0], 'right' => right[1] }
      ])
    end

    it 'compares key types using query semantics' do
      left = [{ 'k' => 1 }, { 'k' => '1' }, { 'k' => true }]
      right = [{ 'k' => 1.0, 'n' => 'number' }, { 'k' => '1', 'n' => 'string' }]
      result = search('left_join(left, &k, right, &k)', 'left' => left, 'right' => right)
      expect(result).to eq([
        { 'left' => left[0], 'right' => right[0] },
        { 'left' => left[1], 'right' => right[1] },
        { 'left' => left[2], 'right' => nil }
      ])
    end

    it 'rejects array keys unless composite keys are declared' do
      data = { 'left' => [{ 'k' => [1, 2] }], 'right' => [] }
      expect do
        search('left_join(left, &k, right, &k)', data)
      end.to raise_error(Errors::InvalidTypeError, /composite/)
    end

    it 'joins on declared composite keys' do
      left = [
        { 'a' => 1, 'b' => 'x' },
        { 'a' => 1, 'b' => 'y' }
      ]
      right = [
        { 'a' => 1, 'b' => 'x', 'n' => 1 },
        { 'a' => 1, 'b' => 'x', 'n' => 2 }
      ]
      result = search(
        'left_join(left, &[a, b], right, &[a, b], `{"composite": true}`)',
        'left' => left, 'right' => right
      )
      expect(result).to eq([
        { 'left' => left[0], 'right' => right[0] },
        { 'left' => left[0], 'right' => right[1] },
        { 'left' => left[1], 'right' => nil }
      ])
    end

    it 'rejects non-scalar components in composite keys' do
      data = {
        'left' => [{ 'k' => [{ 'nested' => 1 }] }],
        'right' => []
      }
      expect do
        search('left_join(left, &k, right, &k, `{"composite": true}`)', data)
      end.to raise_error(Errors::InvalidTypeError, /scalar/)
    end

    it 'fails when the output limit is exceeded during expansion' do
      left = [{ 'k' => 1 }]
      right = [{ 'k' => 1 }, { 'k' => 1 }, { 'k' => 1 }]
      expect do
        search('left_join(left, &k, right, &k, `{"limit": 2}`)', 'left' => left, 'right' => right)
      end.to raise_error(Errors::InvalidValueError, /limit/)
    end

    it 'accepts output exactly at the limit' do
      left = [{ 'k' => 1 }]
      right = [{ 'k' => 1 }, { 'k' => 1 }]
      result = search('left_join(left, &k, right, &k, `{"limit": 2}`)', 'left' => left, 'right' => right)
      expect(result.size).to eq(2)
    end

    it 'raises on invalid arguments' do
      expect { search('left_join(users, &id, events)', 'users' => [], 'events' => []) }
        .to raise_error(Errors::InvalidArityError)
      expect { search('left_join(users, &id, events, &user_id, events)', 'users' => [], 'events' => []) }
        .to raise_error(Errors::InvalidTypeError)
      expect { search('left_join(`1`, &id, events, &user_id)', 'events' => []) }
        .to raise_error(Errors::InvalidTypeError)
      expect { search('left_join(users, &id, events, &user_id, `{"bogus": true}`)', 'users' => [], 'events' => []) }
        .to raise_error(Errors::InvalidValueError)
      expect { search('left_join(users, &id, events, &user_id, `{"limit": -1}`)', 'users' => [], 'events' => []) }
        .to raise_error(Errors::InvalidTypeError)
    end

    describe 'key expression evaluation counts' do
      class CountingExpression < Nodes::Expression
        attr_reader :count

        def initialize(&block)
          @block = block
          @count = 0
        end

        def eval(value)
          @count += 1
          @block.call(value)
        end
      end

      def join(left, left_expr, right, right_expr, options = nil)
        args = [left, left_expr, right, right_expr]
        args << options if options
        Nodes::LeftJoinFunction.new([]).call(args)
      end

      it 'evaluates each key expression exactly once per element' do
        left = [{ 'id' => 1 }, { 'id' => 2 }, { 'id' => 2 }]
        right = [{ 'user_id' => 2 }, { 'user_id' => 2 }, { 'user_id' => 3 }, { 'user_id' => 4 }]
        left_expr = CountingExpression.new { |item| item['id'] }
        right_expr = CountingExpression.new { |item| item['user_id'] }

        result = join(left, left_expr, right, right_expr)

        expect(left_expr.count).to eq(left.size)
        expect(right_expr.count).to eq(right.size)
        expect(result.size).to eq(1 + 2 + 2)
      end

      it 'does not re-evaluate keys while expanding duplicate matches' do
        left = [{ 'id' => 1 }]
        right = Array.new(10) { { 'user_id' => 1 } }
        left_expr = CountingExpression.new { |item| item['id'] }
        right_expr = CountingExpression.new { |item| item['user_id'] }

        result = join(left, left_expr, right, right_expr)

        expect(left_expr.count).to eq(1)
        expect(right_expr.count).to eq(10)
        expect(result.size).to eq(10)
      end
    end
  end
end
