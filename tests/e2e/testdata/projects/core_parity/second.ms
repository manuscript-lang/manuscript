import {Key, Cause} from "./domain.ms"
import transform_set from "./helpers.ms"
import Set from "@std/collections.ms"
import {Equal, Hashable} from "@std/equality.ms"

impl Equal for Key:
    fn equals(other: Equal) -> Bool:
        match other:
            Key(value): return self.label == value.label
            _: return false

impl Hashable for Key:
    fn hash() -> Int: self.label.scalar_length()

impl Error for Cause:
    fn message() -> String: "second {self.count}"

export fn second_mapped() -> Set[Key]:
    let values = Set[Int]().with_value(1).with_value(2)
    return transform_set(
        values,
        fn(n): Key(
            0,
            n.toString()
        )
    )

export fn second_failure(cause: Cause) -> Result[String, Error]:
    let value: Result[Int, Error] = error(cause)
    return value.and_then(
        fn(n): Result[String, Error].ok(n.toString())
    )
