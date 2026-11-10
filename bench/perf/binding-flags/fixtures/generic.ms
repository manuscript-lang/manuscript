type Pair[A, B]:
    first: A
    second: B

enum Choice[T]:
    Empty
    Value(value: T)

fn first[A, B](p: Pair[A, B]) A:
    return p.first

fn optional[T](value: T) T?:
    return value

fn defaulted(value: Int = 17) Int:
    return value + 1

fn required(amount: Int) Int:
    return amount + 2

fn main() Unit:
    a := Pair(7, "a string that lives on the heap")
    b := Pair("another string that lives on the heap", 9)
    c := Choice[Pair[Int, String]].Value(Pair(13, "payload"))
    var total = first(a) + first(b).length()

    payload := match c:
        Empty: 0
        Value(value): value.first

    total += payload

    var f = defaulted
    f = required
    total += f(3)

    held := optional(Pair(5, "retained"))
    if x := held:
        total += first(x)
    print("{total}")
