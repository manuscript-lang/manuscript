import {Key, Cause} from "./domain.ms"
import {transform_set, locate_map, locate_set, convert, remap_keys, remap_values} from "./helpers.ms"

impl Equal for Key:
    fn equals(other: Equal) Bool:
        match other:
            Key(value): return self.label == value.label
            _: return false

impl Hashable for Key:
    fn hash() Int: self.label.scalar_length()

impl Error for Cause:
    fn message() String: "second {self.count}"

export fn second_mapped() Set[Key]:
    let values = Set[Int]([1, 2])
    return transform_set(values, fn(n): Key(0, n.to_string()))

export fn second_failure(cause: Cause) Result[String, Error]:
    let value: Result[Int, Error] = error(cause)
    return value.and_then(fn(n): Result[String, Error].ok(n.to_string()))

export fn second_queries() Bool:
    let key = Key(5, "original")
    var map = Map[Key, String]()
    map.add(key.clone(), "found")

    let set = Set[Key]([key])
    return (
        locate_map(map, Key(5, "different")).is_none()
        and locate_set(set, Key(5, "different")).is_none()
    )

export fn second_converted(cause: Cause) Result[Int, Error]:
    let missing: Optional[Int] = none
    return convert(missing, fn() Error: cause)

export fn second_folded(cause: Cause) Error:
    var values = Map[String, Int]()
    values.add("key", 1)
    return values.fold[Error](cause, fn(acc, key, value): acc)

export fn second_key_transform[T: Hashable](input: Map[T, Int]) Map[Key, Int]:
    return remap_keys(input, fn(key, value): Key(0, key.to_string()))

export fn second_bound_keys() fn(transform: fn(key: Int, value: Int) Key) Map[Key, Int]:
    var chain_1 = Map[Int, Int]()
    chain_1.add(1, 10)
    chain_1.add(2, 20)
    return chain_1.map_keys[Key]

export fn second_value_transform() Int:
    var input = Map[Key, Int]()
    input.add(Key(5, "original"), 2)

    let mapped = remap_values(input, fn(key, value): value + 1)
    return mapped.get(Key(5, "different")).get(0)
