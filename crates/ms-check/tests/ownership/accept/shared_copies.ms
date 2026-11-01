import Shared from "@std/concurrency/shared.ms"

type Holder:
    items: Shared[List[String]]

fn child(holder: Holder) Holder:
    return Holder(holder.items)

fn count(items: Shared[List[String]]) Int:
    return items.length()

fn f() Int:
    let items = Shared(["a", "b"])
    let copy = items
    let holder = Holder(items)
    let other = child(holder)
    let first = items[0]
    return count(copy) + count(other.items) + items.length() + first.length()
