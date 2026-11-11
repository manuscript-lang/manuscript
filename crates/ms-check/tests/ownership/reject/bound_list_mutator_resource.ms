import Closeable from "@std/core.ms"

type Item:
    label: String

fn var Item.close() Unit!: ok(unit)

fn demo() Unit:
    var items = [Item("old")]
    set := items.set  // error: this method value stores its argument in the receiver, so it clones `Item`, which has one owner and cannot be cloned; use it in place
    set(0, Item("new"))
