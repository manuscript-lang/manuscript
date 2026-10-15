export fn transform_set[T: Hashable, U: Hashable](
    values: Set[T],
    transform: fn(value: T) -> U
) -> Set[U]:
    return values.map[U](transform)

export fn lookup[K: Hashable, V](values: Map[K, V], key: K, fallback: V) -> V:
    let get = values.get_or
    return get(key, fallback: fallback)

export fn locate_map[K: Hashable, V](
    values: Map[K, V],
    needle: K
) -> Optional[MapEntry[K, V]]:
    let find = values.find
    return find(fn(key, value): key == needle)

export fn locate_set[T: Hashable](values: Set[T], needle: T) -> Optional[T]:
    let find = values.find
    return find(fn(value): value == needle)

export fn convert[T, E](value: Optional[T], create: fn() -> E) -> Result[T, E]:
    return value.ok_or_else[E](create)

export fn remap_keys[K: Hashable, V, W: Hashable](
    values: Map[K, V],
    transform: fn(key: K, value: V) -> W
) -> Map[W, V]:
    return values.map_keys[W](transform)

export fn remap_values[K: Hashable, V, W](
    values: Map[K, V],
    transform: fn(key: K, value: V) -> W
) -> Map[K, W]:
    return values.map[W](transform)
