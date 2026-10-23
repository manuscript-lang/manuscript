import Key from "./key.ms"
import remove_generic from "./generic.ms"

impl Equal for Key:
    fn equals(other: Equal) Bool:
        match other:
            Key(value): return self.label == value.label
            _: return false

impl Hashable for Key:
    fn hash() Int: self.label.scalar_length()

export fn label_map() Map[Key, Int]:
    var values = Map[Key, Int]()

    values.add(Key(1, "one"), 10)
    values.add(Key(2, "two"), 20)
    values.add(Key(3, "three"), 30)
    return values

export fn label_direct(var values: Map[Key, Int], key: Key) Unit:
    values.remove(key)

export fn label_bound(var values: Map[Key, Int], key: Key) Unit:
    let remove = values.remove

    remove(key)

export fn label_generic(var values: Map[Key, Int], key: Key) Unit:
    remove_generic(var values, key)
