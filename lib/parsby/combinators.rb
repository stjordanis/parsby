class Parsby
  module Combinators
    extend self

    # Parses the string as literally provided.
    def string(e)
      Parsby.new e.inspect do |io|
        a = io.read e.length
        if a == e
          a
        else
          raise ExpectationFailed.new expected: e, actual: a, at: io.pos
        end
      end
    end

    # Uses =~ for matching. Only compares one char.
    def char_matching(r)
      Parsby.new "char matching #{r.inspect}" do |io|
        pos = io.pos
        c = any_char.parse io
        unless c =~ r
          raise ExpectationFailed.new(
            actual: c,
            at: pos,
          )
        end
        c
      end
    end

    # Parses a decimal number as matched by \d+.
    def decimal
      many_1(char_matching(/\d/)).fmap {|ds| ds.join.to_i } % token("number")
    end

    # Parser that always fails without consuming input. We use it for at
    # least <tt>choice</tt>, for when it's supplied an empty list. It
    # corresponds with mzero in Haskell's Parsec.
    def fail
      Parsby.new {|io| raise ExpectationFailed.new at: io.pos }
    end

    # Tries each provided parser until one succeeds. Providing an empty
    # list causes parser to always fail, like how [].any? is false.
    def choice(*ps)
      ps = ps.flatten
      ps.reduce(fail, :|) % "(one of #{ps.map(&:label).join(", ")})"
    end

    # Parses string of 0 or more continuous whitespace characters (" ",
    # "\t", "\n", "\r")
    def whitespace
      token("whitespace") % (whitespace_1 | pure(""))
    end

    # Parses string of 1 or more continuous whitespace characters (" ",
    # "\t", "\n", "\r")
    def whitespace_1
      token("whitespace_1") % join(many_1(choice(*" \t\n\r".chars.map(&method(:string)))))
    end

    # Convinient substitute of <tt>left > p < right</tt> for when
    # <tt>p</tt> is large to write.
    def between(left, right, p)
      left > p < right
    end

    # Turns parser into one that doesn't consume input.
    def peek(p)
      Parsby.new {|io| p.peek io }
    end

    # Parser that returns provided value without consuming any input.
    def pure(x)
      Parsby.new { x }
    end

    # Delays construction of parser until parsing-time. This allows one to
    # construct recursive parsers, which would otherwise result in a
    # stack-overflow in construction-time.
    def lazy(&b)
      Parsby.new {|io| b.call.parse io }
    end

    # Results in empty array without consuming input. This is meant to be
    # used to start off use of <<.
    #
    # Example:
    #
    #   (empty << string("foo") << string("bar")).parse "foobar"
    #   => ["foo", "bar"]
    def empty
      pure []
    end

    # Groups results into an array.
    def group(*ps)
      ps = ps.flatten
      ps.reduce(empty, :<<)
    end

    # Wraps result in a list. This is to be able to do
    #
    #   single(...) + many(...)
    def single(p)
      p.fmap {|x| [x]}
    end

    # Runs parser until it fails and returns an array of the results. Because
    # it can return an empty array, this parser can never fail.
    def many(p)
      Parsby.new do |io|
        rs = []
        while true
          break if io.eof?
          begin
            rs << p.parse(io)
          rescue Error
            break
          end
        end
        rs
      end
    end

    # Same as many, but fails if it can't match even once.
    def many_1(p)
      single(p) + many(p)
    end

    # Like many, but accepts another parser for separators. It returns a list
    # of the results of the first argument. Returns an empty list if it
    # didn't match even once, so it never fails.
    def sep_by(p, s)
      sep_by_1(p, s) | empty
    end

    # Like sep_by, but fails if it can't match even once.
    def sep_by_1(p, s)
      single(p) + many(s > p)
    end

    # Join the Array result of p.
    def join(p)
      p.fmap(&:join)
    end

    # Tries the given parser and returns nil if it fails.
    def optional(p)
      Parsby.new do |io|
        begin
          p.parse io
        rescue Error
          nil
        end
      end
    end

    # Parses any char. Only fails on EOF.
    def any_char
      Parsby.new do |io|
        if io.eof?
          raise ExpectationFailed.new(
            expected: :any_char,
            actual: :eof,
            at: io.pos,
          )
        end
        io.read 1
      end
    end

    # Matches EOF, fails otherwise. Returns nil.
    def eof
      Parsby.new :eof do |io|
        unless io.eof?
          raise ExpectationFailed.new(
            at: io.pos,
            actual: (whitespace > join(many(char_matching(/\S/)))).peek(io),
          )
        end
      end
    end

    # Take characters until p matches.
    def take_until(p, with: any_char)
      Parsby.new do |io|
        r = ""
        until p.would_succeed(io)
          r << with.parse(io)
        end
        r
      end
    end

    # Makes a token with the given name.
    def token(name)
      Parsby::Token.new name
    end
  end
end
