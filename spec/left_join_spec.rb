# frozen_string_literal: true
require 'spec_helper'

module JMESPath
  describe '.search' do
    describe 'left_join' do
      let(:users) do
        [
          { 'id' => 'u1', 'team' => 'a' },
          { 'id' => 'u2', 'team' => nil },
          { 'id' => 'u3', 'team' => 'b' },
          { 'id' => 'u4', 'team' => '' },
          { 'id' => 'u5', 'team' => 'a' }
        ]
      end

      let(:events) do
        [
          { 'id' => 'e1', 'team' => 'a' },
          { 'id' => 'e2', 'team' => nil },
          { 'id' => 'e3', 'team' => 'b' },
          { 'id' => 'e4', 'team' => 'a' },
          { 'id' => 'e5', 'team' => '' }
        ]
      end

      let(:data) { { 'users' => users, 'events' => events } }
      let(:expression) { 'left_join(users, events, &team, &team)' }

      it 'preserves left order and expands matching right values in right order' do
        expect(JMESPath.search(expression, data)).to eq([
          { 'left' => users[0], 'right' => events[0] },
          { 'left' => users[0], 'right' => events[3] },
          { 'left' => users[1], 'right' => nil },
          { 'left' => users[2], 'right' => events[2] },
          { 'left' => users[3], 'right' => events[4] },
          { 'left' => users[4], 'right' => events[0] },
          { 'left' => users[4], 'right' => events[3] }
        ])
      end

      it 'returns an empty join for two empty arrays' do
        expect(JMESPath.search(expression, { 'users' => [], 'events' => [] })).to eq([])
      end

      it 'returns null right records when the right array is empty' do
        result = JMESPath.search(expression, { 'users' => users, 'events' => [] })

        expect(result).to eq(users.map { |user| { 'left' => user, 'right' => nil } })
      end

      it 'does not match null keys unless explicitly enabled' do
        result = JMESPath.search(
          'left_join(users, events, &team, &team, `{"match_null": true}`)',
          data
        )

        expect(result[2]).to eq('left' => users[1], 'right' => events[1])
      end

      it 'matches composite scalar tuples using JMESPath value equality' do
        join_data = {
          'users' => [
            { 'a' => 1.0, 'b' => 'x' },
            { 'a' => '1', 'b' => 'x' },
            { 'a' => 1, 'b' => 'y' }
          ],
          'events' => [
            { 'id' => 'e1', 'a' => 1, 'b' => 'x' },
            { 'id' => 'e2', 'a' => 1, 'b' => 'x' },
            { 'id' => 'e3', 'a' => '1', 'b' => 'x' },
            { 'id' => 'e4', 'a' => 1, 'b' => 'y' }
          ]
        }

        result = JMESPath.search('left_join(users, events, &[a, b], &[a, b])', join_data)
        first_user = join_data['users'][0]

        expect(result).to eq([
          { 'left' => first_user, 'right' => join_data['events'][0] },
          { 'left' => first_user, 'right' => join_data['events'][1] },
          { 'left' => join_data['users'][1], 'right' => join_data['events'][2] },
          { 'left' => join_data['users'][2], 'right' => join_data['events'][3] }
        ])
      end

      it 'does not match composite tuples containing null unless enabled' do
        join_data = {
          'users' => [{ 'a' => 1, 'b' => nil }],
          'events' => [{ 'id' => 'event', 'a' => 1, 'b' => nil }]
        }

        expect(JMESPath.search('left_join(users, events, &[a, b], &[a, b])', join_data)).to eq([
          { 'left' => join_data['users'][0], 'right' => nil }
        ])

        result = JMESPath.search(
          'left_join(users, events, &[a, b], &[a, b], `{"match_null": true}`)',
          join_data
        )
        expect(result).to eq([
          { 'left' => join_data['users'][0], 'right' => join_data['events'][0] }
        ])
      end

      it 'rejects non-scalar composite tuple members' do
        join_data = {
          'users' => [{ 'key' => { 'value' => 1 } }],
          'events' => [{ 'key' => { 'value' => 1 } }]
        }

        expect do
          JMESPath.search('left_join(users, events, &key, &key)', join_data)
        end.to raise_error(Errors::InvalidTypeError)
      end

      it 'rejects empty composite tuples' do
        join_data = {
          'users' => [{ 'values' => [] }],
          'events' => [{ 'values' => [] }]
        }

        expect do
          JMESPath.search('left_join(users, events, &values, &values)', join_data)
        end.to raise_error(Errors::InvalidValueError)
      end

      it 'rejects non-object join options' do
        expect do
          JMESPath.search('left_join(users, events, &team, &team, `true`)', data)
        end.to raise_error(Errors::InvalidTypeError)
      end

      it 'raises when expansion exceeds the limit instead of returning a prefix' do
        expect do
          JMESPath.search(
            'left_join(users, events, &team, &team, `{"limit": 3}`)',
            data
          )
        end.to raise_error(Errors::InvalidValueError, /exceeds the output limit/)
      end

      it 'accepts an output limit equal to the expanded size' do
        result = JMESPath.search(
          'left_join(users, events, &team, &team, `{"limit": 7}`)',
          data
        )

        expect(result.length).to eq(7)
      end

      it 'evaluates each key expression once per item and groups the right array once' do
        left_node = CountingKeyNode.new('a')
        right_node = CountingKeyNode.new('a')
        left_expression = Nodes::Expression.new(left_node)
        right_expression = Nodes::Expression.new(right_node)
        function = Nodes::LeftJoinFunction.new([])

        left = [{ 'k' => 'a' }, { 'k' => 'b' }, { 'k' => 'a' }]
        right = [{ 'k' => 'a' }, { 'k' => 'a' }, { 'k' => 'b' }]

        function.send(:call, [left, right, left_expression, right_expression])

        expect(left_node.count).to eq(3)
        expect(right_node.count).to eq(3)
      end
    end

    class CountingKeyNode < Nodes::Node
      attr_reader :count

      def initialize(key)
        @key = key
        @count = 0
      end

      def visit(value)
        @count += 1
        value[@key]
      end
    end
  end
end
