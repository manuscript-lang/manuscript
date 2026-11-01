# conform: tags=closures,lists,tier-io
# conform: phase=run
# conform: origin=sorted with plain Int comparators uses the integer sort; other comparators stay stable
import stdout from "@std/io/io.ms"

type Item:
    key: Int
    tag: String

fn ascending(left: Int, right: Int) Int:
    if left < right: return -1
    if left > right: return 1

    return 0

fn descending(left: Int, right: Int) Int:
    if left > right: return -1
    if left < right: return 1

    return 0

fn shifted(left: Int, right: Int) Int:
    if left < right + 1: return -1

    return 1

fn by_key(left: Item, right: Item) Int:
    return ascending(left.key, right.key)

fn tags(items: List[Item]) String:
    var out = ""
    for item in items:
        out = "{out}{item.key}{item.tag} "
    return out

export fn main() Int:
    let v = [5, 3, 9, 1, 3, 8, -2, 7, 7, 0, 100, -50, 4, 6, 2, 11, 13, 12, 10, 15, 14]
    let _a = stdout().write("{v.sorted(ascending)}\n")
    let _b = stdout().write("{v.sorted(descending)}\n")
    let _c = stdout().write("{v.sorted(shifted)}\n")
    let _d = stdout().write("{v}\n")
    let none: List[Int] = []
    let _e = stdout().write("{none.sorted(ascending)} {[4].sorted(descending)}\n")
    let items = [
        Item(key: 2, tag: "a"), Item(key: 1, tag: "b"), Item(key: 2, tag: "c"),
        Item(key: 1, tag: "d")
    ]
    let _f = stdout().write("{tags(items.sorted(by_key))}\n")
    return 0
