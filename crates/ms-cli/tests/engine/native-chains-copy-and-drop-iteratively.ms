type Link:
    case End
    case More(next: Link)
    case Tag(n: Int, rest: Link)

def build(n: Int) -> Link:
    if n == 0:
        return End
    if n % 2 == 0:
        return More(build(n - 1))
    return Tag(n, build(n - 1))

def sum(l: Link, acc: Int) -> Int:
    match l:
        case End:
            return acc
        case More(r):
            return sum(r, acc)
        case Tag(n, r):
            return sum(r, acc + n)

export def main() -> Int:
    let a = build(100000)
    let b = a.clone()
    if sum(a, 0) != 2500000000:
        return 1
    if sum(b, 0) != 2500000000:
        return 2
    return 0
