# @deprecated

yarbs turns YARD's `@deprecated` tag into RBS's `%a{deprecated}`
annotation. [Steep](https://github.com/soutaro/steep) acts on that
annotation: anywhere the deprecated method, attribute, constant, class or
module is used, it reports a `Ruby::DeprecatedReference` diagnostic — so the
deprecation notes you already write for humans become real warnings in your
type checker.

The examples below are real: this exact source, run through
`yarbs "lib/**/*.rb" -o sig --strict`, produces the exact `.rbs` shown.

## Methods and attributes

The tag's text becomes the annotation's message. A multi-line description is
joined onto one line, since Steep only reads the message up to the first
newline:

```ruby
class Invoice
  # @deprecated Use {#total_cents} instead, which avoids
  #   floating-point rounding.
  # @return [Float]
  def total
    total_cents / 100.0
  end

  # @return [Integer]
  def total_cents
    0
  end

  # @deprecated
  # @return [String]
  attr_reader :legacy_ref
end
```

```rbs
class Invoice
  %a(deprecated: Use {#total_cents} instead, which avoids floating-point rounding.)
  def total: () -> Float

  def total_cents: () -> Integer

  %a{deprecated}
  attr_reader legacy_ref: String
end
```

A bare `@deprecated` with no text gives a bare `%a{deprecated}`. When the
message itself contains `{…}` (as YARD links do), RBS writes the annotation
with a different delimiter, `%a(…)`, which means exactly the same thing.

## Classes, modules and constants

```ruby
module Billing
  # @deprecated Use {Billing::Invoice} instead.
  class Bill
  end

  class Invoice
    # @deprecated Use {Billing::DEFAULT_CURRENCY}.
    # @return [String]
    CURRENCY = "SEK"
  end
end
```

```rbs
module Billing
  %a(deprecated: Use {Billing::Invoice} instead.)
  class Bill
  end

  class Invoice
    %a(deprecated: Use {Billing::DEFAULT_CURRENCY}.)
    CURRENCY: String
  end
end
```

## What Steep reports

Given a caller like:

```ruby
class Checkout
  def run
    Billing::Invoice.new.total
  end
end
```

`steep check` reports:

```
lib/billing.rb:31:25: [warning] The method is deprecated: Use {#total_cents} instead, which avoids floating-point rounding.
│ Diagnostic ID: Ruby::DeprecatedReference
│
└     Billing::Invoice.new.total
                           ~~~~~
```

Note that for classes, modules and constants, Steep also warns at the
*definition* itself (`class Bill`, `CURRENCY = "SEK"`), since defining one
counts as referencing it. That's Steep's behavior for any `%a{deprecated}`,
not something yarbs adds.
