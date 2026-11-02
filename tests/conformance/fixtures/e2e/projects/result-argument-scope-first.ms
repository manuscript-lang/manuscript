# conform: tags=control-flow,diagnostics,generics,interfaces,interpolation,modules,strings,tier-core,try-result
# conform: phase=check
# conform: origin=tests/e2e/testdata/projects/result_argument_scope/first.ms
import Cause, make from "./domain.ms"
import erase, forward from "./helper.ms"

fn first_error(cause: Cause[Int]) Error: Error("first {cause.value}")

export fn first() Int!: erase(Result[Int, Cause[Int]].error(make()).map_error(first_error))

export fn first_generic() Int!: forward(
    Result[Int, Cause[Int]].error(make()).map_error(first_error)
)
