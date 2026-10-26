# conform: tags=aliasing,control-flow,formatter,interfaces,maps,match,modules,parser,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/testdata/projects/map_remove/by_label.ms
from "./key.ms" import Key
from "./generic.ms" import remove_generic

impl Equal for Key:
    def equals(other: Key) -> Bool:
        return self.label == other.label

impl Hashable for Key:
    def hash() -> Int: self.label.scalar_length()

export def label_map() -> Map[Key, Int]:
    var values = Map[Key, Int]()
    values.add(Key(1, "one"), 10)
    values.add(Key(2, "two"), 20)
    values.add(Key(3, "three"), 30)
    return values

export def label_direct(var values: Map[Key, Int], key: Key) -> Unit:
    values.remove(key)

export def label_bound(var values: Map[Key, Int], key: Key) -> Unit:
    let remove = values.remove
    remove(key)

export def label_generic(var values: Map[Key, Int], key: Key) -> Unit:
    remove_generic(var values, key)
