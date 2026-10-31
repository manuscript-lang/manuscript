import Key from "./domain.ms"
import add_generic, remove_generic from "./helpers.ms"

impl Equal for Key:
    fn equals(other: Key) Bool:
        return self.label == other.label

impl Hashable for Key:
    fn hash() Int: self.label.scalar_length()

export fn second_run() Set[Key]:
    var items = Set[Key]([Key(1, "original")])
    items.add(Key(1, "duplicate"))
    add_generic(var items, Key(2, "original"))
    items.remove(Key(99, "duplicate"))
    remove_generic(var items, Key(1, "absent"))
    return items
