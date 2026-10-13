import {Key, Cause} from "./domain.ms"
import {transform_set, locate_map, locate_set, convert} from "./helpers.ms"
import {Map, Set} from "@std/collections.ms"
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

export fn second_queries() -> Bool:
    let key = Key(5, "original")
    let map = Map[Key, String]().with_entry(key, "found")
    let set = Set[Key]().with_value(key)
    return (
        locate_map(
            map,
            Key(5, "different")
        ).is_none()
        and locate_set(
            set,
            Key(5, "different")
        ).is_none()
    )

export fn second_converted(cause: Cause) -> Result[Int, Error]:
    let missing: Optional[Int] = none
    return convert(
        missing,
        fn() -> Error: cause
    )

export fn second_folded(cause: Cause) -> Error:
    let values = Map[String, Int]().with_entry("key", 1)
    return values.fold[Error](
        cause,
        fn(acc, key, value): acc
    )
