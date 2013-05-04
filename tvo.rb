require 'strscan'
require 'pathname'

module Tvo
  PATH = Pathname.new('..').expand_path(__FILE__)

  module Primitives
    def primitives
      @primitives ||= {}
    end

    def prim(name, &blk)
      primitives[name] = blk
    end

    def lookup_primitives(name)
      primitives[name]
    end
  end

  class Environment
    MAIN = File.binread(PATH + 'main.tvo')

    def self.main
      @main ||= Eval.new(MAIN, new).run.env
    end

    extend Primitives

    def copy
      dup.instance_eval do
        @fields = @fields.dup
        self
      end
    end

    def initialize
      @fields = {}
    end

    def set(name, value)
      @fields[name] = [value]
      self
    end

    def define(name, value)
      @fields[name] = value
      self
    end

    def lookup(name)
      self.class.lookup_primitives(name) || @fields[name]
    end

    ### Primitives

    ## Stack primitives
    prim 'dup' do
      stack << stack.last
    end

    prim 'pop' do
      stack.pop
    end

    prim 'swap' do
      a, b = stack.pop, stack.pop
      stack << a << b
    end

    prim 'dip' do
      body = stack.pop
      top = stack.pop
      apply(body)
      stack << top
    end

    prim 'linrec' do
      after = stack.pop
      before = stack.pop
      bottom = stack.pop
      switch = stack.pop

      aux = proc do
        save = stack.dup
        apply(switch)
        res = stack.last
        self.stack = save

        if res
          apply(bottom)
        else
          apply(before)
          aux.call
          apply(after)
        end
      end

      aux[]
    end

    ## Data structures
    prim 'rec' do
      stack << Record.new
    end

    prim 'list' do
      stack << List.new
    end

    ## Operators
    prim '*' do
      stack << stack.pop * stack.pop
    end

    prim 'not' do
      stack << !stack.pop
    end

    ## Libraries
    prim 'import' do
      file = stack.pop
      data = File.binread(file)
      words = Eval.new(data).run.stack.last
      words.each do |word|
        env.define(word.name, [word])
      end
    end

    ## Helpers
    prim '.' do
      puts stack.pop.inspect
    end
  end

  class Record
    def initialize(fields = {}, methods = {})
      @fields = fields
      @methods = methods
    end

    def get(name)
      @fields.fetch(name)
    end

    def set(name, value)
      Record.new(@fields.merge(name => value), @methods)
    end

    def set?(name)
      @fields.has_key?(name)
    end

    def define(name, value)
      Record.new(@fields, @methods.merge(name => value))
    end

    def lookup(name)
      @methods[name]
    end
  end

  class List < Array
    CORE = File.binread(PATH + 'list.tvo')

    extend Primitives

    def self.helper
      @helper ||= Eval.new(CORE).run.stack.last
    end

    def lookup(name)
      self.class.lookup_primitives(name) || List.helper.lookup(name)
    end

    prim 'null' do
      list = stack.pop
      stack << list.empty?
    end

    prim 'cons' do
      list = stack.pop
      ele = stack.pop
      stack << List[ele, *list]
    end

    prim 'uncons' do
      list = stack.pop
      stack << list.first
      stack << List[*list[1..-1]]
    end
  end

  class Getter < Struct.new(:name)
  end

  class Setter < Struct.new(:name)
  end

  class Defined < Struct.new(:name)
  end

  class Define < Struct.new(:name, :body)
  end

  class Word < Struct.new(:name, :env)
    def inspect
      "Word(#{name})"
    end
  end

  class Eval
    attr_accessor :env, :stack

    def initialize(data, env = Environment.main.copy)
      @env = env
      @scanner = StringScanner.new(data)
      @stack = [@env]
      @prefix_stack = []
    end

    def run
      each_token do |token|
        call(token)
      end
      self
    end

    ## Parser
    def each_token
      until @scanner.eos?
        token = next_token
        yield token if token
      end
    end

    def next_token
      res = _next_token
      if @scanner.skip(/{/)
        @prefix_stack << res
        next_token
      else
        res
      end
    end

    WORD = /[\w*-.+\/]+/
    def _next_token
      case
      when @scanner.scan(/"(.*?)"/)
        @scanner[1]
      when @scanner.scan(/\d+/)
        @scanner[0].to_i
      when @scanner.scan(/=(#{WORD})/)
        Setter.new(@scanner[1])
      when @scanner.scan(/\.(#{WORD})/)
        Getter.new(@scanner[1])
      when @scanner.scan(/\?(#{WORD})/)
        Defined.new(@scanner[1])
      when @scanner.scan(/:(#{WORD})/)
        Define.new(@scanner[1], next_list(/;/))
      when @scanner.scan(/\[/)
        next_list(/\]/)
      when @scanner.scan(/}/)
        @prefix_stack.pop
      when @scanner.scan(/\(.*?\)/)
      when @scanner.scan(/\s+/)
      when @scanner.scan(/#{WORD}/)
        Word.new(@scanner[0], @env)
      else
        raise "Parse error: #{@scanner.inspect}"
      end
    end

    def next_list(stop)
      res = List.new
      until @scanner.skip(stop)
        token = next_token
        res << token if token
      end
      res
    end

    ## Evaluator
    def call(token)
      case token
      when String, Integer, List, Record
        @stack << token
      when Getter
        base = @stack.pop
        @stack << base.get(token.name)
      when Defined
        base = @stack.pop
        @stack << base.set?(token.name)
      when Setter
        value = @stack.pop
        base = @stack.pop
        @stack << base.set(token.name, value)
      when Define
        base = @stack.pop
        @stack << base.define(token.name, token.body)
      when Word
        body = token.env.lookup(token.name) || lookup_method(token.name)
        raise "No such word: #{token.name}" unless body
        apply(body)
      else
        raise "Unknown type: #{token}"
      end
    end

    def lookup_method(name)
      if stack.last.respond_to?(:lookup)
        stack.last.lookup(name)
      end
    end

    def apply(body)
      case body
      when Proc
        instance_eval(&body)
      when Array
        body.each { |token| call(token) }
      else
        raise body.inspect
      end
    end
  end
end

Tvo::Eval.new(File.binread(ARGV[0])).run

