# Blocks (`yield` and `&block`)

yarbs reads YARD's `@yieldparam` and `@yieldreturn` tags to type a method's
own block — the thing you call with `yield` or an explicit `&block`
parameter. This is a separate mechanism from `@param`/`@option`: a block
isn't an ordinary parameter, it's its own slot in the method signature
(`{ (Integer) -> void }` in RBS).

The examples below are real: this exact source, run through
`yarbs "lib/**/*.rb" -o sig --strict`, produces the exact `.rbs` shown.

See [param.md](param.md) for `@param`/`@option`, [return.md](return.md) for
`@return`, and [classes.md](classes.md) for classes, modules, and
attributes.

## Implicit block (`yield`)

```ruby
# @yieldparam progress [Integer] percent complete
# @yieldreturn [void]
# @return [void]
def run_implicit
  yield 50
end
```

```rbs
def run_implicit: () { (Integer progress) -> void } -> void
```

`rbs prototype rb` finds the `yield 50` call site itself, so it already
knows the block takes one argument — `@yieldparam` just adds the name and
type; `@yieldreturn` types what the block itself is expected to return.

## Explicit `&block`, called rather than yielded

```ruby
# @yieldparam progress [Integer] percent complete
# @yieldreturn [Boolean] whether to continue
# @return [void]
def run_explicit(&block)
  block.call(50)
end
```

```rbs
def run_explicit: () { (Integer progress) -> bool } -> void
```

This looks identical to the `yield` case in the generated `.rbs`, but under
the hood it's a harder case: `rbs prototype rb` can only infer a block's
*arity* from a literal `yield x, y` in the method body. A block that's only
ever `.call`ed has no such call site, so structurally there's nothing to
count arguments from — yarbs falls back to building the block's signature
entirely from `@yieldparam`/`@yieldreturn`, in the order the tags are
written.

## Explicit `&block`, undocumented

If there's no `yield` in the body *and* no `@yieldparam` tags, there's
nothing to build a signature from at all, so yarbs leaves it fully
`untyped`:

```ruby
def run_explicit_undocumented(&block)
  block.call(50)
end
```

```rbs
def run_explicit_undocumented: () { (?) -> untyped } -> untyped
```

## What about `Proc`/lambda *parameters*?

A block (`yield`/`&block`) is different from an ordinary parameter that
happens to hold a `Proc` or lambda object — for example, storing a callback
and invoking it later:

```ruby
# @param callback [Proc] called with progress updates
# @return [void]
def register(callback)
  callback.call(50)
end
```

```rbs
def register: (Proc callback) -> void
```

RBS actually has a real type for a callable's full signature — a proc
literal, `^(Integer) -> void` — usable anywhere a type is expected,
including an ordinary parameter. You can't write that literally, though:
YARD's own tag parser mangles a `->` written inside `@param [...]` brackets
before yarbs ever sees the type string (`^(Integer) -> void` comes back
truncated to `^(Integer) -`, with everything from the arrow on silently
dropped) — not a yarbs limitation, an upstream YARD one.

Instead, yarbs supports a convention that sidesteps the arrow entirely:
`Proc<(ArgType, ...), ReturnType>`, which it rewrites into the proc literal
for you.

```ruby
# @param callback [Proc<(Integer), void>] called with progress updates
# @return [void]
def register(callback)
  callback.call(50)
end
```

```rbs
def register: (^(Integer) -> void callback) -> void
```

Argument and return types inside `Proc<...>` go through the same rewriting
as everywhere else, so generics nest fine:
`Proc<(Array<String>, Integer), Hash<Symbol, String>>` becomes
`^(Array[String], Integer) -> Hash[Symbol, String]`. For a zero-argument
callback, leave the parens empty: `Proc<(), void>` → `^() -> void`.

This is a yarbs-specific convention, not a YARD or RBS standard — plain
`yard doc` will show `Proc<(Integer), void>` as-is rather than rendering it
specially. If that bothers you, `[Proc]` (untyped, but universally
understood) is still a reasonable fallback.
