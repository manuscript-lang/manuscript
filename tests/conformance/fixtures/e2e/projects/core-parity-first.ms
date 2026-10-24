# conform: tags=aliasing,closures,control-flow,diagnostics,faults,generics,interfaces,interpolation,maps,match,modules,optional,sets,strings,tier-core,try-result
# conform: phase=check
# conform: origin=tests/e2e/testdata/projects/core_parity/first.ms
from "./domain.ms" import Key, Cause
from "./helpers.ms" import (
    transform_set,
    lookup,
    locate_map,
    locate_set,
    convert,
    remap_keys,
    remap_values
)

impl Equal for Key:
    def equals(other: Equal) -> Bool:
        match other:
            case Key(value): return self.id == value.id
            case _: return False

impl Hashable for Key:
    def hash() -> Int: self.id

impl Error for Cause:
    def message() -> String: f"first {self.count}"

export def first_mapped() -> Set[Key]:
    let values = Set[Int]([1, 2])
    return transform_set(values, lambda n: Key(0, n.to_string()))

export def first_bound_map() -> Callable[[Callable[[Int], Key]], Set[Key]]:
    return Set[Int]([1, 2]).map[Key]

export def first_generic_map[T: Hashable](values: Set[T]) -> Set[Key]:
    return transform_set(values, lambda n: Key(0, n.to_string()))

export def first_lookup() -> String:
    var values = Map[Key, String]()
    values.add(Key(5, "original"), "found")
    return values.filter(lambda k, v: True) | lookup(Key(5, "different"), "absent")

export def first_failure(cause: Cause) -> Result[String, Error]:
    let value: Result[Int, Error] = error(cause)
    return value.map(lambda n: n.to_string()).and_then(lambda text: ok(text))

export def first_queries() -> Bool:
    let key = Key(5, "original")
    var map = Map[Key, String]()
    map.add(key, "found")

    let set = Set[Key]([key])
    return (
        locate_map(map, Key(5, "different")).is_some()
        and locate_set(set, Key(5, "different")).is_some()
    )

export def first_converted(cause: Cause) -> Result[Int, Error]:
    let missing: Optional[Int] = none
    return convert(missing, lambda () -> Error: cause)

export def first_folded(cause: Cause) -> Error:
    var values = Map[String, Int]()
    values.add("key", 1)
    return values.fold[Error](cause, lambda acc, key, value: acc)

export def first_key_transform[T: Hashable](input: Map[T, Int]) -> Map[Key, Int]:
    return remap_keys(input, lambda key, value: Key(0, key.to_string()))

export def first_bound_keys() -> Callable[[Callable[[Int, Int], Key]], Map[Key, Int]]:
    var chain_1 = Map[Int, Int]()
    chain_1.add(1, 10)
    chain_1.add(2, 20)
    return chain_1.map_keys[Key]

export def first_value_transform() -> Int:
    var input = Map[Key, Int]()
    input.add(Key(5, "original"), 2)

    let mapped = remap_values(input, lambda key, value: value + 1)
    return mapped.get(Key(5, "different")).get(0)
