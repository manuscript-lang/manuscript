# conform: tags=control-flow,diagnostics,generics,interfaces,interpolation,modules,strings,tier-core,try-result
# conform: phase=check
# conform: origin=tests/e2e/testdata/projects/result_argument_scope/first.ms
from "./domain.ms" import Cause, make
from "./helper.ms" import erase, forward

impl Error for Cause[T]:
    def message() -> String: f"first {self.value}"

export def first() -> Result[Int, Error]: erase(Result[Int, Cause[Int]].error(make()))

export def first_generic() -> Result[Int, Error]: forward(
    Result[Int, Cause[Int]].error(make())
)
