# conform: tags=closures,diagnostics,generics,maps,optional,sets,tier-core,try-result
# conform: phase=check
# conform: origin=tests/e2e/testdata/projects/core_parity/helpers.ms
export def transform_set[T: Hashable, U: Hashable](
    values: Set[T],
    transform: Callable[[T], U]
) -> Set[U]:
    return values.map[U](transform)

export def lookup[K: Hashable, V](values: Map[K, V], key: K, fallback: V) -> V:
    let get = values.get_or
    return get(key, fallback)

export def locate_map[K: Hashable, V](
    values: Map[K, V],
    needle: K
) -> Optional[MapEntry[K, V]]:
    let find = values.find
    return find(lambda key, value: key == needle)

export def locate_set[T: Hashable](values: Set[T], needle: T) -> Optional[T]:
    let find = values.find
    return find(lambda value: value == needle)

export def convert[T, E: Error](value: Optional[T], create: Callable[[], E]) -> Result[T, E]:
    return value.ok_or_else[E](create)

export def remap_keys[K: Hashable, V, W: Hashable](
    values: Map[K, V],
    transform: Callable[[K, V], W]
) -> Map[W, V]:
    return values.map_keys[W](transform)

export def remap_values[K: Hashable, V, W](
    values: Map[K, V],
    transform: Callable[[K, V], W]
) -> Map[K, W]:
    return values.map[W](transform)
