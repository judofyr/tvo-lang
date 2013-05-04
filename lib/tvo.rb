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

    def initialize
      @fields = {}
    end

    def copy
      dup.instance_eval do
        @fields = @fields.dup
        self
      end
    end

    def freeze
      @fields.freeze
      super
    end

    def set(name, value)
      @fields[name] = proc { stack << value }
      self
    end

    def define(name, value)
      @fields[name] = value
      self
    end

    def lookup(name)
      self.class.lookup_primitives(name) || @fields[name]
    end

    def inspect
      "Environment(#{@fields.keys.join(', ')})"
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

    prim 'tailrec' do
      recur = stack.pop
      bottom = stack.pop
      switch = stack.pop

      while true
        save = stack.dup
        apply(switch)
        res = stack.last
        self.stack = save

        if res
          apply(bottom)
          break
        else
          apply(recur)
        end
      end
    end

    ## Data structures
    prim 'rec' do
      stack << Record.new
    end

    prim 'list' do
      stack << List.new
    end

    ## Operators
    %w[+ - * /].each do |op|
      prim op do
        a = stack.pop
        b = stack.pop
        stack << b.send(op, a)
      end
    end

    prim '=' do
      a = stack.pop
      b = stack.pop
      stack << (b == a)
    end

    prim 'not' do
      stack << !stack.pop
    end

    prim '?' do
      fval = stack.pop
      tval = stack.pop
      cond = stack.pop
      stack << (cond ? tval : fval)
    end

    prim 'if' do
      fbranch = stack.pop
      tbranch = stack.pop
      cond = stack.pop
      apply(cond ? tbranch : fbranch)
    end

    ## Dynamic calls
    prim 'call' do
      name = stack.pop
      body = lookup_method(name)
      raise "no such method: #{name}" unless body
      apply(body)
    end

    prim 'get' do
      name = stack.pop
      base = stack.pop
      stack << base.get(name)
    end

    prim 'set' do
      name = stack.pop
      value = stack.pop
      base = stack.pop
      stack << base.set(name, value)
    end

    ## Libraries
    prim 'import' do
      words = stack.pop
      words.each do |word|
        env.define(word.name, List[word])
      end
    end

    prim 'load' do
      file = stack.pop
      data = File.binread(file)
      runner = Eval.new(data).run
      runner.env.set('export', runner.stack.last)
      runner.env.freeze
      stack << runner.env
    end

    prim 'eval' do
      code = stack.pop
      instance_eval(code)
    end

    ## Helpers
    prim 'print' do
      print(stack.pop)
    end

    prim 'puts' do
      puts(stack.pop)
    end

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
      if parent
        @fields.fetch(name) { parent.get(name) }
      else
        @fields.fetch(name)
      end
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
      @methods[name] || (parent.lookup(name) if parent)
    end

    def parent
      @fields['^parent']
    end
  end

  class List
    CORE = File.binread(PATH + 'list.tvo')

    extend Primitives

    def self.helper
      @helper ||= Eval.new(CORE).run.stack.last
    end

    def lookup(name)
      self.class.lookup_primitives(name) || List.helper.lookup(name)
    end
    
    attr_reader :head, :tail

    def initialize(head = nil, tail = nil)
      @head = head
      @tail = tail
      freeze
    end

    NULL = new

    def self.[](*items)
      if items.empty?
        NULL
      else
        head, *tail = *items
        new(head, self[*tail])
      end
    end

    def each
      cons = self
      while cons.tail
        yield cons.head
        cons = cons.tail
      end
      self
    end

    include Enumerable

    def inspect
      to_a.inspect
    end

    prim 'null' do
      list = stack.pop
      stack << list.tail.nil?
    end

    prim 'cons' do
      tail = stack.pop
      head = stack.pop
      stack << List.new(head, tail)
    end

    prim 'uncons' do
      list = stack.pop
      stack << list.head
      stack << list.tail
    end

    prim 'each' do
      list = stack.pop
      fn = stack.pop
      save = stack.dup
      list.each do |ele|
        stack << ele
        apply(fn)
        self.stack = save
      end
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

    WORD = /[\w*-.+\/=?^]+/
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
      when @scanner.scan(/#[^\n]+/m)
      when @scanner.scan(/#{WORD}/)
        Word.new(@scanner[0], @env)
      else
        raise "Parse error: #{@scanner.inspect}"
      end
    end

    def next_list(stop)
      res = []
      until @scanner.skip(stop)
        token = next_token
        res << token if token
      end
      List[*res]
    end

    ## Evaluator
    def call(token)
      case token
      when String, Integer, List, Record, Environment
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
        raise "Unknown type: #{token.inspect}"
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
      when List
        body.each { |token| call(token) }
      else
        raise body.inspect
      end
    end
  end
end

