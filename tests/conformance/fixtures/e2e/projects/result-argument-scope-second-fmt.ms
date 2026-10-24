# conform: tags=control-flow,formatter,generics,interfaces,interpolation,modules,parser,strings,tier-core,try-result
# conform: phase=parse
# conform: origin=tests/e2e/testdata/projects/result_argument_scope/second.ms
from "./domain.ms" import Cause, make
from "./helper.ms" import erase, forward

impl Error for Cause[T]:
    def message() -> String: f"second {self.value}"

export def second() -> Result[Int, Error]: erase(Result[Int, Cause[Int]].error(make()))

export def second_generic() -> Result[Int, Error]: forward(
    Result[Int, Cause[Int]].error(make())
)
