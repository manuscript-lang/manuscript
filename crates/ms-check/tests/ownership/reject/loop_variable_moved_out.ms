def keep(xs: List[Int]) -> List[Int]:
    return xs

def f(rows: List[List[Int]]) -> Int:
    var total = 0
    for row in rows:
        total += keep(row).length()  # error: only borrows its value
    return total + rows.length()
