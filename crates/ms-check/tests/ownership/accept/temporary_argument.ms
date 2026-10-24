def make() -> List[Int]:
    return [1, 2]

def total(xs: List[Int]) -> Int:
    return xs.length()

def f() -> Int:
    return total(make()) + make().length()
