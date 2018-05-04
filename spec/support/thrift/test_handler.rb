require 'thrift'
require_relative 'gen-rb/test_service'

class TestHandler
  def test_void_return
    nil
  end

  def test_primitive_return(input)
    input.mapping.values.count
  end

  def test_struct_return(structs)
    THTP::Test::Retval.number(
  end
end
