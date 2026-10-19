# conform: tags=control-flow,diagnostics,generics,interfaces,interpolation,modules,strings,tier-core,try-result
# conform: phase=check
# conform: origin=tests/e2e/testdata/projects/result_argument_scope/first.ms
import {Cause, make} from "./domain.ms"
import {erase, forward} from "./helper.ms"

impl Error for Cause[T]:
    fn message() String: "first {self.value}"

export fn first() Result[Int, Error]: erase(Result[Int, Cause[Int]].error(make()))

export fn first_generic() Result[Int, Error]: forward(
    Result[Int, Cause[Int]].error(make())
)
