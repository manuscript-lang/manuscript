import Cause, make from "./domain.ms"
import erase, forward from "./helper.ms"

impl Error for Cause[T]:
    fn message() String: "first {self.value}"

export fn first() Int!: erase(Result[Int, Cause[Int]].error(make()))

export fn first_generic() Int!: forward(Result[Int, Cause[Int]].error(make()))
