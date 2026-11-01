import Shared from "@std/concurrency/shared.ms"

type Holder:
    items: Shared[List[String]]

fn child(var holder: Holder) Holder:
    return Holder(holder.items)

fn count(items: Shared[List[String]]) Int:
    return items.length()

fn f() Int:
    var items = Shared(["a", "b"])
    let copy = items
    var holder = Holder(items)
    let other = child(var holder)
    let first = items[0]
    return count(copy) + count(other.items) + items.length() + first.length()
