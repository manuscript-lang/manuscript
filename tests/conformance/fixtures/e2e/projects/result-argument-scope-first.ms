// conform: tags=control-flow,diagnostics,generics,interfaces,interpolation,modules,strings,tier-core,try-result
// conform: phase=check
// conform: origin=tests/e2e/testdata/projects/result_argument_scope/first.ms
import (
	Cause, make from "./domain.ms",
	erase, forward from "./helper.ms",
)

fn first_error(cause Cause[Int]) Error => Error(f"first {cause.value}")

export fn first() Int! => erase(
	Result[Int, Cause[Int]].error(make()).map_error(first_error)
)

export fn first_generic() Int! => forward(
	Result[Int, Cause[Int]].error(make()).map_error(first_error)
)
// expect-error: MS2002 4:1 cannot find module ./domain.ms (looked for domain.ms); check the spelling, make sure the file exists, and that the path is relative to the importing file
