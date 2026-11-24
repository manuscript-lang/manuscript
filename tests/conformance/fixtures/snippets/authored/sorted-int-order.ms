// conform: tags=closures,lists,tier-io
// conform: phase=run
// conform: origin=sorted with plain Int comparators uses the integer sort; other comparators stay stable
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
        out = f"{out}{item.key}{item.tag} "
    return out

fn main() Void:
    v := [5, 3, 9, 1, 3, 8, -2, 7, 7, 0, 100, -50, 4, 6, 2, 11, 13, 12, 10, 15, 14]
    _a := stdout().write(f"{v.sorted(ascending)}\n")
    _b := stdout().write(f"{v.sorted(descending)}\n")
    _c := stdout().write(f"{v.sorted(shifted)}\n")
    _d := stdout().write(f"{v}\n")
    null: List[Int] := []
    _e := stdout().write(f"{null.sorted(ascending)} {[4].sorted(descending)}\n")
    items := [
        Item(key: 2, tag: "a"), Item(key: 1, tag: "b"), Item(key: 2, tag: "c"),
        Item(key: 1, tag: "d")
    ]
    _f := stdout().write(f"{tags(items.sorted(by_key))}\n")
