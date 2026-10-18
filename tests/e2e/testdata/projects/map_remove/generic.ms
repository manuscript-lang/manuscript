export fn remove_generic[K: Hashable, V](values: Map[K, V], key: K) Map[K, V]:
    return values.remove(key)
