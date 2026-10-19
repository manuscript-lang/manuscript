# conform: tags=aliasing,formatter,maps,parser,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/testdata/projects/map_add_scope/helper.ms
export fn insert[K: Hashable, V](var m: Map[K, V], key: K, value: V) Unit:
    m.add(key, value)

export fn insert_bound[K: Hashable, V](var m: Map[K, V], key: K, value: V) Unit:
    let add = m.add
    add(value: value, key: key)
