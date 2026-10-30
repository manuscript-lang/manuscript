import Cause, make from "./domain.ms"
import erase, forward from "./helper.ms"

impl Error for Cause[T]:
    fn message() String: "second {self.value}"

export fn second() Result[Int, Error]: erase(Result[Int, Cause[Int]].error(make()))

export fn second_generic() Result[Int, Error]: forward(
    Result[Int, Cause[Int]].error(make())
)
