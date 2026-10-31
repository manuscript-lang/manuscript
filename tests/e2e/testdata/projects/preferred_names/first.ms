import Key from "./domain.ms"
import add_generic, remove_generic from "./helpers.ms"

impl Equal for Key:
    fn equals(other: Key) Bool:
        return self.id == other.id

impl Hashable for Key:
    fn hash() Int: self.id

export fn first_run() Set[Key]:
    var items = Set[Key]([Key(1, "original")])
    items.add(Key(1, "duplicate"))
    add_generic(var items, Key(2, "second"))
    items.remove(Key(1, "different"))
    remove_generic(var items, Key(8, "absent"))
    return items

export fn first_add(var items: Set[Key], value: Key) Unit:
    items.add(value)

export fn first_remove(var items: Set[Key], value: Key) Unit:
    items.remove(value)

export fn first_empty() Set[Key]:
    return Set[Key]([])
