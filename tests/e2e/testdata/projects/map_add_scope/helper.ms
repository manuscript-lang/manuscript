export fn insert[K: Hashable, V](var m: Map[K, V], key: K, value: V) Unit:
    m.add(key, value)

export fn insert_bound[K: Hashable, V](var m: Map[K, V], key: K, value: V) Unit:
    let add = m.add
    add(value: value, key: key)
