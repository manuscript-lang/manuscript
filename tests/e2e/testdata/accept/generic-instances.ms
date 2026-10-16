import panic from "@std/faults.ms"

type Point:
    x: Int

fn ident[T](x: T) -> T:
    return x

fn pick[T](first: Bool, left: T, right: T) -> T:
    var chosen = left

    if not first:
        chosen = right

    return chosen

fn keep[T](value: T) -> T:
    let copy = value
    return copy

fn count(value: Int) -> Int:
    return value + 1

test "parametric generics keep each instantiation's values":
    if ident(x: 41) != 41: return panic("Int instance changed its value")
    if ident(x: 1.5) != 1.5: return panic("Float instance changed its value")
    if ident(x: "go") != "go": return panic("String instance changed its value")
    if not ident(x: true): return panic("Bool instance changed its value")
    if pick(first: true, left: 1, right: 2) != 1: return panic(
        "first branch selected the wrong Int"
    )
    if pick(first: false, left: "a", right: "b") != "b": return panic(
        "second branch selected the wrong String"
    )
    if keep(value: count(value: 1)) != 2: return panic(
        "argument was not evaluated once"
    )

test "instances share one identity for non-scalar arguments":
    let point = Point(x: 3)
    let same = ident(x: point)
    same.x = 4
    if point.x != 4: return panic("record identity was lost through a generic instance")

    let alias = pick(first: true, left: point, right: Point(x: 9))
    alias.x = 5
    if point.x != 5: return panic("record identity was lost through a selected branch")
