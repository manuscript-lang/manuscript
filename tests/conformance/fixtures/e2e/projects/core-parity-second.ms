# conform: tags=aliasing,closures,control-flow,diagnostics,faults,generics,interfaces,interpolation,maps,match,modules,optional,sets,strings,tier-core,try-result
# conform: phase=check
# conform: origin=tests/e2e/testdata/projects/core_parity/second.ms
from "./domain.ms" import Key, Cause
from "./helpers.ms" import transform_set, locate_map, locate_set, convert, remap_keys, remap_values

impl Equal for Key:
    def equals(other: Equal) -> Bool:
        match other:
            case Key(value): return self.label == value.label
            case _: return False

impl Hashable for Key:
    def hash() -> Int: self.label.scalar_length()

impl Error for Cause:
    def message() -> String: f"second {self.count}"

export def second_mapped() -> Set[Key]:
    let values = Set[Int]([1, 2])
    return transform_set(values, lambda n: Key(0, n.to_string()))

export def second_failure(cause: Cause) -> Result[String, Error]:
    let value: Result[Int, Error] = error(cause)
    return value.and_then(lambda n: Result[String, Error].ok(n.to_string()))

export def second_queries() -> Bool:
    let key = Key(5, "original")
    var map = Map[Key, String]()
    map.add(key, "found")

    let set = Set[Key]([key])
    return (
        locate_map(map, Key(5, "different")).is_none()
        and locate_set(set, Key(5, "different")).is_none()
    )

export def second_converted(cause: Cause) -> Result[Int, Error]:
    let missing: Optional[Int] = none
    return convert(missing, lambda () -> Error: cause)

export def second_folded(cause: Cause) -> Error:
    var values = Map[String, Int]()
    values.add("key", 1)
    return values.fold[Error](cause, lambda acc, key, value: acc)

export def second_key_transform[T: Hashable](input: Map[T, Int]) -> Map[Key, Int]:
    return remap_keys(input, lambda key, value: Key(0, key.to_string()))

export def second_bound_keys() -> Callable[[Callable[[Int, Int], Key]], Map[Key, Int]]:
    var chain_1 = Map[Int, Int]()
    chain_1.add(1, 10)
    chain_1.add(2, 20)
    return chain_1.map_keys[Key]

export def second_value_transform() -> Int:
    var input = Map[Key, Int]()
    input.add(Key(5, "original"), 2)

    let mapped = remap_values(input, lambda key, value: value + 1)
    return mapped.get(Key(5, "different")).get(0)
