# conform: tags=control-flow,formatter,interfaces,match,modules,parser,sets,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/testdata/projects/preferred_names/second.ms
from "./domain.ms" import Key
from "./helpers.ms" import add_generic, remove_generic

impl Equal for Key:
    def equals(other: Equal) -> Bool:
        match other:
            case Key(value): return self.label == value.label
            case _: return False

impl Hashable for Key:
    def hash() -> Int: self.label.scalar_length()

export def second_run() -> Set[Key]:
    var items = Set[Key]([Key(1, "original")])
    let add = items.add
    let remove = items.remove
    add(Key(1, "duplicate"))
    add_generic(var items, Key(2, "original"))
    remove(Key(99, "duplicate"))
    remove_generic(var items, Key(1, "absent"))
    return items
