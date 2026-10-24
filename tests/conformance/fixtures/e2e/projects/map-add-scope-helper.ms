# conform: tags=diagnostics,maps,tier-core
# conform: phase=check
# conform: origin=tests/e2e/testdata/projects/map_add_scope/helper.ms
export def insert[K: Hashable, V](var m: Map[K, V], key: K, value: V) -> Unit:
    m.add(key, value)

export def insert_bound[K: Hashable, V](var m: Map[K, V], key: K, value: V) -> Unit:
    let add = m.add
    add(value: value, key: key)
