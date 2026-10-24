from "./domain.ms" import Cause, make
from "./helper.ms" import erase, forward

impl Error for Cause[T]:
    def message() -> String: f"second {self.value}"

export def second() -> Result[Int, Error]: erase(Result[Int, Cause[Int]].error(make()))

export def second_generic() -> Result[Int, Error]: forward(
    Result[Int, Cause[Int]].error(make())
)
