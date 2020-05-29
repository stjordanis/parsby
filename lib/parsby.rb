require "parsby/version"
require "parsby/combinators"

class Parsby
  extend Combinators

  class Error < StandardError; end

  class Token
    attr_reader :name

    def initialize(name)
      @name = name
    end

    def to_s
      "<#{name}>"
    end
  end

  class ExpectationFailed < Error
    attr_reader :opts

    def initialize(opts)
      @opts = opts
    end

    def message
      parts = []
      parts << "expected #{opts[:expected]}" if opts[:expected]
      parts << "actual #{opts[:actual]}" if opts[:actual]
      parts << "at #{opts[:at]}"
      parts.join(", ")
    end

    # I'd rather keep things immutable, but part of the original backtrace
    # is lost if we use a new one.
    def modify!(opts)
      self.opts.merge! opts
    end
  end

  class BackedIO
    attr_reader :backup

    def initialize(io, &b)
      @io = io
      @backup = ""
    end

    def self.for(io, &b)
      bio = new io
      begin
        b.call bio
      rescue
        bio.restore
        raise
      end
    end

    def restore
      @backup.chars.reverse.each {|c| @io.ungetc c }
      @backup = ""
      nil
    end

    def eof?
      @io.eof?
    end

    def pos
      @io.pos
    end

    def read(count)
      @io.read(count).tap {|r| @backup << r unless r.nil? }
    end

    def ungetc(c)
      @backup.slice! @backup.length - c.length
      @io.ungetc(c)
    end
  end

  def label
    @label || Token.new("unknown")
  end

  def label=(name)
    @label = name.is_a?(Symbol) ? Token.new(name) : name
  end

  def initialize(label = nil, &b)
    self.label = label if label
    @parser = b
  end

  # Parse a String or IO object.
  def parse(io)
    io = StringIO.new io if io.is_a? String
    BackedIO.for io do |bio|
      begin
        @parser.call bio
      rescue ExpectationFailed => e
        # Use the instance variable instead of the reader since the reader
        # is set-up to return an unknown token if it's nil.
        if @label
          e.modify! expected: @label
        end
        raise
      end
    end
  end

  # x | y tries y if x fails.
  def |(p)
    Parsby.new "(#{self.label} or #{p.label})" do |io|
      begin
        parse io
      rescue Error
        p.parse io
      end
    end
  end

  # x < y runs parser x then y and returns x.
  def <(p)
    Parsby.new do |io|
      r = parse io
      p.parse io
      r
    end
  end

  # x > y runs parser x then y and returns y.
  def >(p)
    Parsby.new do |io|
      parse io
      p.parse io
    end
  end

  # Set the label and return self.
  def %(name)
    self.label = name
    self
  end

  # Like map for arrays, this lets you work with the value "inside" the
  # parser, i.e. the result. decimal.fmap {|x| x + 1}.parse("2") == 3.
  def fmap(&b)
    Parsby.new do |io|
      b.call parse io
    end
  end

  # x.that_fail(y) will try y, fail if it succeeds, and parse x if it
  # fails.
  #
  # Example:
  #
  #   decimal.that_fail(string("10")).parse "3"
  #   => 3
  #   decimal.that_fail(string("10")).parse "10"
  #   => Exception
  def that_fail(p)
    Parsby.new do |bio|
      begin
        r = p.parse bio
      rescue Error
        bio.restore
        parse bio
      else
        raise ExpectationFailed.new(
          expected: "(not #{p.label})",
          actual: "#{r}",
          at: bio.pos,
        )
      end
    end
  end
end
