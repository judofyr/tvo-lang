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
    end

    def test_dip
      assert_equal 3, tvo('1 2 4 [+] dip pop')
    end

    def test_branch
      assert_equal 1, tvo('2 2 = 1 2 ?')
      assert_equal 2, tvo('1 2 = 1 2 ?')
    end

    def test_rec_field
      assert_equal 'Hello', tvo('rec  "Hello" =text  .text')
    end

    def test_rec_method
      assert_equal 'Hello', tvo('rec  :hello "Hello" ;  hello')
    end
  end
end

