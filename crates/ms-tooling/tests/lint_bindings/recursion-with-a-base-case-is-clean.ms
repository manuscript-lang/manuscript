fn fact(n: Int) Int:
    if n <= 1:
        return 1

    return n * fact(n - 1)

fn sum(n: Int) Int:
    return if n <= 0: 0 else: n + sum(n - 1)

fn count(n: Int) Int:
    for i in 0..n:
        return i
    return count(n - 1)

fn walk(n: Int) Int:
    if n > 0 and walk(n - 1) > 0:
        return 1

    return 0

export fn main() Int:
    return fact(3) + sum(2) + count(1) + walk(1)
