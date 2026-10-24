# conform: tags=aliasing,closures,control-flow,diagnostics,interfaces,maps,match,modules,tier-core
# conform: phase=check
# conform: origin=tests/e2e/testdata/projects/map_remove/by_id.ms
from "./key.ms" import Key
from "./generic.ms" import remove_generic

impl Equal for Key:
    def equals(other: Equal) -> Bool:
        match other:
            case Key(value): return self.id == value.id
            case _: return False

impl Hashable for Key:
    def hash() -> Int: self.id

export def id_map() -> Map[Key, Int]:
    var values = Map[Key, Int]()
    values.add(Key(1, "one"), 10)
    values.add(Key(2, "two"), 20)
    values.add(Key(3, "three"), 30)
    return values

export def id_direct(var values: Map[Key, Int], key: Key) -> Unit:
    values.remove(key)

export def id_bound(var values: Map[Key, Int], key: Key) -> Unit:
    let remove = values.remove
    remove(key)

export def id_generic(var values: Map[Key, Int], key: Key) -> Unit:
    remove_generic(var values, key)
