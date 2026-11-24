// conform: tags=scope-cleanup,diagnostics,tier-core
// conform: phase=check
// An element never leaves its list: the list closes every element it holds, so a `move`
// receiver taken from an index is rejected whatever the list is bound to.
import Closeable from "@std/core.ms"

type Item:
    label String

fn move Item.close() Void! => ok()

fn close_first(members List[Item]) Void!:
    members[0].close()?
    return ok()

fn main() Void!:
    close_first([Item("a")])?
    return ok()
