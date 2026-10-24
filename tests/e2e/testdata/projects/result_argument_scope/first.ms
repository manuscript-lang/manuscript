from "./domain.ms" import Cause, make
from "./helper.ms" import erase, forward

impl Error for Cause[T]:
    def message() -> String: f"first {self.value}"

export def first() -> Result[Int, Error]: erase(Result[Int, Cause[Int]].error(make()))

export def first_generic() -> Result[Int, Error]: forward(
    Result[Int, Cause[Int]].error(make())
)
