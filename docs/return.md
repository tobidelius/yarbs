# @return

yarbs reads ordinary YARD `@return` tags and uses them as the method's
return type, unless the method is `#initialize` (see below).

The examples below are real: this exact source, run through
`yarbs "lib/**/*.rb" -o sig --strict`, produces the exact `.rbs` shown.

See [param.md](param.md) for `@param`, including `*args` and `**kwargs`,
[blocks.md](blocks.md) for `yield`/`&block` (`@yieldparam`/`@yieldreturn`),
and [classes.md](classes.md) for using `@return` on `attr_*` and constants.

## A plain return type

```ruby
# @param id [Integer] the record id
# @return [String, nil] the name, or nil if not found
def find_name(id)
  id.zero? ? nil : "name-#{id}"
end
```

```rbs
def find_name: (Integer id) -> (String | nil)
```

Multiple types in one tag — or multiple separate `@return` tags — are
unioned the same way `@param` is:

```ruby
# @param id [Integer] the record id
# @return [String] the name, if found
# @return [nil] if not found
def find_name_alt(id)
  id.zero? ? nil : "name-#{id}"
end
```

```rbs
def find_name_alt: (Integer id) -> (String | nil)
```

## `@return [void]`

`void` is a real RBS return type, meaning "this method has a return value,
but callers shouldn't rely on it" (as opposed to `nil`, which means it
always literally returns `nil`). Document it exactly like any other type:

```ruby
# @param message [String] what to log
# @return [void]
def log(message)
  puts message
end
```

```rbs
def log: (String message) -> void
```

`void` is only meaningful as a *return* type — using it as a `@param` type
doesn't make sense in RBS and will fail to parse as part of a full
signature, so avoid `@param x [void]`.

## No `@return` tag at all

yarbs falls back to whatever `rbs prototype rb` could infer from the method
body itself — a literal, best-effort guess, not necessarily correct:

```ruby
def enabled?
  true
end
```

```rbs
def enabled?: () -> bool
```

## `initialize` is always `void`

Ruby's `#initialize` return value is never used (`Foo.new` always returns
the new instance, not whatever `initialize` returns), so yarbs always keeps
`rbs prototype rb`'s `void` for it — even if you write a `@return` tag that
says otherwise, it's ignored:

```ruby
# @param name [String] the name
# @return [String] this is ignored -- initialize is always void
def initialize(name)
  @name = name
end
```

```rbs
def initialize: (String name) -> void
```

## What if a return type isn't documented?

Nothing breaks — a missing `@return` is just left as whatever
`rbs prototype rb` could infer from the method body, and everything else in
the signature still gets its real type. The same is true if a `@return`
type can't be converted to RBS at all (yarbs warns on stderr and falls back
to `untyped`), unless you pass `--strict`, in which case it raises instead.
