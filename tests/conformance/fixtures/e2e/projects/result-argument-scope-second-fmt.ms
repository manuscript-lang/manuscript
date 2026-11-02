# conform: tags=control-flow,formatter,generics,interfaces,interpolation,modules,parser,strings,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/projects/result_argument_scope/second.ms
import Cause, make from "./domain.ms"
import erase, forward from "./helper.ms"

fn second_error(cause: Cause[Int]) Error: Error("second {cause.value}")

export fn second() Int!: erase(Result[Int, Cause[Int]].error(make()).map_error(second_error))

export fn second_generic() Int!: forward(
    Result[Int, Cause[Int]].error(make()).map_error(second_error)
)
