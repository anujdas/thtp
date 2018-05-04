namespace rb THTP.Test

typedef string error # test typedefs

const i32 ZERO = 0 # test constants

enum Operation { # test enums
  ADD = 1,
  SUBTRACT = 2,
  MULTIPLY = 3,
  DIVIDE = 4,
}

struct SetVariablesRequest { # test structs in args
  1: map<string, i32> variables, # test complex datatypes
}

struct VariablesSet {
  2: list<string> variables,
}

union RetVal {
  1: i32 result,
  2: VariablesSet variables_set,
}

exception DivideByZero { # test exceptions
  10: error error_string, # test non-incrementing field numbers
  5: i32 zero = ZERO, # test default vals
}

service CalculatorService {
  RetVal set_variables(
    10: string reason,
    1: SetVariablesRequest request,
  ) throws (
    1: OhNo oh_no_exception,
  ),

  i32 do_operation(
    99: Operation operation,
    1: i32 operand_one,
    2: i32 operand_two,
  ) throws (
    1: DivideByZero dvz_exception,
  ),
  
  RetVal test_struct_return(
    1: list<FancyStruct> structs,
  ) throws (
    1: Oops oops_exception,
  ),
  
  
  RetVal test_exception(
    1: list<FancyStruct> structs,
  ) throws (
    1: Oops oops_exception,
  ),
  
  void test_internal_error(),
}
