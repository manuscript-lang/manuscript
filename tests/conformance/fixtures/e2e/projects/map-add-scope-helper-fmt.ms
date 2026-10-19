# conform: tags=aliasing,formatter,maps,parser,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/testdata/projects/map_add_scope/helper.ms
export fn insert[K: Hashable, V](m: Map[K, V], key: K, value: V) Map[K, V]:
    return m.add(key, value)

export fn insert_bound[K: Hashable, V](m: Map[K, V], key: K, value: V) Map[K, V]:
    let add = m.add
    return add(value: value, key: key)
