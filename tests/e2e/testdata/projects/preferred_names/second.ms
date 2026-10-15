import Key from "./domain.ms"
import {add_generic, remove_generic} from "./helpers.ms"

impl Equal for Key:
    fn equals(other: Equal) -> Bool:
        match other:
            Key(value): return self.label == value.label
            _: return false

impl Hashable for Key:
    fn hash() -> Int: self.label.scalar_length

export fn second_run() -> Set[Key]:
    let items = Set[Key]().add(Key(1, "original"))
    let add = items.add
    let remove = items.remove
    add(Key(1, "duplicate"))
    add_generic(items, Key(2, "original"))
    remove(Key(99, "duplicate"))
    remove_generic(items, Key(1, "absent"))
    return items
