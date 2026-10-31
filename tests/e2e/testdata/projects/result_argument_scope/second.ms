import Cause, make from "./domain.ms"
import erase, forward from "./helper.ms"

impl Error for Cause[T]:
    fn message() String: "second {self.value}"

export fn second() Int!: erase(Result[Int, Cause[Int]].error(make()))

export fn second_generic() Int!: forward(Result[Int, Cause[Int]].error(make()))
