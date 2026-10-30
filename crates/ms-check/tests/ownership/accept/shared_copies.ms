import {new_lock, Lock} from "@std/lock.ms"

type Holder:
    items: Lock[List[String]]

fn child(holder: Holder) Holder:
    return Holder(holder.items)

fn count(items: Lock[List[String]]) Int:
    return items.get().length()

fn f() Int:
    let items = new_lock(["a", "b"])
    let copy = items
    let holder = Holder(items)
    let other = child(holder)
    return count(copy) + count(other.items) + items.get().length()
