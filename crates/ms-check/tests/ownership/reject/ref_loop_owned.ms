def make() -> List[Int]:
    return [1, 2]

def total() -> Int:
    var n = 0
    for ref x in make():  # error: `for ref` borrows the elements of a variable or field
        n += x
    return n
