require_relative 'helper'

module Tvo
  class TestStuff < MiniTest::Unit::TestCase
    def tvo(code)
      Tvo::Eval.new(code).run.stack.last
    end

    def test_number
      assert_equal 1, tvo('1')
      assert_equal 4, tvo('2 2 +')
      assert_equal 2, tvo('4 2 /')
      assert tvo('2 2 =')
      refute tvo('2 3 =')
      assert tvo('3 2 >')
      assert tvo('2 3 <')

      assert_output "1\n" do
        tvo('1 .')
      end
    end

    def test_boolean
      assert tvo('true')
      refute tvo('false')
    end

    def test_prefix
      assert_equal 4, tvo('+{2 2}')
    end

    def test_dip
      assert_equal 3, tvo('1 2 4 [+] dip pop')
    end

    def test_swap
      assert_equal 1, tvo('1 2 swap')
      assert_equal 2, tvo('1 2 swap pop')
    end

    def test_dup
      assert_equal 2, tvo('1 dup +')
    end

    def test_pop
      assert_equal 1, tvo('1 2 pop')
    end

    def test_not
      assert tvo('1 2 = not')
      refute tvo('2 2 = not')
    end

    def test_branch
      assert_equal 1, tvo('2 2 = 1 2 ?')
      assert_equal 2, tvo('1 2 = 1 2 ?')
    end

    def test_if
      assert_equal 2, tvo('2 2 = [1 1 +] [2 2 +] if')
      assert_equal 4, tvo('1 2 = [1 1 +] [2 2 +] if')
    end

    def test_rec_field
      assert_equal 'Hello', tvo('rec  "Hello" =text  .text')

      refute tvo('rec ?text')
      assert tvo('rec  "Hello" =text  ?text')
    end

    def test_rec_dynamic_fields
      assert_equal 'Hello', tvo('rec  "Hello" "text" set  .text')
      assert_equal 'Hello', tvo('rec  "Hello" =text  "text" get')
    end

    def test_rec_method
      assert_equal 'Hello', tvo('rec  :hello "Hello" ;  hello')
    end

    def test_rec_dynamic_method
      assert_equal 'Hello', tvo('rec  :hello "Hello" ;  "hello" call')
    end

    def test_getter_delegation
      assert_equal 'Hello world!', tvo(<<-EOF)
        rec  "Hello " =hello
        rec  "world!" =world
        =^parent
        dup [.hello] dip
        .world
        +
      EOF
    end

    def test_method_delegation
      assert_equal 'Hello world!', tvo(<<-EOF)
        rec  :hello pop "Hello " ;
        rec  :world pop "world!" ;
        =^parent
        dup [hello] dip
        world
        +
      EOF
    end

    def test_namespace_method
      assert_equal 4, tvo(':square dup * ;  2 square')
    end
    
    def test_namespace_set
      assert_equal 4, tvo('=four{4}  four')
    end

    def test_lists
      assert tvo('list null')
      assert_equal 1, tvo('1 list cons head')
      assert tvo('1 list cons tail null')

      assert_equal 14, tvo('[1 2 3] [dup *] swap map sum')

      assert_output "1\n2\n3\n" do
        tvo('[1 2 3] [.] swap each')
      end

      assert_output "[1, 2, 3]\n" do
        tvo('[1 2 3] .')
      end
    end

    def test_eval
      assert_equal 5, tvo('"stack << 2 + 3" eval')
    end

    def test_print
      assert_output 'Hello' do
        tvo('"Hello" print')
      end
    end

    def test_puts
      assert_output "Hello\n" do
        tvo('"Hello" puts')
      end
    end
  end
end

