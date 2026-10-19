# conform: tags=formatter,maps,parser,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/testdata/projects/map_remove/generic.ms
export fn remove_generic[K: Hashable, V](var values: Map[K, V], key: K) Unit:
    values.remove(key)
