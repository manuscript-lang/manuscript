fn keep(xs: List[Int]) List[Int]:
    return xs

fn f(rows: List[List[Int]]) Int:
    var total = 0
    for row in rows:
        total += keep(row).length()
    return total + rows.length()
