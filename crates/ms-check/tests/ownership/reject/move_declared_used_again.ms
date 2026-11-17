type Item:
    name: String

fn take(move item: Item) Int:
    return item.name.length()

fn f() Int:
    it := Item("a")
    n := take(it)  // error: `it` is moved here but used again
    return n + it.name.length()
