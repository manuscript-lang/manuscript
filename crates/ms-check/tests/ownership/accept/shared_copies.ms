from "@std/shared.ms" import share, Shared

type Holder:
    items: Shared[List[String]]

def child(holder: Holder) -> Holder:
    return Holder(holder.items)

def count(items: Shared[List[String]]) -> Int:
    return items.get().length()

def f() -> Int:
    let items = share(["a", "b"])
    let copy = items
    let holder = Holder(items)
    let other = child(holder)
    return count(copy) + count(other.items) + items.get().length()
