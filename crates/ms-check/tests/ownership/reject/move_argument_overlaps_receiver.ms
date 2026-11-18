type Item:
    name: String

fn Item.eat(move other: Item) Int:
    return other.name.length()

fn use2(a: Item, move b: Item) Int:
    return a.name.length() + b.name.length()

fn main() Int:
    a := Item("x")
    b := Item("y")
    n := a.eat(a)  // error: argument `a` of `eat` is moved or changed in place but overlaps the receiver `a`
    return n + use2(b, b)  // error: argument `b` of `use2` is moved or changed in place but overlaps argument `b`
