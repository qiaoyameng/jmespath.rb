# frozen_string_literal: true
require 'spec_helper'

module JMESPath
  describe '.transform' do
    it 'replaces a field selected by a single expression' do
      data = { 'foo' => { 'bar' => 1 } }
      result = JMESPath.transform('foo.bar', data) { |v| v + 1 }
      expect(result).to eq('foo' => { 'bar' => 2 })
    end

    it 'replaces values at array indices, including negative indices' do
      data = { 'a' => [1, 2, 3] }
      result = JMESPath.transform({ 'a[0]' => ->(_) { :first }, 'a[-1]' => ->(_) { :last } }, data)
      expect(result).to eq('a' => [:first, 2, :last])
    end

    it 'replaces elements selected by a slice' do
      data = { 'a' => [1, 2, 3, 4] }
      result = JMESPath.transform('a[1:3]', data) { |v| v * 10 }
      expect(result).to eq('a' => [1, 20, 30, 4])
    end

    it 'replaces elements selected by a slice with a step' do
      data = { 'a' => [1, 2, 3, 4, 5] }
      result = JMESPath.transform('a[::2]', data) { |v| v * 10 }
      expect(result).to eq('a' => [10, 2, 30, 4, 50])
    end

    it 'replaces values selected by an array projection' do
      data = { 'items' => [{ 'price' => 1 }, { 'price' => 2 }] }
      result = JMESPath.transform('items[*].price', data) { |price| price * 2 }
      expect(result).to eq('items' => [{ 'price' => 2 }, { 'price' => 4 }])
    end

    it 'replaces values selected by an object projection' do
      data = { 'a' => { 'x' => 1, 'y' => 2 } }
      result = JMESPath.transform('a.*', data) { |v| v + 1 }
      expect(result).to eq('a' => { 'x' => 2, 'y' => 3 })
    end

    it 'replaces values selected by nested array projections' do
      data = { 'a' => [[1, 2], [3, 4]] }
      result = JMESPath.transform('a[*][*]', data) { |v| v * 10 }
      expect(result).to eq('a' => [[10, 20], [30, 40]])
    end

    it 'replaces values selected by a filter projection' do
      data = {
        'items' => [
          { 'sku' => 'a', 'price' => 5 },
          { 'sku' => 'b', 'price' => 50 },
          { 'sku' => 'c', 'price' => 500 }
        ]
      }
      result = JMESPath.transform('items[?price > `10`].price', data) { |price| price / 10 }
      expect(result).to eq(
        'items' => [
          { 'sku' => 'a', 'price' => 5 },
          { 'sku' => 'b', 'price' => 5 },
          { 'sku' => 'c', 'price' => 50 }
        ]
      )
    end

    it 'allows the full expression language inside filter tests' do
      data = { 'items' => [{ 'name' => 'ab' }, { 'name' => 'abcd' }] }
      result = JMESPath.transform('items[?length(name) > `2`].name', data, &:upcase)
      expect(result).to eq('items' => [{ 'name' => 'ab' }, { 'name' => 'ABCD' }])
    end

    it 'deletes array elements selected by a filter when the block returns DELETE' do
      data = {
        'items' => [
          { 'sku' => 'a', 'expired' => false },
          { 'sku' => 'b', 'expired' => true },
          { 'sku' => 'c', 'expired' => false },
          { 'sku' => 'd', 'expired' => true }
        ]
      }
      result = JMESPath.transform('items[?expired]', data) { JMESPath::DELETE }
      expect(result).to eq(
        'items' => [
          { 'sku' => 'a', 'expired' => false },
          { 'sku' => 'c', 'expired' => false }
        ]
      )
    end

    it 'deletes hash keys when the block returns DELETE' do
      data = { 'a' => 1, 'b' => 2 }
      result = JMESPath.transform('b', data) { JMESPath::DELETE }
      expect(result).to eq('a' => 1)
    end

    it 'deletes the correct array elements without index shifting' do
      data = { 'a' => [0, 1, 2, 3, 4] }
      result = JMESPath.transform('a[*]', data) { |v| v.odd? ? JMESPath::DELETE : v }
      expect(result).to eq('a' => [0, 2, 4])
    end

    it 'replaces and deletes within the same array' do
      data = { 'a' => [1, 2, 3, 4] }
      result = JMESPath.transform('a[*]', data) { |v| v.even? ? JMESPath::DELETE : v * 10 }
      expect(result).to eq('a' => [10, 30])
    end

    it 'passes the original path to blocks accepting a second argument' do
      data = { 'items' => [{ 'price' => 1 }, { 'price' => 2 }] }
      paths = []
      JMESPath.transform('items[*].price', data) do |_, path|
        paths << path
        0
      end
      expect(paths).to eq([['items', 0, 'price'], ['items', 1, 'price']])
    end

    it 'resolves every target against the original document before replacing' do
      data = { 'a' => 1, 'b' => 2 }
      seen = {}
      result = JMESPath.transform({
        'a' => ->(v) { seen[:a] = v; 100 },
        'b' => ->(v) { seen[:b] = v; 200 }
      }, data)
      expect(result).to eq('a' => 100, 'b' => 200)
      expect(seen).to eq(a: 1, b: 2)
    end

    it 'distinguishes missing keys from null values' do
      data = { 'present_null' => nil }
      called = []
      result = JMESPath.transform({ 'present_null' => ->(v) { called << v; 'was-null' },
                                    'missing' => ->(v) { called << v; 'was-missing' } }, data)
      expect(called).to eq([nil])
      expect(result).to eq('present_null' => 'was-null')
    end

    it 'does not call the block for out-of-range indices' do
      called = false
      result = JMESPath.transform('a[5]', { 'a' => [1] }) { called = true }
      expect(called).to be(false)
      expect(result).to eq('a' => [1])
    end

    it 'returns an independent document and leaves the input unchanged' do
      data = { 'items' => [{ 'price' => 1 }], 'tag' => 'x' }
      result = JMESPath.transform('items[*].price', data) { |v| v + 1 }
      expect(result).to eq('items' => [{ 'price' => 2 }], 'tag' => 'x')
      expect(data).to eq('items' => [{ 'price' => 1 }], 'tag' => 'x')
      expect(result['items']).not_to be(data['items'])
      expect(result['items'][0]).not_to be(data['items'][0])
      expect(result['tag']).not_to be(data['tag'])
    end

    it 'mutates the document in place when :in_place is true' do
      data = { 'a' => 1 }
      result = JMESPath.transform('a', data, in_place: true) { |v| v + 1 }
      expect(result).to be(data)
      expect(data).to eq('a' => 2)
    end

    describe 'unsupported expressions' do
      # Proves rejection happens before the document is consumed.
      class ExplodingHash < Hash
        def key?(*)
          raise 'document was consumed'
        end
      end

      def expect_rejected(expression)
        called = false
        expect do
          JMESPath.transform(expression, ExplodingHash['a' => 1]) { called = true }
        end.to raise_error(Errors::UnsupportedExpressionError, /#{Regexp.escape(expression)}/)
        expect(called).to be(false)
      end

      it 'rejects functions that generate new values' do
        expect_rejected('length(a)')
      end

      it 'rejects sorting' do
        expect_rejected('sort_by(a, &b)')
      end

      it 'rejects multi-select hashes' do
        expect_rejected('a.{x: x}')
      end

      it 'rejects multi-select lists' do
        expect_rejected('a.[x, y]')
      end

      it 'rejects flatten' do
        expect_rejected('a[]')
      end

      it 'rejects literals' do
        expect_rejected('`1`')
      end
    end

    describe 'conflicting targets' do
      it 'rejects duplicate targets' do
        data = { 'a' => { 'b' => 1 } }
        expect do
          JMESPath.transform([['a.b', ->(v) { v }], ['a.b', ->(v) { v }]], data)
        end.to raise_error(Errors::TransformConflictError, /duplicate.*a\.b/)
      end

      it 'rejects duplicate targets selected by different expressions' do
        data = { 'a' => [1] }
        expect do
          JMESPath.transform({ 'a[0]' => ->(v) { v }, 'a[*]' => ->(v) { v } }, data)
        end.to raise_error(Errors::TransformConflictError, /duplicate.*a\[0\]/)
      end

      it 'rejects a target that is an ancestor of another target' do
        data = { 'a' => { 'b' => 1 } }
        expect do
          JMESPath.transform({ 'a' => ->(v) { v }, 'a.b' => ->(v) { v } }, data)
        end.to raise_error(Errors::TransformConflictError, /overlap.*a.*a\.b/)
      end

      it 'rejects a target that is a descendant of another target' do
        data = { 'a' => { 'b' => 1 } }
        expect do
          JMESPath.transform({ 'a.b' => ->(v) { v }, 'a' => ->(v) { v } }, data)
        end.to raise_error(Errors::TransformConflictError)
      end
    end

    describe 'block errors' do
      it 'raises a TransformError carrying the original path' do
        data = { 'items' => [{ 'price' => 1 }, { 'price' => 2 }] }
        error = nil
        begin
          JMESPath.transform('items[*].price', data) do |price|
            raise 'boom' if price == 2
            price
          end
        rescue Errors::TransformError => e
          error = e
        end
        expect(error).not_to be_nil
        expect(error.path).to eq(['items', 1, 'price'])
        expect(error.expression).to eq('items[*].price')
        expect(error.message).to include('boom', 'items[1].price', 'items[*].price')
        expect(error.cause).to be_a(RuntimeError)
      end

      it 'leaves the original document item-by-item unchanged when the last block raises' do
        item_a = { 'sku' => 'a', 'price' => 5, 'expired' => false }
        item_b = { 'sku' => 'b', 'price' => 8, 'expired' => true }
        item_c = { 'sku' => 'c', 'price' => 500, 'expired' => false }
        items = [item_a, item_b, item_c]
        data = { 'items' => items, 'meta' => { 'count' => 3 } }
        meta = data['meta']
        snapshot = Marshal.load(Marshal.dump(data))

        expect do
          JMESPath.transform({
            # replace prices selected by a filter
            'items[?price > `10`].price' => ->(price) { price / 10 },
            # delete expired items selected by a filter
            'items[?expired]' => ->(_) { JMESPath::DELETE },
            # the last block raises
            'meta.count' => ->(_) { raise 'boom' }
          }, data)
        end.to raise_error(Errors::TransformError, /meta\.count/)

        expect(data).to eq(snapshot)
        expect(data['items']).to be(items)
        expect(data['items']).to eq([item_a, item_b, item_c])
        expect(data['items'][0]).to be(item_a)
        expect(data['items'][1]).to be(item_b)
        expect(data['items'][2]).to be(item_c)
        expect(item_a).to eq('sku' => 'a', 'price' => 5, 'expired' => false)
        expect(item_b).to eq('sku' => 'b', 'price' => 8, 'expired' => true)
        expect(item_c).to eq('sku' => 'c', 'price' => 500, 'expired' => false)
        expect(data['meta']).to be(meta)
        expect(meta).to eq('count' => 3)
      end

      it 'leaves the document unchanged in place mode when a block raises' do
        data = { 'a' => 1, 'b' => 2 }
        expect do
          JMESPath.transform({
            'a' => ->(v) { v + 1 },
            'b' => ->(_) { raise 'boom' }
          }, data, in_place: true)
        end.to raise_error(Errors::TransformError)
        expect(data).to eq('a' => 1, 'b' => 2)
      end
    end

    describe 'root targets' do
      it 'replaces the root node' do
        result = JMESPath.transform('@', { 'a' => 1 }) { |doc| { 'wrapped' => doc } }
        expect(result).to eq('wrapped' => { 'a' => 1 })
      end

      it 'refuses to delete the root node' do
        expect do
          JMESPath.transform('@', { 'a' => 1 }) { JMESPath::DELETE }
        end.to raise_error(Errors::TransformError, /root/)
      end
    end

    describe 'rule normalization' do
      it 'requires a block for a single expression' do
        expect { JMESPath.transform('a', { 'a' => 1 }) }.to raise_error(ArgumentError)
      end

      it 'accepts an array of expression/callable pairs' do
        result = JMESPath.transform([['a', ->(v) { v + 1 }]], { 'a' => 1 })
        expect(result).to eq('a' => 2)
      end

      it 'rejects non-callable rule values' do
        expect do
          JMESPath.transform({ 'a' => 1 }, { 'a' => 1 })
        end.to raise_error(ArgumentError, /call/)
      end
    end
  end
end
