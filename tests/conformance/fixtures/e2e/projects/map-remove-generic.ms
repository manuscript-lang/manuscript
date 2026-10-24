# conform: tags=diagnostics,maps,tier-core
# conform: phase=check
# conform: origin=tests/e2e/testdata/projects/map_remove/generic.ms
export def remove_generic[K: Hashable, V](var values: Map[K, V], key: K) -> Unit:
    values.remove(key)
