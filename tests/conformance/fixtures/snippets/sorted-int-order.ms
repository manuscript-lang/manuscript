# conform: tags=closures,lists,tier-io
# conform: phase=run
# conform: origin=sorted with plain Int comparators uses the integer sort; other comparators stay stable
from "@std/io.ms" import stdout

type Item:
    key: Int
    tag: String

def ascending(left: Int, right: Int) -> Int:
    if left < right: return -1
    if left > right: return 1

    return 0

def descending(left: Int, right: Int) -> Int:
    if left > right: return -1
    if left < right: return 1

    return 0

def shifted(left: Int, right: Int) -> Int:
    if left < right + 1: return -1

    return 1

def by_key(left: Item, right: Item) -> Int:
    return ascending(left.key, right.key)

def tags(items: List[Item]) -> String:
    var out = ""
    for item in items:
        out = f"{out}{item.key}{item.tag} "
    return out

export def main() -> Int:
    let v = [5, 3, 9, 1, 3, 8, -2, 7, 7, 0, 100, -50, 4, 6, 2, 11, 13, 12, 10, 15, 14]
    let a = stdout().write(f"{v.sorted(ascending)}\n")
    let b = stdout().write(f"{v.sorted(descending)}\n")
    let c = stdout().write(f"{v.sorted(shifted)}\n")
    let d = stdout().write(f"{v}\n")
    let none: List[Int] = []
    let e = stdout().write(f"{none.sorted(ascending)} {[4].sorted(descending)}\n")
    let items = [
        Item(key: 2, tag: "a"), Item(key: 1, tag: "b"), Item(key: 2, tag: "c"),
        Item(key: 1, tag: "d")
    ]
    let f = stdout().write(f"{tags(items.sorted(by_key))}\n")
    return 0
