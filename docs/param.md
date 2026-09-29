# @param

yarbs reads ordinary YARD `@param` tags and matches them to the actual
parameter list `rbs prototype rb` found in your source (by name), so it
handles every kind of Ruby parameter — it doesn't matter what order you
document them in, only that the `@param` name matches the parameter name.

The examples below are real: this exact source, run through
`yarbs "lib/**/*.rb" -o sig --strict`, produces the exact `.rbs` shown.

See [return.md](return.md) for `@return`, including `void`,
[blocks.md](blocks.md) for `yield`/`&block` (`@yieldparam`/`@yieldreturn`),
and [classes.md](classes.md) for classes, modules, and attributes.

## Regular (required positional) parameters

```ruby
# @param name [String] the person's name
# @return [String] a greeting
def greet(name)
  "Hello, #{name}!"
end
```

```rbs
def greet: (String name) -> String
```

## Optional positional parameters (default value)

A parameter with a default value becomes an *optional* positional (`?` in
RBS) automatically — you don't need to say so in the docs, `rbs prototype rb`
already knows from the `= false` in the source.

```ruby
# @param name [String] the person's name
# @param excited [Boolean] whether to shout the greeting
# @return [String] a greeting
def greet_optionally(name, excited = false)
  excited ? "HELLO, #{name}!" : "Hello, #{name}."
end
```

```rbs
def greet_optionally: (String name, ?bool excited) -> String
```

(`Boolean` is converted to RBS's `bool`.)

## Named (keyword) parameters

Same idea: `name:` is required because it has no default, `title:` is
optional because it does.

```ruby
# @param name [String] the person's name
# @param title [String, nil] an optional title, e.g. "Dr."
# @return [String] a greeting
def greet_with_title(name:, title: nil)
  title ? "Hello, #{title} #{name}!" : "Hello, #{name}!"
end
```

```rbs
def greet_with_title: (name: String, ?title: String | nil) -> String
```

(Two `@param` types — `[String, nil]` — become the union `String | nil`.)

## `*args` (rest positional)

Document it the same way you'd document any other array-producing YARD tag:
`@param names [Array<String>]`, describing what `names` looks like *inside*
the method body. yarbs knows RBS's `*` type instead describes a single
element, and unwraps one layer of `Array` for you.

```ruby
# @param names [Array<String>] any number of names to greet
# @return [Array<String>] one greeting per name
def greet_all(*names)
  names.map { |name| "Hello, #{name}!" }
end
```

```rbs
def greet_all: (*String names) -> Array[String]
```

Note the asymmetry: the **return** type stays `Array[String]` (that's really
what gets returned), but the **parameter** type is unwrapped to `String`
(that's the type of each argument you pass in).

## `**kwargs` (rest keyword)

Same idea, with `Hash{Symbol => V}` unwrapped to just `V` (the value type —
the keys of `**kwargs` are always symbols, so RBS doesn't declare them).

```ruby
# @param greetings [Hash{Symbol => String}] name => greeting overrides
# @return [Hash{Symbol => String}] the same mapping, unchanged
def greet_custom(**greetings)
  greetings
end
```

```rbs
def greet_custom: (**String greetings) -> Hash[Symbol, String]
```

## All of them together

Ruby lets you mix every kind of parameter in one method signature, and so
does yarbs:

```ruby
# @param name [String] required positional
# @param greeting [String] optional positional
# @param args [Array<String>] rest positional (*args)
# @param loud [Boolean] required keyword
# @param title [String, nil] optional keyword
# @param kwargs [Hash{Symbol => untyped}] rest keyword (**kwargs)
# @return [String] a greeting
def greet_everything(name, greeting = "Hello", *args, loud:, title: nil, **kwargs)
  "#{greeting}, #{name}!"
end
```

```rbs
def greet_everything: (String name, ?String greeting, *String args, loud: bool, ?title: String | nil, **untyped kwargs) -> String
```

## `@option` (an options hash, typed like an interface)

YARD has a dedicated tag for documenting the individual keys of an options
hash: `@option`. RBS has a matching feature — a **record type**,
`{ key: Type, ?optional_key: Type }` — which is a shape/interface for a Hash
with known keys, distinct from a uniform `Hash[K, V]`. yarbs turns one into
the other: each `@option <param> [Type] :key ...` contributes a field to a
record built for `<param>`. Every field is optional (`?key:`), since that's
what an options hash means — you're never required to pass any particular
key, whether or not you documented a default for it.

```ruby
# @param opts [Hash] the options to create a message with
# @option opts [String] :subject the subject
# @option opts [String] :from ('nobody') from address
# @option opts [Boolean, nil] :urgent whether it's urgent
# @return [void]
def send_message(opts = {})
end
```

```rbs
def send_message: (?{ ?subject: String, ?from: String, ?urgent: bool | nil } opts) -> void
```

This works the same way for a keyword parameter:

```ruby
# @option settings [String] :name a required-looking keyword
def configure(settings:)
end
```

```rbs
def configure: (settings: { ?name: String }) -> nil
```

**`@option` doesn't apply to `*args`/`**kwargs`.** RBS's rest types (`*`/
`**`) describe a single element or value, and there's no RBS syntax for
"this specific rest keyword collects these specific named types" — so on a
`**opts` parameter, any `@option opts` tags are ignored and `opts` is typed
from its plain `@param` tag instead, same as before `@option` support
existed:

```ruby
# @param opts [Hash] options
# @option opts [String] :subject the subject
# @return [void]
def send_message(**opts)
end
```

```rbs
def send_message: (**untyped opts) -> void
```

A bare `Hash` is filled in as `Hash[untyped, untyped]` (see
[Generic types](#generic-types)), so unwrapping the rest keyword leaves
`untyped`.

If you need per-key types on a `**opts` method, document its individual
keyword parameters directly instead of using `**opts` + `@option`.

## Generic types

YARD is loose about type arguments, RBS isn't. For the core generics
(`Array`, `Set`, `Range`, `Enumerable`, `Enumerator` and `Hash`) yarbs fits
the arguments to what RBS expects, anywhere in a type:

| YARD | RBS |
| --- | --- |
| `Array` | `Array[untyped]` |
| `Hash` | `Hash[untyped, untyped]` |
| `Array<String, Regexp>` | `Array[String \| Regexp]` |
| `Enumerator<String>` | `Enumerator[String, untyped]` |

In YARD, `Array<String, Regexp>` means an array whose elements are Strings
or Regexps, which in RBS is a single union argument.

## What if a parameter isn't documented?

Nothing breaks — an undocumented parameter is just left as `untyped`, and
everything else in the signature still gets its real type. The same is true
if a `@param` type can't be converted to RBS at all (yarbs warns on stderr
and falls back to `untyped`), unless you pass `--strict`, in which case it
raises instead.
