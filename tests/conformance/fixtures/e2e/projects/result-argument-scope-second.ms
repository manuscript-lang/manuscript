# conform: tags=control-flow,diagnostics,generics,interfaces,interpolation,modules,strings,tier-core,try-result
# conform: phase=check
# conform: origin=tests/e2e/testdata/projects/result_argument_scope/second.ms
import {Cause, make} from "./domain.ms"
import {erase, forward} from "./helper.ms"

impl Error for Cause[T]:
    fn message() String: "second {self.value}"

export fn second() Result[Int, Error]: erase(Result[Int, Cause[Int]].error(make()))

export fn second_generic() Result[Int, Error]: forward(
    Result[Int, Cause[Int]].error(make())
)
