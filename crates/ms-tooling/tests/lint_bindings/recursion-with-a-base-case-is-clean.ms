def fact(n: Int) -> Int:
    if n <= 1:
        return 1
    return n * fact(n - 1)

def sum(n: Int) -> Int:
    return 0 if n <= 0 else n + sum(n - 1)

def count(n: Int) -> Int:
    for i in 0..n:
        return i
    return count(n - 1)

def walk(n: Int) -> Int:
    if n > 0 and walk(n - 1) > 0:
        return 1
    return 0

export def main() -> Int:
    return fact(3) + sum(2) + count(1) + walk(1)
