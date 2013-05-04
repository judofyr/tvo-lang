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
    end
  end
end

