# jmespath.rb

[![Gitter chat](https://badges.gitter.im/jmespath/jmespath.rb.png)](https://gitter.im/jmespath/jmespath.rb) [![Build Status](https://travis-ci.org/jmespath/jmespath.rb.png?branch=master)](https://travis-ci.org/jmespath/jmespath.rb)

An implementation of [JMESPath](https://github.com/boto/jmespath) for Ruby. This implementation supports searching JSON documents as well as native Ruby data structures.

## Installation

```
$ gem install jmespath
```

## Basic Usage

Call `JMESPath.search` with a valid JMESPath search expression and data to search. It will return the extracted values.

```ruby
require 'jmespath'

JMESPath.search('foo.bar', { foo: { bar: { baz: "value" }}})
#=> {baz: "value"}
```

In addition to accessing nested values, you can exact values from arrays.

```ruby
JMESPath.search('foo.bar[0]', { foo: { bar: ["one", "two"] }})
#=> "one"

JMESPath.search('foo.bar[-1]', { foo: { bar: ["one", "two"] }})
#=> "two"

JMESPath.search('foo[*].name', {foo: [{name: "one"}, {name: "two"}]})
#=> ["one", "two"]
```

If you search for keys no present in the data, then `nil` is returned.

```ruby
JMESPath.search('foo.bar', { abc: "mno" })
#=> nil
```

**[See the JMESPath specification for a full list of supported search expressions.](http://jmespath.org/specification.html)**

## Indifferent Access

The examples above show JMESPath expressions used to search over hashes with symbolized keys. You can use search also for hashes with string keys or Struct objects.

```ruby
JMESPath.search('foo.bar', { "foo" => { "bar" => "value" }})
#=> "value"

data = Struct.new(:foo).new(
  Struct.new(:bar).new("value")
)
JMESPath.search('foo.bar', data)
#=> "value"
```

## JSON Documents

If you have JSON documents on disk, or IO objects that contain JSON documents, you can pass them as the data argument.

```ruby
JMESPath.search(expression, Pathname.new('/path/to/data.json'))

File.open('/path/to/data.json', 'r', encoding:'UTF-8') do |file|
  JMESPath.search(expression, file)
end
```

## Transforming Documents

`JMESPath.transform` selects nodes with a restricted JMESPath expression and replaces each selected value with the return value of a block. It returns a new document and never modifies its input.

```ruby
JMESPath.transform('items[*].price', data) { |price| price * 2 }
```

Only expressions that map back to concrete paths in the original document are supported: fields, indices, slices, filters and projections. Expressions that generate new values — functions (including `sort_by`), multi-selects, flatten, literals — are rejected with `JMESPath::Errors::UnsupportedExpressionError` before the document is inspected.

Return `JMESPath::DELETE` from the block to remove the selected node from its parent hash or array.

```ruby
# delete expired items selected by a filter
JMESPath.transform('items[?expired]', data) { JMESPath::DELETE }
```

Multiple rules can be applied in one call. Every target is resolved against the original document before any replacement is applied, so one rule never observes the effect of another. Overlapping rules (duplicate targets, or one target being an ancestor of another) raise `JMESPath::Errors::TransformConflictError`.

```ruby
JMESPath.transform({
  'items[?price > `10`].price' => ->(price) { price / 10 },
  'items[?expired]' => ->(_) { JMESPath::DELETE },
}, data)
```

If a block raises, the error is wrapped in `JMESPath::Errors::TransformError` carrying the original `#path` and `#expression`, and the input document is left unchanged. Pass `in_place: true` to mutate the input document instead of transforming a copy.

## Links of Interest

* [Release Notes](https://github.com/trevorrowe/jmespath.rb/releases)
* [License](http://www.apache.org/licenses/LICENSE-2.0)
* [JMESPath Tutorial](http://jmespath.org/tutorial.html)
* [JMESPath Specification](http://jmespath.org/specification.html)

## License

This library is distributed under the apache license, version 2.0

> Copyright 2014 Trevor Rowe; All rights reserved.
>
> Licensed under the apache license, version 2.0 (the "license");
> You may not use this library except in compliance with the license.
> You may obtain a copy of the license at:
>
> http://www.apache.org/licenses/license-2.0
>
> Unless required by applicable law or agreed to in writing, software
> distributed under the license is distributed on an "as is" basis,
> without warranties or conditions of any kind, either express or
> implied.
>
> See the license for the specific language governing permissions and
> limitations under the license.
