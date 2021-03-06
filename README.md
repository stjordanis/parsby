# Parsby

Parser combinator library for Ruby, based on Haskell's Parsec.

 - [Installation](#installation)
 - [Examples](#examples)
 - [Introduction](#introduction)
 - [Some commonly used combinators](#some-commonly-used-combinators)
 - [Defining combinators](#defining-combinators)
 - [Defining parsers as modules](#defining-parsers-as-modules)
 - [`ExpectationFailed`](#expectationfailed)
   - [Cleaning up the parse tree for the trace](#cleaning-up-the-parse-tree-for-the-trace)
 - [Recursive parsers with `lazy`](#recursive-parsers-with-lazy)
 - [Parsing left-recursive languages with `reduce` combinator](#parsing-leftrecursive-languages-with-reduce-combinator)
 - [`Parsby.new`](#parsbynew)
 - [Parsing from a string, a file, a pipe, a socket, ...](#parsing-from-a-string-a-file-a-pipe-a-socket-)
 - [Comparing with Haskell's Parsec](#comparing-with-haskells-parsec)
 - [Development](#development)

## Installation

Add this line to your application's Gemfile:

```ruby
gem 'parsby'
```

And then execute:

    $ bundle

Or install it yourself as:

    $ gem install parsby

## Examples

If you'd like to jump right into example parsers that use this library,
there's a few in this source:

 - [CSV (RFC 4180 compliant)](lib/parsby/example/csv_parser.rb)
 - [JSON](lib/parsby/example/json_parser.rb)
 - [Lisp](lib/parsby/example/lisp_parser.rb)
 - [Arithmetic expressions](lib/parsby/example/arithmetic_parser.rb)

## Introduction

This is a library used to define parsers by declaratively describing a
syntax using what's commonly referred to as combinators. Parser combinators
are functions that take parsers as inputs and/or return parsers as outputs,
i.e. they *combine* parsers into new parsers.

As an example, `between` is a combinator with 3 parameters: a parser for
what's to the left, one for what's to the right, and lastly one for what's
in-between them, and it returns a parser that, after parsing, returns the
result of the in-between parser:

```ruby
between(lit("<"), lit(">"), decimal).parse "<100>"
#=> 100
```

## Some commonly used combinators

```ruby
# Parse argument string literally
lit("foo").parse "foo"
#=> "foo"

# Case insensitive lit
ilit("Foo").parse "fOo"
#=> "fOo"

# Make any value into a parser that results in that value without
# consuming input.
pure("foo").parse ""
#=> "foo"

# Parse foo or bar
(lit("foo") | lit("bar")).parse "bar"
#=> "bar"

# Like `|`, parse one of foo or bar. `choice` is better when you have
# many choices to chose from. You can pass it any number of parsers or
# array of parsers.
choice(lit("foo"), lit("bar")).parse "bar"
#=> "bar"

# Parse with each argument in succesion and group the results in an
# array.
group(lit("foo"), lit("bar")).parse "foobar"
#=> ["foo", "bar"]

# Parse foo and bar, returning bar.
(lit("foo") > lit("bar")).parse "foobar"
#=> "bar"

# Parse foo and bar, returning foo.
(lit("foo") < lit("bar")).parse "foobar"
#=> "foo"

# Make parser optional
group(optional(lit("foo")), lit("bar")).parse "bar"
#=> [nil, "bar"]

# Use parser zero or more times, grouping results in array. many_1, does
# the same, but requires parsing at least once.
many(lit("foo")).parse "foofoo"
#=> ["foo", "foo"]

# Parse many, but each separated by something. sep_by_1 requires at least
# one element to be parsed.
sep_by(lit(","), lit("foo")).parse "foo,foo"
#=> ["foo", "foo"]

# `whitespace` (alias `ws`) is zero or more whitespace characters.
# `whitespace_1` (alias `ws_1`) is one or more whitespace characters.
# `spaced` allows a parser to be surrounded by optional whitespace.
# `whitespace_1` is the base definition. If you extend it to e.g. add the
# parsing of comments, the other combinators will also recognize that
# change.
(whitespace > lit("foo")).parse "   foo"
#=> "foo"
group(lit("foo"), ws_1 > lit("bar")).parse "foo   bar"
#=> ["foo", "bar"]
spaced(lit("foo")).parse "   foo    "
#=> "foo"

# Parse transform result according to block.
lit("foo").fmap {|x| x.upcase }.parse "foo"
#=> "FOO"

# join(p) is the same as p.fmap {|xs| xs.join }
join(sep_by(lit(","), lit("foo") | lit("bar"))).parse "foo,bar"
#=> "foobar"

# Parse a character from the choices in a set of strings or ranges
char_in(" \t\r\n").parse "\t"
#=> "\t"
typical_identifier_characters = ['a'..'z', 'A'..'Z', 0..9, "_"]
join(many(char_in("!?", typical_identifier_characters))).parse "foo23? bar"
#=> "foo23?"

# Parse any one character
any_char.parse "foo"
#=> "f"

# Require end of input at end of parse.
(lit("foo") < eof).parse "foobar"
#=> Parsby::ExpectationFailed: line 1:
  foobar
     |    * failure: eof
  \-/    *| success: lit("foo")
         \|
  |       * failure: (lit("foo") < eof)

# Parse only when other parser fails.
join(many(any_char.that_fails(whitespace_1))).parse "foo bar"
#=> "foo"

# single(p) is the same as p.fmap {|x| [x] }
single(lit("foo")).parse "foo"
#=> ["foo"]

# p1 + p2 is the same as group(p1, p2).fmap {|(r1, r2)| r1 + r2 }
(lit("foo") + (ws > lit("bar"))).parse "foo bar"
#=> "foobar"
(single(lit("foo")) + many(ws > lit("bar"))).parse "foo bar bar"
#=> ["foo", "bar", "bar"]
```

## Defining combinators

If you look at the examples in this source, you'll notice that almost all
combinators are defined with `define_combinator`. Strictly speaking, it's
not necessary to use that to define combinators. You can do it with
variable assignment or `def` syntax. Nevertheless, `define_combinator` is
preferred because it automates the assignment of a label to the combinator.
Consider this example:

```ruby
define_combinator :between do |left, right, p|
  left > p < right
end

between(lit("<"), lit(">"), lit("foo")).label
#=> 'between(lit("<"), lit(">"), lit("foo"))'
```

Having labels that resemble the source code is helpful for [the error
messages](#expectationfailed).

If we use `def` instead of `define_combinator`, then the label would be
that of its definition. In the following case, it would be that assigned by
`<`.

```ruby
def between(left, right, p)
  left > p < right
end

between(lit("<"), lit(">"), lit("foo")).label
#=> '((lit("<") > lit("foo")) < lit(">"))'
```

If we're to wrap that parser in a new one, then the label would be simply
unknown.

```ruby
def between(left, right, p)
  Parsby.new {|c| (left > p < right).parse c }
end

between(lit("<"), lit(">"), lit("foo")).label.to_s
#=> "unknown"
```

## Defining parsers as modules

The typical pattern I use is something like this:

```ruby
module FoobarParser
  include Parsby::Combinators
  extend self

  # Entrypoint nicety
  def parse(s)
    foobar.parse s
  end

  define_combinator :foobar do
    foo + bar
  end

  define_combinator :foo do
    lit("foo")
  end

  define_combinator :bar do
    lit("bar")
  end
end
```

From that, you can use it directly as:

```ruby
FoobarParser.parse "foobar"
#=> "foobar"
FoobarParser.foo.parse "foo"
#=> "foo"
```

Being able to use subparsers directly is useful for when you want to e.g.
parse a JSON array, instead of any JSON value.

Writing the parser as a module like that also makes it easy to make a new
parser based on it:

```ruby
module FoobarbazParser
  include FoobarParser
  extend self

  def parse(s)
    foobarbaz.parse s
  end

  define_combinator :foobarbaz do
    foobar + baz
  end

  define_combinator :baz do
    lit("baz")
  end
end
```

You can also define such a module to hold your own project's combinators to
use in multiple parsers.

## `ExpectationFailed`

Here's an example of an error, when parsing fails:

```
pry(main)> Parsby::Example::LispParser.sexp.parse "(foo `(foo ,bar) 2.3 . . nil)"    
Parsby::ExpectationFailed: line 1:
  (foo `(foo ,bar) 2.3 . . nil)
                         |           * failure: char_in("([")
                         |           * failure: list
                         |          *| failure: symbol
                         |         *|| failure: nil
                         |        *||| failure: string
                         |       *|||| failure: number
                                 \\\||
                         |          *| failure: atom
                         |         *|| failure: abbrev
                                   \\|
                         |           * failure: sexp
                       V            *| success: lit(".")
                   \-/             *|| success: sexp
       \---------/                *||| success: sexp
   \-/                           *|||| success: sexp
  V                             *||||| success: char_in("([")
                                \\\\\|
  |                                  * failure: list
  |                                  * failure: sexp
```

As can be seen, Parsby manages a tree structure representing parsers and
their subparsers, with the information of where a particular parser began
parsing, where it ended, whether it succeeded or failed, and the label of
the parser.

It might be worth mentioning that when debugging a parser from an
unexpected `ExpectationFailed` error, the backtrace isn't really useful.
That's because the backtrace points to the code involved in parsing, not
the code involved in constructing the parsers, which succeeded, but is
where the problem typically lies. The tree-looking exception message above
is meant to somewhat substitute the utility of the backtrace in these
cases.

Relating to that, the right-most text are the labels of the corresponding
parsers. I find that labels that resemble the source code are quite useful,
just like the code location descriptions that appear right-most in
backtraces. It's because of this that I consider the use of
`define_combinator` more preferable than using `def` and explicitly
assigning labels.

### Cleaning up the parse tree for the trace

If you look at the source of the example lisp parser, you might note that
there are a lot more parsers in between those shown in the tree above.
`sexp` is not a direct child of `list`, for example, despite it appearing
as so. There are at least 6 ancestors/descendant parsers between `list` and
`sexp`. It'd be very much pointless to show them all. They convey little
additional information and their labels are very verbose.

The reason why they don't appear is because the `splicer.start` combinator
is used to make the tree look a little cleaner. To show an example of how
it works, here's a simplified definition of `choice`:

```ruby
define_combinator :choice do |*ps|
  ps = ps.flatten

  ps.reduce(unparseable) do |a, p|
    a | p
  end
end
```

Let's fail it:

```
pry(main)> choice(lit("foo"), lit("bar"), lit("baz")).parse "qux"                                   
Parsby::ExpectationFailed: line 1:
  qux
  \-/    * failure: lit("baz")
  \-/   *| failure: lit("bar")
  \-/  *|| failure: lit("foo")
  |   *||| failure: unparseable
      \|||
  |    *|| failure: (unparseable | lit("foo"))
       \||
  |     *| failure: ((unparseable | lit("foo")) | lit("bar"))
        \|
  |      * failure: (((unparseable | lit("foo")) | lit("bar")) | lit("baz"))
  |      * failure: choice(lit("foo"), lit("bar"), lit("baz"))
```

Those parser intermediaries that use `|` aren't really making things any
clearer. Let's use `splicer` to remove those:

```ruby
    define_combinator :choice do |*ps|
      ps = ps.flatten

      splicer.start do |m|
        ps.reduce(unparseable) do |a, p|
          a | m.end(p)
        end
      end
    end
```

This makes the `p` parsers appear as direct children of the `splicer.start`
parser in the trace. Let's fail it, again:

```
pry(main)> choice(lit("foo"), lit("bar"), lit("baz")).parse "qux"                                  
Parsby::ExpectationFailed: line 1:
  qux
  \-/   * failure: lit("baz")
  \-/  *| failure: lit("bar")
  \-/ *|| failure: lit("foo")
      \\|
  |     * failure: splicer.start((((unparseable | splicer.end(lit("foo"))) | splicer.end(lit("bar"))) | splicer.end(lit("baz"))))
  |     * failure: choice(lit("foo"), lit("bar"), lit("baz"))
```

Now, the only issue left is that `define_combinator` wraps the resulting
parser in another parser. It does this so you can see the label assigned to
the combinator and to its definition separately. Let's disable that
wrapping by passing `wrap: false` to it:

```ruby
    define_combinator :choice, wrap: false do |*ps|
      ps = ps.flatten

      splicer.start do |m|
        ps.reduce(unparseable) do |a, p|
          a | m.end(p)
        end
      end
    end
```

That causes it to overwrite the label to the resulting parser of the block.
Let's fail it, again:

```
pry(main)> choice(lit("foo"), lit("bar"), lit("baz")).parse "qux"                                  
Parsby::ExpectationFailed: line 1:
  qux
  \-/   * failure: lit("baz")
  \-/  *| failure: lit("bar")
  \-/ *|| failure: lit("foo")
      \\|
  |     * failure: choice(lit("foo"), lit("bar"), lit("baz"))
```

## Recursive parsers with `lazy`

If we try to define a recursive parser using combinators like so:

```ruby
define_combinator :value do
  list | lit("foo")
end

define_combinator :list do
  between(lit("["), lit("]"), sep_by(lit(","), spaced(value)))
end

value
#=> SystemStackError: stack level too deep
```

We get a stack overflow.

This isn't a problem in Haskell because the language evaluates lazily by
default. This allows it to define recursive parsers without even thinking
about it.

In Ruby's case, we need to be explicit about our laziness. For that,
there's `lazy`. We just need to wrap one of the expressions in the
recursive loop with it. It could be the `value` call in `list`; it could be
`list` call in `value`; it could be the whole of `value`. It really doesn't
matter.

```ruby
define_combinator :value do
  lazy { list | lit("foo") }
end

define_combinator :list do
  between(lit("["), lit("]"), sep_by(lit(","), spaced(value)))
end

value.parse "[[[[foo, foo]]]]"
#=> [[[["foo", "foo"]]]]
```

## Parsing left-recursive languages with `reduce` combinator

Here's a little arithmetic parser based on the
`Parsby::Example::ArithmeticParser`:

```ruby
define_combinator :div_op {|left, right| group(left, spaced(lit("/")), right) }
define_combinator :mul_op {|left, right| group(left, spaced(lit("*")), right) }
define_combinator :add_op {|left, right| group(left, spaced(lit("+")), right) }
define_combinator :sub_op {|left, right| group(left, spaced(lit("-")), right) }

def scope(x, &b)
  b.call x
end

define_combinator :expr do
  lazy do
    e = decimal

    # hpe -- higher precedence level expression
    # spe -- same precedence level expression

    e = scope e do |hpe|
      recursive do |spe|
        choice(
          mul_op(hpe, spe),
          div_op(hpe, spe),
          hpe,
        )
      end
    end

    e = scope e do |hpe|
      recursive do |spe|
        choice(
          add_op(hpe, spe),
          sub_op(hpe, spe),
          hpe,
        )
      end
    end
  end
end

expr.parse "5 - 4 - 3"
#=> [5, "-", [4, "-", 3]]
```

Now, that's incorrectly right-associative because we made the
precedence-level parsers right-recursive. See how the block parameter of
`recursive` is used for the right operands and not the left ones?

Let's fix that by switching the parsers used for the operands:

```ruby
define_combinator :expr do
  lazy do
    e = decimal

    # hpe -- higher precedence level expression
    # spe -- same precedence level expression

    e = scope e do |hpe|
      recursive do |spe|
        choice(
          mul_op(spe, hpe),
          div_op(spe, hpe),
          hpe,
        )
      end
    end

    e = scope e do |hpe|
      recursive do |spe|
        choice(
          add_op(spe, hpe),
          sub_op(spe, hpe),
          hpe,
        )
      end
    end
  end
end

expr.parse "5 - 4 - 3"
# ...
```

If you ran this, it might take a while, but eventually you'll have a bunch
of `SystemStackError: stack level too deep` errors.

What's happening is that e.g. while trying to check whether the expression
is a subtraction, it needs to first resolve the left operand, and as part
of that it needs to check whether *that's* a subtraction, and so on and so
forth. In other words, this causes infinite recursion. It can't even read a
single character of the input because of this.

Our problem is that we're parsing top-down. We're trying to understand what
the whole thing is before looking at the parts. We need to parse bottom-up.
Successfully parse a small piece, then figure out what the whole thing is
as we keep reading. To do that while keeping our definitions declarative,
we can use the `reduce` combinator (in combination with `pure`):

```ruby
define_combinator :expr do
  lazy do
    e = decimal

    # hpe -- higher precedence level expression
    # spe -- same precedence level expression

    e = scope e do |hpe|
      reduce hpe do |left_result|
        choice(
          mul_op(pure(left_result), hpe),
          div_op(pure(left_result), hpe),
        )
      end
    end

    e = scope e do |hpe|
      reduce hpe do |left_result|
        choice(
          add_op(pure(left_result), hpe),
          sub_op(pure(left_result), hpe),
        )
      end
    end
  end
end

expr.parse "5 - 4 - 3"
#=> [[5, "-", 4], "-", 3]
```

`reduce` starts parsing with its argument, in this case `hpe`, then passes
the result to the block, which uses it for the resolved left operand.
`reduce` then parses with the parser returned by the block and passes the
result again to the block, and so on and so forth until parsing fails,
returning the result of the last successful parse.

In effect, we're parsing left operands bottom-up and right operands
top-down.

## `Parsby.new`

Normally one ought to be able to define parsers using just combinators, but
there are times when one might need more control. For those times, the most
raw way to define a parser is using `Parsby.new`.

Here's `lit` as an example:

```ruby
define_combinator :lit, wrap: false do |e, case_sensitive: true|
  Parsby.new do |c|
    a = c.bio.read e.length
    if case_sensitive ? a == e : a.to_s.downcase == e.downcase
      a
    else
      raise ExpectationFailed.new c
    end
  end
end
```

It takes a string argument for what it `e`xpects to parse, and returns what
was `a`ctually parsed if it matches the expectation.

The block parameter `c` is a `Parsby::Context`. `c.bio` holds a
`Parsby::BackedIO`. The `parse` method of `Parsby` objects accepts ideally
any `IO` (and `String`s, which it turns into `StringIO`) and then wraps
them with `BackedIO` to give the `IO` the ability to backtrack.

## Parsing from a string, a file, a pipe, a socket, ...

Any `IO` ought to work (unit tests currently have only checked pipes,
though). When you pass a string to `Parsby#parse` it wraps it with
`StringIO` before using it.

## Comparing with Haskell's Parsec

If you're already familiar with Parsec, here are some similarities:

```ruby
# Parsby                                 # -- Parsec
                                         #
lit("foo")                               # string "foo"
                                         #
foo | bar                                # foo <|> bar
                                         #
pure "foo"                               # pure "foo"
                                         #
foo.then {|x| bar x }                    # foo >>= \x -> bar x
                                         #
foobar = Parsby.new do |c|               # foobar = do
  x = foo.parse c                        #   x <- foo
  bar(x).parse c                         #   bar x
end                                      #
                                         #
lit("(") > foo < lit(")")                # string "(" *> foo <* string ")"
                                         #
lit("5").fmap {|n| n.to_i + 1 }          # fmap (\n -> read n + 1) (string "5")
                                         #
group(x, y, z)                           # (,,) <$> x <*> y <*> z
                                         #
group(                                   #
  w,                                     #
  group(x, y),                           #
  z,                                     #
).fmap do |(wr, (xr, yr), zr)|           #
  Foo.new(wr, Bar.new(xr, yr), zr)       # Foo <$> w <*> (Bar <$> x <*> y) <*> z
end                                      #
                                         #
                                         # -- Means the same, but this
                                         # -- raises an error in Haskell
                                         # -- because it requires an
                                         # -- infinite type [[[[...]]]]
recursive do |p|                         # fix $ \p ->
  between(lit("("), lit(")"),            #  between (string "(") (string ")") $
    single(p) | pure([])                 #    ((:[]) <$> p) <|> pure []
  end                                    #
end                                      #
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then,
run `rake spec` to run the tests. You can also run `bin/console` for an
interactive prompt that will allow you to experiment.

`bin/console` includes `Parsby::Combinators` into the top-level so the
combinators and `define_combinator` are available directly from the prompt.
It also defines `reload!` to quickly load changes made to the source.

To install this gem onto your local machine, run `bundle exec rake
install`.
