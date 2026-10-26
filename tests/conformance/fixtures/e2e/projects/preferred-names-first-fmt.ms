# conform: tags=closures,control-flow,formatter,interfaces,match,modules,parser,sets,tier-core
# conform: phase=parse
# conform: origin=tests/e2e/testdata/projects/preferred_names/first.ms
from "./domain.ms" import Key
from "./helpers.ms" import add_generic, remove_generic

impl Equal for Key:
    def equals(other: Key) -> Bool:
        return self.id == other.id

impl Hashable for Key:
    def hash() -> Int: self.id

export def first_run() -> Set[Key]:
    var items = Set[Key]([Key(1, "original")])
    let add = items.add
    let remove = items.remove
    add(Key(1, "duplicate"))
    add_generic(var items, Key(2, "second"))
    remove(Key(1, "different"))
    remove_generic(var items, Key(8, "absent"))
    return items

export def first_add(items: Set[Key]) -> Callable[[Key], Unit]:
    return items.add

export def first_remove(items: Set[Key]) -> Callable[[Key], Unit]:
    return items.remove
