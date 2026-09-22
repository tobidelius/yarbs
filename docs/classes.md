# Classes, modules, and attributes

Most of a class's *structure* — nesting, superclass, mixins, visibility,
`attr_*` — comes straight from `rbs prototype rb` parsing your real Ruby
source, not from YARD docs at all. yarbs only steps in to fill in the
*types*: attribute types (from `@return`) and constant types (also from
`@return`).

The examples below are real: this exact source, run through
`yarbs "lib/**/*.rb" -o sig --strict`, produces the exact `.rbs` shown.

See [param.md](param.md)/[return.md](return.md) for method signatures and
[blocks.md](blocks.md) for `yield`/`&block`.

## Nesting

Module and class nesting is structural — yarbs doesn't need any docs to get
this right, including a class nested inside a class (not just modules):

```ruby
module Shapes
  class Circle
  end
end

class Outer
  class Inner
  end
end
```

```rbs
module Shapes
  class Circle
  end
end

class Outer
  class Inner
  end
end
```

## Inheritance and mixins

`class Circle < Shape`, `include`, `extend`, and `prepend` are all picked
up automatically:

```ruby
class Shape
  include Comparable
  extend Forwardable
end

class Circle < Shape
  # @param radius [Float] the radius
  # @return [Float] the area
  def self.area_for(radius)
    Math::PI * radius**2
  end
end
```

```rbs
class Shape
  include Comparable

  extend Forwardable
end

class Circle < Shape
  def self.area_for: (Float radius) -> Float
end
```

## `attr_reader`, `attr_writer`, `attr_accessor`

Document these the same way you'd document a method's return type — with
`@return`:

```ruby
class Shape
  # @return [String] the shape's name
  attr_reader :name

  # @return [Float] the shape's area
  attr_accessor :area

  # @return [Symbol] the token
  attr_writer :token
end
```

```rbs
class Shape
  attr_reader name: String

  attr_accessor area: Float

  attr_writer token: Symbol
end
```

`attr_writer` is worth calling out specifically: unlike `attr_reader` and
`attr_accessor`, it has no getter, so YARD only ever registers the `name=`
method for it — yarbs looks the type up there instead of at the (nonexistent)
plain `name` path.

An undocumented attribute is just `untyped`, same as everywhere else:

```ruby
class Shape
  attr_accessor :undocumented
end
```

```rbs
class Shape
  attr_accessor undocumented: untyped
end
```

## Constants

Also documented with `@return`:

```ruby
class Shape
  # @return [Integer] the max supported sides
  MAX_SIDES = 12
end
```

```rbs
class Shape
  MAX_SIDES: Integer
end
```

An undocumented constant falls back to `rbs prototype rb`'s own literal
inference rather than `untyped` — a constant assigned a string or symbol
literal, for example, gets typed as that exact literal value, which is
usually *too* narrow to be useful:

```ruby
class Shape
  UNDOCUMENTED = "hi"
end
```

```rbs
class Shape
  UNDOCUMENTED: "hi"
end
```

## Visibility

`private` works and is preserved as-is:

```ruby
class Shape
  # @return [void]
  def recalculate
  end
  private :recalculate
end
```

or the more common block form:

```ruby
class Shape
  private

  # @return [void]
  def recalculate
  end
end
```

```rbs
class Shape
  private

  def recalculate: () -> void
end
```

**`protected` is silently dropped — this is an RBS limitation, not a yarbs
one.** RBS's own method-definition AST only has `public`/`private`; there's
no `protected` concept at all, and `rbs prototype rb` doesn't even recognize
a `protected` call in your source. A method after `protected` ends up typed
exactly as if nothing had changed — public, if nothing set `private`
earlier in the class:

```ruby
class Shape
  protected

  # @return [void]
  def guarded
  end
end
```

```rbs
class Shape
  def guarded: () -> void
end
```

If you rely on `protected` for encapsulation, be aware the generated
signature doesn't restrict access at all — `private` is the closest
approximation RBS can express.

## What's *not* typed here

Instance variables get their own declarations in RBS (`@name: Type`,
separate from the accessor method), and yarbs currently leaves those as
`untyped` even when the corresponding `attr_reader`/`attr_accessor` is
fully typed:

```ruby
class Shape
  # @return [String] the shape's name
  attr_reader :name
end
```

```rbs
class Shape
  @name: untyped

  attr_reader name: String
end
```
