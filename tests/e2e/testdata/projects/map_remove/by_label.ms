import Key from "./key.ms"
import remove_generic from "./generic.ms"

impl Equal for Key:
    fn equals(other: Equal) -> Bool:
        match other:
            Key(value): return self.label == value.label
            _: return false

impl Hashable for Key:
    fn hash() -> Int: self.label.scalar_length()

export fn label_map() -> Map[Key, Int]:
    return (
        Map[Key, Int]()
        .add(Key(1, "one"), 10)
        .add(Key(2, "two"), 20)
        .add(Key(3, "three"), 30)
    )

export fn label_direct(values: Map[Key, Int], key: Key) -> Map[Key, Int]:
    return values.remove(key)

export fn label_bound(values: Map[Key, Int], key: Key) -> Map[Key, Int]:
    let remove = values.remove
    return remove(key)

export fn label_generic(values: Map[Key, Int], key: Key) -> Map[Key, Int]:
    return remove_generic(values, key)
