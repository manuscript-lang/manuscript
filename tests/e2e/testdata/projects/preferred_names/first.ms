from "./domain.ms" import Key
from "./helpers.ms" import add_generic, remove_generic

impl Equal for Key:
    def equals(other: Equal) -> Bool:
        match other:
            case Key(value): return self.id == value.id
            case _: return False

impl Hashable for Key:
    def hash() -> Int: self.id

export def first_run() -> Set[Key]:
    var items = Set[Key]([Key(1, "original")])
    items.add(Key(1, "duplicate"))
    add_generic(var items, Key(2, "second"))
    items.remove(Key(1, "different"))
    remove_generic(var items, Key(8, "absent"))
    return items

export def first_add(var items: Set[Key], value: Key) -> Unit:
    items.add(value)

export def first_remove(var items: Set[Key], value: Key) -> Unit:
    items.remove(value)

export def first_empty() -> Set[Key]:
    return Set[Key]([])
