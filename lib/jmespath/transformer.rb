# frozen_string_literal: true
module JMESPath
  # Return this sentinel from a transform block to delete the selected
  # node from its parent hash or array.
  DELETE = Object.new.freeze

  # Transforms JSON-like documents (hashes and arrays) by selecting
  # nodes with a restricted JMESPath expression and replacing (or
  # deleting) them with the return value of a block.
  #
  # Only expressions whose results can be mapped back to concrete paths
  # in the original document are supported: fields, indices, slices,
  # filters and projections. Expressions that produce new values
  # (functions, multi-selects, flatten, literals, ...) are rejected
  # with {Errors::UnsupportedExpressionError} before the document is
  # inspected.
  #
  # All targets are resolved against the original document before any
  # replacement is applied, so one rule can never observe the effect of
  # another. Overlapping targets (identical paths, or one path being an
  # ancestor of another) raise {Errors::TransformConflictError}.
  #
  # By default the document is deep-copied and the copy is transformed;
  # the input is never modified. If any block raises, a
  # {Errors::TransformError} carrying the original path is raised and
  # the input document is left untouched.
  class Transformer
    # @option options [Boolean] :in_place (false) When `true`, the given
    #   document is mutated instead of a copy. Replacements are still
    #   only applied after every block has been called, so a raising
    #   block leaves the document unchanged unless the block itself
    #   mutated values it received.
    # @option options [Boolean] :cache_expressions (true)
    # @option options [Parser, CachingParser] :parser
    def initialize(options = {})
      @parser = options[:parser] || default_parser(options)
      @in_place = options[:in_place] ? true : false
    end

    # @param [String, Hash, Array] rules A single expression (requires
    #   a block), a Hash of `expression => callable` pairs, or an Array
    #   of `[expression, callable]` pairs. Rules are applied in order,
    #   but every target is resolved against the original document
    #   first.
    # @param [Hash, Array] data The document to transform.
    # @yield [value, path] Optional block used as the callable for a
    #   single expression rule. Receives the selected value (and the
    #   path, when the callable declares exactly two parameters) and
    #   returns the replacement value, or {JMESPath::DELETE} to remove
    #   the node.
    # @return [Hash, Array] The transformed document.
    def transform(rules, data, &block)
      rules = normalize_rules(rules, block)
      parsed = rules.map { |expression, callable| [expression, @parser.parse(expression), callable] }

      # Reject unsupported expressions before the data is inspected.
      parsed.each { |expression, ast, _| validate_spine!(ast, expression) }

      document = @in_place ? data : deep_copy(data)

      # Resolve every target against the untouched document.
      all_targets = []
      resolved = parsed.map do |expression, ast, callable|
        targets = resolve(ast, document, [])
        targets.each { |_, path| all_targets << [expression, path] }
        [expression, callable, targets]
      end

      check_conflicts!(all_targets)

      # Call every block before applying any edit, so a raising block
      # leaves the document untouched.
      edits = []
      resolved.each do |expression, callable, targets|
        targets.each do |value, path|
          edits << [expression, path, call_block(callable, value, path, expression)]
        end
      end

      apply_edits(document, edits)
    end

    private

    def default_parser(options)
      if options[:cache_expressions] == false
        Parser.new(options)
      else
        CachingParser.new(options)
      end
    end

    def normalize_rules(rules, block)
      pairs =
        case rules
        when String
          raise ArgumentError, 'a block is required when transforming with a single expression' unless block
          [[rules, block]]
        when Hash
          rules.to_a
        when Array
          rules
        else
          raise ArgumentError, 'rules must be an expression String, a Hash of `expression => callable`, ' \
                               'or an Array of [expression, callable] pairs'
        end
      pairs.map do |expression, callable|
        raise ArgumentError, "rule expressions must be strings, got: #{expression.inspect}" unless expression.is_a?(String)
        unless callable.respond_to?(:call)
          raise ArgumentError, "rule for #{expression.inspect} must respond to :call, got: #{callable.inspect}"
        end
        [expression, callable]
      end
    end

    # @api private
    # Only fields, indices, slices, filters and projections may appear
    # on the path-carrying spine of the expression. Filter tests may
    # use the full expression language: they select nodes but never
    # produce replacement values.
    def validate_spine!(node, expression)
      case node
      when Nodes::Current, Nodes::Field
        nil
      when Nodes::Subexpression
        validate_spine!(node.left, expression)
        validate_spine!(node.right, expression)
      when Nodes::ArrayProjection
        validate_spine!(node.target, expression) unless node.target.is_a?(Nodes::Slice)
        validate_spine!(node.projection, expression)
      when Nodes::ObjectProjection
        validate_spine!(node.target, expression)
        validate_spine!(node.projection, expression)
      when Nodes::Condition
        validate_spine!(node.child, expression)
      else
        construct = node.class.name.split('::').last
        raise Errors::UnsupportedExpressionError,
              "transform expressions do not support #{construct}; only fields, indices, slices, filters " \
              "and projections map back to the original document (expression: #{expression.inspect})"
      end
    end

    # @api private
    # Returns a list of `[value, path]` pairs for the node, resolved
    # against `value` located at `path`. Missing keys and out-of-range
    # indices produce no pairs; present `nil` values do.
    def resolve(node, value, path)
      case node
      when Nodes::Current
        [[value, path]]
      when Nodes::Field
        resolve_field(node, value, path)
      when Nodes::Subexpression
        resolve(node.left, value, path).flat_map { |v, p| resolve(node.right, v, p) }
      when Nodes::ArrayProjection
        projection_elements(node, value, path).flat_map do |element, element_path|
          resolve(node.projection, element, element_path)
        end
      when Nodes::ObjectProjection
        resolve(node.target, value, path).flat_map do |target_value, target_path|
          next [] unless target_value.is_a?(Hash)
          target_value.flat_map { |k, v| resolve(node.projection, v, target_path + [k]) }
        end
      when Nodes::Condition
        if Util.falsey?(node.test.visit(value))
          []
        else
          resolve(node.child, value, path)
        end
      else
        construct = node.class.name.split('::').last
        raise Errors::UnsupportedExpressionError, "transform expressions do not support #{construct}"
      end
    end

    def resolve_field(node, value, path)
      key = node.key
      if key.is_a?(Integer)
        return [] unless value.is_a?(Array)
        index = key.negative? ? key + value.length : key
        return [] if index.negative? || index >= value.length
        [[value[index], path + [index]]]
      elsif value.is_a?(Hash)
        if value.key?(key)
          [[value[key], path + [key]]]
        elsif (symbol_key = key.respond_to?(:to_sym) ? key.to_sym : nil) && value.key?(symbol_key)
          [[value[symbol_key], path + [symbol_key]]]
        else
          []
        end
      else
        []
      end
    end

    def projection_elements(node, value, path)
      if node.target.is_a?(Nodes::Slice)
        return [] unless value.is_a?(Array)
        slice_indices(node.target, value.length).map { |i| [value[i], path + [i]] }
      else
        resolve(node.target, value, path).flat_map do |target_value, target_path|
          next [] unless target_value.is_a?(Array)
          target_value.each_with_index.map { |element, i| [element, target_path + [i]] }
        end
      end
    end

    # Evaluates the slice against a range of indices to reuse the exact
    # slice semantics (including negative steps) and learn which
    # original indices it selects.
    def slice_indices(slice, length)
      slice.visit((0...length).to_a) || []
    end

    def check_conflicts!(targets)
      sorted = targets.sort_by { |_, path| path_sort_key(path) }
      sorted.each_cons(2) do |(expression_a, path_a), (expression_b, path_b)|
        if path_a == path_b
          raise Errors::TransformConflictError,
                "duplicate transform target #{format_path(path_a)} selected by both " \
                "#{expression_a.inspect} and #{expression_b.inspect}"
        elsif path_prefix?(path_a, path_b)
          raise Errors::TransformConflictError,
                "overlapping transform targets #{format_path(path_a)} (#{expression_a.inspect}) and " \
                "#{format_path(path_b)} (#{expression_b.inspect})"
        end
      end
    end

    def path_sort_key(path)
      path.map { |key| key.is_a?(Integer) ? [0, key, ''] : [1, 0, key.to_s] }
    end

    def path_prefix?(prefix, path)
      prefix.length < path.length && path.first(prefix.length) == prefix
    end

    def call_block(callable, value, path, expression)
      callable.arity == 2 ? callable.call(value, path.dup) : callable.call(value)
    rescue Errors::Error
      raise
    rescue StandardError => e
      error = Errors::TransformError.new(
        "transform block raised #{e.class}: #{e.message} at #{format_path(path)} " \
        "(expression: #{expression.inspect})",
        expression: expression,
        path: path
      )
      raise error, cause: e
    end

    def apply_edits(document, edits)
      root_edits, edits = edits.partition { |_, path, _| path.empty? }
      root_edit = root_edits.first
      if root_edit
        expression, _, replacement = root_edit
        if replacement.equal?(DELETE)
          raise Errors::TransformError.new('cannot delete the root node', expression: expression, path: [])
        elsif @in_place
          raise Errors::TransformError.new(
            'cannot replace the root node when :in_place is true', expression: expression, path: []
          )
        end
      end

      replacements, deletions = edits.partition { |_, _, replacement| !replacement.equal?(DELETE) }
      replacements.each { |_, path, replacement| apply_replacement(document, path, replacement) }
      apply_deletions(document, deletions.map { |_, path, _| path })

      root_edit ? root_edit[2] : document
    end

    def apply_replacement(document, path, replacement)
      parent = value_at(document, path[0..-2])
      key = path[-1]
      case parent
      when Hash, Array then parent[key] = replacement
      end
    end

    # Array elements are deleted in descending index order so that
    # earlier deletions never shift the indices of later ones.
    def apply_deletions(document, paths)
      paths.group_by { |path| path[0..-2] }.each do |parent_path, child_paths|
        parent = value_at(document, parent_path)
        case parent
        when Array
          child_paths.map { |path| path[-1] }.sort.reverse_each { |index| parent.delete_at(index) }
        when Hash
          child_paths.each { |path| parent.delete(path[-1]) }
        end
      end
    end

    def value_at(document, path)
      path.reduce(document) do |value, key|
        case value
        when Hash, Array then value[key]
        end
      end
    end

    def deep_copy(value)
      case value
      when Hash
        value.each_with_object({}) { |(k, v), copy| copy[k] = deep_copy(v) }
      when Array
        value.map { |element| deep_copy(element) }
      when String
        value.dup
      else
        value
      end
    end

    def format_path(path)
      return '<root>' if path.empty?
      path.map do |key|
        if key.is_a?(Integer)
          "[#{key}]"
        elsif key.to_s.match?(/\A[A-Za-z_][A-Za-z0-9_]*\z/)
          ".#{key}"
        else
          "[#{key.to_s.inspect}]"
        end
      end.join.sub(/\A\./, '')
    end
  end
end
