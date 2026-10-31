export fn remove_generic[K: Hashable, V](var values: Map[K, V], key: K) Unit:
    values.remove(key)
