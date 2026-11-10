enum Link:
    End
    More(next: Link)
    Tag(n: Int, rest: Link)

fn build(n: Int) Link:
    if n == 0:
        return End
    if n % 2 == 0:
        return More(build(n - 1))

    return Tag(n, build(n - 1))

fn sum(l: Link, acc: Int) Int:
    match l:
        End:
            return acc
        More(r):
            return sum(r, acc)
        Tag(n, r):
            return sum(r, acc + n)

export fn main() Int:
    a := build(100000)
    b := a.clone()
    if sum(a, 0) != 2500000000:
        return 1
    if sum(b, 0) != 2500000000:
        return 2

    return 0
