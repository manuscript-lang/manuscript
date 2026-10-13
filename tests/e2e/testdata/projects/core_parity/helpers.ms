import {Map, Set} from "@std/collections.ms"
import Hashable from "@std/equality.ms"

export fn transform_set[T: Hashable, U: Hashable](
    values: Set[T],
    transform: fn(value: T) -> U
) -> Set[U]:
    return values.map[U](transform)

export fn lookup[K: Hashable, V](values: Map[K, V], key: K, fallback: V) -> V:
    let get = values.get_or
    return get(key, fallback: fallback)
