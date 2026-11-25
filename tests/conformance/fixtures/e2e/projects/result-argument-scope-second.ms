// conform: tags=control-flow,diagnostics,generics,interfaces,interpolation,modules,strings,tier-core,try-result
// conform: phase=check
// conform: origin=tests/e2e/testdata/projects/result_argument_scope/second.ms
import (
	Cause, make from "./domain.ms",
	erase, forward from "./helper.ms",
)

fn second_error(cause Cause[Int]) Error => Error(f"second {cause.value}")

export fn second() Int! => erase(
	Result[Int, Cause[Int]].error(make()).map_error(second_error)
)

export fn second_generic() Int! => forward(
	Result[Int, Cause[Int]].error(make()).map_error(second_error)
)
// expect-error: MS2002 4:1 cannot find module ./domain.ms (looked for domain.ms); check the spelling, make sure the file exists, and that the path is relative to the importing file
