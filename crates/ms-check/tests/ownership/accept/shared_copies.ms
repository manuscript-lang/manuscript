import {share, Shared} from "@std/shared.ms"

type Holder:
    items: Shared[List[String]]

fn child(holder: Holder) Holder:
    return Holder(holder.items)

fn count(items: Shared[List[String]]) Int:
    return items.get().length()

fn f() Int:
    let items = share(["a", "b"])
    let copy = items
    let holder = Holder(items)
    let other = child(holder)
    return count(copy) + count(other.items) + items.get().length()
