# frozen_string_literal: true
require 'json'
require 'stringio'
require 'pathname'

module JMESPath
  require 'jmespath/caching_parser'
  require 'jmespath/errors'
  require 'jmespath/lexer'
  require 'jmespath/nodes'
  require 'jmespath/parser'
  require 'jmespath/runtime'
  require 'jmespath/token'
  require 'jmespath/token_stream'
  require 'jmespath/transformer'
  require 'jmespath/util'
  require 'jmespath/version'

  class << self
    # @param [String] expression A valid
    #   [JMESPath](https://github.com/boto/jmespath) expression.
    # @param [Hash] data
    # @return [Mixed,nil] Returns the matched values. Returns `nil` if the
    #   expression does not resolve inside `data`.
    def search(expression, data, runtime_options = {})
      data = case data
             when Hash, Struct then data # check for most common case first
             when Pathname then load_json(data)
             when IO, StringIO then JSON.parse(data.read)
             else data
        end
      Runtime.new(runtime_options).search(expression, data)
    end

    # @api private
    def load_json(path)
      JSON.parse(File.open(path, 'r', encoding: 'UTF-8', &:read))
    end

    # Transforms a JSON-like document (hashes and arrays) by selecting
    # nodes with restricted JMESPath expressions and replacing them with
    # the return values of callables.
    #
    # Only fields, indices, slices, filters and projections are
    # supported; expressions that generate new values (functions,
    # multi-selects, sorting, ...) are rejected before the document is
    # inspected. All targets are resolved against the original document
    # before any replacement is applied. Returns a new document and
    # leaves `data` unchanged, even when a callable raises.
    #
    # @example Replace every selected value
    #   JMESPath.transform('items[*].price', data) { |price| price * 2 }
    #
    # @example Delete selected nodes by returning JMESPath::DELETE
    #   JMESPath.transform('items[?expired]', data) { JMESPath::DELETE }
    #
    # @example Apply multiple rules resolved against the original document
    #   JMESPath.transform({
    #     'items[*].price' => ->(price) { price * 2 },
    #     'meta.total' => ->(total) { total + 1 },
    #   }, data)
    #
    # @param [String, Hash, Array] rules A single expression (requires
    #   a block), a Hash of `expression => callable` pairs, or an Array
    #   of `[expression, callable]` pairs.
    # @param [Hash, Array] data The document to transform. It is never
    #   modified unless the `:in_place` option is `true`.
    # @param [Hash] runtime_options
    # @option runtime_options [Boolean] :in_place (false) Mutate `data`
    #   instead of transforming a deep copy.
    # @return [Hash, Array] The transformed document.
    def transform(rules, data, runtime_options = {}, &block)
      Transformer.new(runtime_options).transform(rules, data, &block)
    end
  end
end
