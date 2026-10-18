import {Key, Cause} from "./domain.ms"
import {
    transform_set,
    lookup,
    locate_map,
    locate_set,
    convert,
    remap_keys,
    remap_values
} from "./helpers.ms"

impl Equal for Key:
    fn equals(other: Equal) Bool:
        match other:
            Key(value): return self.id == value.id
            _: return false

impl Hashable for Key:
    fn hash() Int: self.id

impl Error for Cause:
    fn message() String: "first {self.count}"

export fn first_mapped() Set[Key]:
    let values = Set[Int]().add(1).add(2)
    return transform_set(values, fn(n): Key(0, n.to_string()))

export fn first_bound_map() fn(transform: fn(value: Int) Key) Set[Key]:
    return Set[Int]().add(1).add(2).map[Key]

export fn first_generic_map[T: Hashable](values: Set[T]) Set[Key]:
    return transform_set(values, fn(n): Key(0, n.to_string()))

export fn first_lookup() String:
    let values = Map[Key, String]().add(Key(5, "original"), "found")
    return values.filter(fn(k, v): true) | lookup(Key(5, "different"), "absent")

export fn first_failure(cause: Cause) Result[String, Error]:
    let value: Result[Int, Error] = error(cause)
    return value.map(fn(n): n.to_string()).and_then(fn(text): ok(text))

export fn first_queries() Bool:
    let key = Key(5, "original")
    let map = Map[Key, String]().add(key, "found")
    let set = Set[Key]().add(key)
    return (
        locate_map(map, Key(5, "different")).is_some()
        and locate_set(set, Key(5, "different")).is_some()
    )

export fn first_converted(cause: Cause) Result[Int, Error]:
    let missing: Optional[Int] = none
    return convert(missing, fn() Error: cause)

export fn first_folded(cause: Cause) Error:
    let values = Map[String, Int]().add("key", 1)
    return values.fold[Error](cause, fn(acc, key, value): acc)

export fn first_key_transform[T: Hashable](input: Map[T, Int]) Map[Key, Int]:
    return remap_keys(input, fn(key, value): Key(0, key.to_string()))

export fn first_bound_keys() fn(transform: fn(key: Int, value: Int) Key) Map[Key, Int]:
    return Map[Int, Int]().add(1, 10).add(2, 20).map_keys[Key]

export fn first_value_transform() Int:
    let input = Map[Key, Int]().add(Key(5, "original"), 2)
    let mapped = remap_values(input, fn(key, value): value + 1)
    return mapped.get(Key(5, "different")).get(0)
