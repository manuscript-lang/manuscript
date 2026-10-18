export fn insert[K: Hashable, V](m: Map[K, V], key: K, value: V) Map[K, V]:
    return m.add(key, value)

export fn insert_bound[K: Hashable, V](m: Map[K, V], key: K, value: V) Map[K, V]:
    let add = m.add
    return add(value: value, key: key)
