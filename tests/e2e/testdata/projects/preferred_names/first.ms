import Key from "./domain.ms"
import {add_generic, remove_generic} from "./helpers.ms"

impl Equal for Key:
    fn equals(other: Equal) Bool:
        match other:
            Key(value): return self.id == value.id
            _: return false

impl Hashable for Key:
    fn hash() Int: self.id

export fn first_run() Set[Key]:
    var items = Set[Key]([Key(1, "original")])
    let add = items.add
    let remove = items.remove

    add(Key(1, "duplicate"))
    add_generic(var items, Key(2, "second"))
    remove(Key(1, "different"))
    remove_generic(var items, Key(8, "absent"))
    return items

export fn first_add(items: Set[Key]) fn(value: Key) Unit:
    return items.add

export fn first_remove(items: Set[Key]) fn(value: Key) Unit:
    return items.remove
